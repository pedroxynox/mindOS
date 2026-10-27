"""Expense detection (mejoras-v2 §E): the money-cue pre-filter, output
normalisation, the pipeline wiring (second call only on a cue, best effort,
idempotent) and the offline expense eval."""

import json
from datetime import UTC, datetime

import pytest

from app.eval.expenses_eval import (
    ExpenseThresholds,
    load_expense_cases,
    render_expense_report,
    run_expense_eval,
)
from app.eval.run_eval import main as run_eval_main
from app.providers.base import AIProvider, Completion, Embedding, Usage
from app.providers.fake_provider import FakeProvider
from app.understanding.expenses import (
    EXPENSE_CATEGORIES,
    detect_expenses,
    has_money_cue,
    parse_amount,
    parse_expenses,
)
from app.understanding.extract import EXTRACTION_PROMPT_VERSION
from app.understanding.pipeline import Outcome, run_understanding
from app.understanding.store import InMemoryGraphStore

USER = "user-1"
CAP = "cap-1"


@pytest.mark.parametrize(
    "text",
    [
        "Hoy gasté R$ 45,90 en el almuerzo",
        "Uber 18 €",
        "paid $12 for lunch",
        "Gastei 60 reais no mercado",
        "35.000 COP de internet",
        "me salió 20 la entrada",
        "Compré pan, 3 pesos",
    ],
)
def test_money_cue_detects_spending(text: str) -> None:
    assert has_money_cue(text)


@pytest.mark.parametrize(
    "text",
    [
        "Llamar a Lucas a las 5",
        "Reunión con Marcos el martes 12",
        "Es un problema real del equipo",
        "Leer 20 páginas del libro",
        "",
    ],
)
def test_money_cue_skips_notes_without_money(text: str) -> None:
    assert not has_money_cue(text)


def test_every_annotated_expense_passes_the_cue() -> None:
    # The pre-filter must never hide a real expense from the model.
    for case in load_expense_cases():
        if case.gold:
            assert has_money_cue(case.text), case.id


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        (20, 20.0),
        ("12,5", 12.5),
        ("1.234,50", 1234.5),
        ("1,234.50", 1234.5),
        ("1.500", 1500.0),
        ("1,500", 1500.0),
        ("$ 20", 20.0),
        ("-5", None),
        ("veinte", None),
        (True, None),
    ],
)
def test_parse_amount(raw: object, expected: float | None) -> None:
    assert parse_amount(raw) == expected


def test_parse_expenses_normalises_and_drops_invalid_items() -> None:
    raw = json.dumps(
        {
            "expenses": [
                {"amount": "45,90", "currency": "brl", "category": "FOOD",
                 "description": "  almuerzo   con Ana "},
                {"amount": 10, "currency": "reais", "category": "comida"},
                {"amount": 0, "category": "food"},
                {"amount": -3, "category": "food"},
                "not an object",
            ]
        }
    )
    items = parse_expenses(raw)

    assert [(i.amount, i.currency, i.category) for i in items] == [
        (45.9, "BRL", "food"),
        (10.0, None, "other"),
    ]
    assert items[0].description == "almuerzo con Ana"
    assert all(i.category in EXPENSE_CATEGORIES for i in items)


@pytest.mark.parametrize("raw", ["not json", "[]", '{"items": []}'])
def test_parse_expenses_rejects_the_wrong_shape(raw: str) -> None:
    with pytest.raises(ValueError):
        parse_expenses(raw)


class _SpyProvider(FakeProvider):
    """FakeProvider that counts calls and can break the expense call."""

    def __init__(self, *, expense_output: str | None = None,
                 expense_error: Exception | None = None) -> None:
        self.calls = 0
        self._expense_output = expense_output
        self._expense_error = expense_error

    async def complete(self, prompt: str, *, schema: dict | None = None) -> Completion:
        self.calls += 1
        is_expense = schema is not None and "expenses" in schema.get("properties", {})
        if is_expense and self._expense_error is not None:
            raise self._expense_error
        if is_expense and self._expense_output is not None:
            usage = Usage("fake", "fake-extract-1", "complete", 1, 1, 0.0)
            return Completion(text=self._expense_output, usage=usage)
        return await super().complete(prompt, schema=schema)


async def test_no_model_call_without_a_money_cue() -> None:
    provider = _SpyProvider()
    result = await detect_expenses("Llamar a Marcos mañana", provider)
    assert result.expenses == [] and result.usage is None
    assert provider.calls == 0


async def test_invalid_model_output_yields_no_expenses() -> None:
    provider = _SpyProvider(expense_output="definitely not json")
    result = await detect_expenses("Gasté 20 dólares", provider)
    assert result.expenses == []
    assert result.usage is not None  # the call still cost something


def _store(body: str, **kwargs: object) -> InMemoryGraphStore:
    store = InMemoryGraphStore()
    store.seed_capture(USER, CAP, body=body, **kwargs)  # type: ignore[arg-type]
    return store


def _expenses(store: InMemoryGraphStore) -> list[dict]:
    return [
        n for n in store.nodes_for(USER)
        if n["attributes"].get("kind") == "expense"
    ]


async def test_pipeline_writes_detected_expenses_with_provenance() -> None:
    occurred = datetime(2026, 10, 26, 13, 30, tzinfo=UTC)
    store = _store(
        "Gasté 20 en el super y un Uber de R$ 15.",
        occurred_at=occurred,
        user_currency="brl",
    )

    result = await run_understanding(CAP, USER, provider=FakeProvider(), store=store)

    assert result.outcome is Outcome.PROCESSED
    expenses = sorted(_expenses(store), key=lambda n: n["attributes"]["amount"])
    found = [
        (a["amount"], a["currency"], a["category"])
        for a in (n["attributes"] for n in expenses)
    ]
    assert found == [(15.0, "BRL", "transport")]
    expense = expenses[0]
    assert expense["type"] == "note" and expense["origin"] == "ai"
    assert expense["attributes"]["spent_at"] == "2026-10-26T13:30:00.000Z"
    assert expense["attributes"]["capture_id"] == CAP
    provenance = [
        e for e in store.edges_for(USER)
        if e["source_node_id"] == expense["id"] and e["type"] == "derived_from"
    ]
    assert len(provenance) == 1 and provenance[0]["target_node_id"] == CAP
    # extraction + expense call + embedding, each with its cost row.
    operations = [u["operation"] for u in store.llm_usage]
    assert operations == ["complete", "complete", "embed"]


async def test_ambiguous_currency_falls_back_to_the_users_then_usd() -> None:
    store = _store("Paid $12 for lunch", user_currency="MXN")
    await run_understanding(CAP, USER, provider=FakeProvider(), store=store)
    assert [n["attributes"]["currency"] for n in _expenses(store)] == ["MXN"]

    other = _store("Paid $12 for lunch")
    await run_understanding(CAP, USER, provider=FakeProvider(), store=other)
    assert [n["attributes"]["currency"] for n in _expenses(other)] == ["USD"]


async def test_capture_without_money_makes_no_second_call() -> None:
    store = _store("Call Ana tomorrow about the invoice.")
    await run_understanding(CAP, USER, provider=FakeProvider(), store=store)
    assert _expenses(store) == []
    assert [u["operation"] for u in store.llm_usage] == ["complete", "embed"]


async def test_a_failing_expense_call_never_fails_the_capture() -> None:
    provider = _SpyProvider(expense_error=RuntimeError("boom"))
    store = _store("Gasté R$ 30 en el almuerzo con Ana")

    result = await run_understanding(CAP, USER, provider=provider, store=store)

    assert result.outcome is Outcome.PROCESSED
    assert _expenses(store) == []
    assert any(n["type"] == "person" for n in store.nodes_for(USER))


async def test_expenses_are_idempotent_and_identical_ones_are_kept() -> None:
    output = json.dumps(
        {"expenses": [
            {"amount": 5, "currency": "EUR", "category": "food", "description": "café"},
            {"amount": 5, "currency": "EUR", "category": "food", "description": "café"},
        ]}
    )
    store = _store("Dos cafés de 5 euros")
    provider = _SpyProvider(expense_output=output)
    await run_understanding(CAP, USER, provider=provider, store=store)
    assert len(_expenses(store)) == 2

    # Redelivery after a crash: same plan, same keys, no duplicates.
    store.seed_capture(USER, CAP, body="Dos cafés de 5 euros", status="raw")
    await run_understanding(CAP, USER, provider=provider, store=store)
    assert len(_expenses(store)) == 2


def test_the_v8_prompt_is_untouched() -> None:
    assert EXTRACTION_PROMPT_VERSION == "v8"


async def test_offline_expense_eval_runs_and_reports() -> None:
    cases = load_expense_cases()
    assert len(cases) >= 20
    report, errors = await run_expense_eval(FakeProvider(), cases)

    assert errors == []
    assert len(report.scores) == len(cases)
    assert report.cue_recall == 1.0
    text = render_expense_report(report, ExpenseThresholds(), "fake")
    assert "Expense detection eval" in text and "VERDICT" in text


def test_cli_runs_the_expense_suite(capsys: pytest.CaptureFixture[str]) -> None:
    assert run_eval_main(["--suite", "expenses", "--provider", "fake"]) == 0
    assert "expenses-v1" in capsys.readouterr().out


class _SilentModel(AIProvider):
    """Only to prove the eval needs nothing but ``complete``."""

    async def complete(self, prompt: str, *, schema: dict | None = None) -> Completion:
        return Completion('{"expenses": []}', Usage("x", "m", "complete", 0, 0, 0.0))

    async def embed(self, text: str) -> Embedding:  # pragma: no cover
        raise AssertionError("not used")

    async def transcribe(  # pragma: no cover
        self,
        audio_bytes: bytes,
        content_type: str,
        *,
        duration_s: float | None = None,
    ) -> Completion:
        raise AssertionError("not used")


async def test_an_empty_model_scores_zero_recall_but_no_false_expenses() -> None:
    report, _ = await run_expense_eval(_SilentModel(), load_expense_cases())
    assert report.recall == 0.0
    assert report.false_expense_rate == 0.0
