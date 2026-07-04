"""Tests for the eval runner and the acceptance-gate logic."""

import asyncio
from unittest import mock

import httpx
import pytest
from hypothesis import given
from hypothesis import settings as hyp_settings
from hypothesis import strategies as st

from app.config import settings
from app.eval.loader import EvalCase, EvalDataset, load_dataset
from app.eval.metrics import aggregate
from app.eval.run_eval import (
    EXIT_PROVIDER_UNAVAILABLE,
    _describe_provider_error,
    main,
    render_report,
    run_eval,
    thresholds_from_settings,
)
from app.providers.base import AIProvider, Completion, Embedding
from app.providers.fake_provider import FakeProvider
from app.understanding.extract import Extraction


def test_dataset_loads_expected_cases() -> None:
    dataset = load_dataset()
    # Eval set expanded to ~45 cases for a stable, low-noise measurement (R-001).
    assert 40 <= len(dataset) <= 50
    ids = [c.id for c in dataset.cases]
    assert ids == sorted(ids)  # deterministic ordering
    assert len(set(ids)) == len(ids)  # unique ids


async def test_run_eval_over_dataset_produces_bounded_metrics() -> None:
    dataset = load_dataset()
    report, _ = await run_eval(FakeProvider(), dataset)
    assert report.n_cases == len(dataset)
    assert 0.0 <= report.entity.f1 <= 1.0
    assert 0.0 <= report.task.precision <= 1.0
    assert 0.0 <= report.hallucination_rate <= 1.0
    # FakeProvider has zero cost.
    assert report.mean_cost_usd == 0.0


async def test_render_report_contains_verdict() -> None:
    dataset = load_dataset()
    report, _ = await run_eval(FakeProvider(), dataset)
    text = render_report(report, thresholds_from_settings(settings), "fake")
    assert "VERDICT" in text
    assert "Comprehension Evaluation Report" in text


def test_empty_report_gate_passes_trivially() -> None:
    # No cases -> perfect P/R (vacuously), zero hallucination/cost -> gate passes.
    report = aggregate([])
    passed, failures = report.gate(thresholds_from_settings(settings))
    assert passed is True
    assert failures == []


def test_main_returns_zero_without_gate() -> None:
    # Report-only mode always exits 0 regardless of thresholds.
    assert main(["--provider", "fake"]) == 0


def test_main_gate_mode_returns_int() -> None:
    # Gate mode returns 0 (pass) or 1 (fail); with the fake baseline + provisional
    # thresholds this exercises the non-zero path used by future CI.
    code = main(["--provider", "fake", "--gate"])
    assert code in (0, 1)


class _RateLimitedProvider(AIProvider):
    """Provider whose calls always raise a rate-limit error (post-retries)."""

    async def complete(
        self, prompt: str, *, schema: dict | None = None
    ) -> Completion:
        from openai import RateLimitError

        response = httpx.Response(
            429, request=httpx.Request("POST", "https://api.openai.com/v1/x")
        )
        raise RateLimitError("429 Too Many Requests", response=response, body=None)

    async def embed(self, text: str) -> Embedding:  # pragma: no cover - unused
        raise NotImplementedError

    async def transcribe(
        self, audio_bytes: bytes, content_type: str
    ) -> Completion:  # pragma: no cover - unused
        raise NotImplementedError


def test_main_reports_clear_message_on_rate_limit(
    capsys: pytest.CaptureFixture[str],
) -> None:
    # With per-case isolation, a provider that errors on EVERY case makes the
    # run complete with zero scored cases; main must still return exit 2 and
    # surface the un-evaluated section with the raw provider detail (not abort).
    dataset = load_dataset()
    with mock.patch(
        "app.eval.run_eval.build_provider", return_value=_RateLimitedProvider()
    ):
        code = main(["--provider", "openai"])
    assert code == EXIT_PROVIDER_UNAVAILABLE
    err = capsys.readouterr().err
    assert "RateLimitError" in err
    assert "429" in err
    # Every case is un-evaluated when the provider errors on all of them.
    assert f"CASOS NO EVALUADOS (provider error): {len(dataset)}" in err



# --- Task 1: bug-condition exploration -------------------------------------
class _FailOnCaseProvider(AIProvider):
    """Wraps ``FakeProvider`` but raises a provider error for one target case.

    When the prompt contains ``fail_substring`` (a substring unique to the
    target case's text) it raises an OpenAI-style ``RateLimitError`` built from
    an offline ``httpx.Response(429)`` with a ``body`` (no network). Every other
    case is delegated to ``FakeProvider.complete`` so the run has real scores to
    aggregate.
    """

    def __init__(self, fail_substring: str) -> None:
        self._fail_substring = fail_substring
        self._delegate = FakeProvider()

    async def complete(
        self, prompt: str, *, schema: dict | None = None
    ) -> Completion:
        if self._fail_substring in prompt:
            from openai import RateLimitError

            response = httpx.Response(
                429,
                request=httpx.Request("POST", "https://api.openai.com/v1/x"),
            )
            raise RateLimitError(
                "429 Too Many Requests",
                response=response,
                body={"error": {"code": "RESOURCE_EXHAUSTED"}},
            )
        return await self._delegate.complete(prompt, schema=schema)

    async def embed(self, text: str) -> Embedding:  # pragma: no cover - unused
        raise NotImplementedError

    async def transcribe(
        self, audio_bytes: bytes, content_type: str
    ) -> Completion:  # pragma: no cover - unused
        raise NotImplementedError


async def test_run_eval_isolates_single_provider_error() -> None:
    # A single case raising a provider error must NOT abort the whole run:
    # the run completes over the other cases, records the errored case, and
    # excludes it from scoring (not counted as an empty extraction).
    dataset = load_dataset()
    target = dataset.cases[len(dataset.cases) // 2]
    provider = _FailOnCaseProvider(fail_substring=target.text)

    report, errors = await run_eval(provider, dataset)

    assert report.n_cases == len(dataset) - 1
    assert len(errors) == 1
    assert errors[0].case_id == target.id
    assert errors[0].detail  # non-empty raw provider detail
    scored_ids = {s.case_id for s in report.per_case}
    assert target.id not in scored_ids



# --- Task 2: preservation baseline (runs against UNFIXED code) --------------
class _ValueErrorOnCaseProvider(AIProvider):
    """Returns malformed JSON for one target case (triggers ValueError path).

    Malformed provider output makes ``parse_extraction`` raise ``ValueError``,
    which ``run_eval`` treats as an empty extraction (a genuine quality miss),
    NOT an infrastructure error. All other cases delegate to ``FakeProvider``.
    """

    def __init__(self, fail_substring: str) -> None:
        self._fail_substring = fail_substring
        self._delegate = FakeProvider()

    async def complete(
        self, prompt: str, *, schema: dict | None = None
    ) -> Completion:
        if self._fail_substring in prompt:
            from app.providers.base import Usage

            usage = Usage(
                provider="fake",
                model="fake-extract-1",
                operation="complete",
                input_tokens=1,
                output_tokens=1,
                cost_usd=0.0,
            )
            return Completion(text="this is not valid json", usage=usage)
        return await self._delegate.complete(prompt, schema=schema)

    async def embed(self, text: str) -> Embedding:  # pragma: no cover - unused
        raise NotImplementedError

    async def transcribe(
        self, audio_bytes: bytes, content_type: str
    ) -> Completion:  # pragma: no cover - unused
        raise NotImplementedError


async def test_value_error_still_empty_extraction() -> None:
    # A ValueError (malformed output) on one case stays a quality miss: the
    # case is scored as an empty extraction and still counted in n_cases; it is
    # never reclassified as a provider/infrastructure error.
    dataset = load_dataset()
    target = dataset.cases[3]
    provider = _ValueErrorOnCaseProvider(fail_substring=target.text)

    report, errors = await run_eval(provider, dataset)

    assert report.n_cases == len(dataset)
    assert errors == []
    scored = {s.case_id: s for s in report.per_case}
    assert target.id in scored
    # Empty extraction => no true positives contributed by the target case.
    assert scored[target.id].entity.tp == 0
    assert scored[target.id].task.tp == 0


async def test_run_eval_preserves_baseline_metrics_zero_errors() -> None:
    # Zero-provider-error run reproduces the recorded baseline: same n_cases,
    # same aggregate metrics (field for field), and an empty errors list.
    dataset = load_dataset()
    report, errors = await run_eval(FakeProvider(), dataset)

    assert errors == []
    assert report.n_cases == len(dataset)
    assert report.entity == aggregate(report.per_case).entity
    # Recorded baseline values (observed on the pre-fix code).
    assert report.entity.f1 == pytest.approx(0.558621, abs=1e-6)
    assert report.task.precision == pytest.approx(1.0, abs=1e-6)
    assert report.hallucination_rate == pytest.approx(0.295652, abs=1e-6)
    assert report.mean_cost_usd == 0.0



# --- Task 3.8: fix-checking + error-detail surfacing ------------------------
async def test_run_eval_metric_equivalence() -> None:
    # The completed-case metrics of an isolated run (one target case failing)
    # equal, field for field, the metrics of running over the dataset with the
    # target case removed. Errored cases never contribute to any aggregate.
    dataset = load_dataset()
    target = dataset.cases[len(dataset.cases) // 2]

    isolated_report, errors = await run_eval(
        _FailOnCaseProvider(fail_substring=target.text), dataset
    )

    subset = EvalDataset(cases=[c for c in dataset.cases if c.id != target.id])
    subset_report, subset_errors = await run_eval(FakeProvider(), subset)

    assert len(errors) == 1
    assert subset_errors == []
    assert target.id not in {s.case_id for s in isolated_report.per_case}
    assert isolated_report.n_cases == subset_report.n_cases
    assert isolated_report.entity == subset_report.entity
    assert isolated_report.task == subset_report.task
    assert isolated_report.connection == subset_report.connection
    assert isolated_report.hallucination_rate == subset_report.hallucination_rate
    assert isolated_report.mean_cost_usd == subset_report.mean_cost_usd
    # Latency is live wall-clock timing (non-reproducible run-to-run), so only
    # the scoring aggregates above are asserted equal, not p95 latency.


def test_main_partial_run_returns_exit_2_and_lists_unevaluated(
    capsys: pytest.CaptureFixture[str],
) -> None:
    # A partial run (one case errors) prints the normal report on stdout, lists
    # the un-evaluated case on stderr, and returns exit 2 (never a clean pass).
    dataset = load_dataset()
    target = dataset.cases[len(dataset.cases) // 2]
    with mock.patch(
        "app.eval.run_eval.build_provider",
        return_value=_FailOnCaseProvider(fail_substring=target.text),
    ):
        code = main(["--provider", "openai"])
    assert code == EXIT_PROVIDER_UNAVAILABLE
    captured = capsys.readouterr()
    assert "Comprehension Evaluation Report" in captured.out
    assert "CASOS NO EVALUADOS (provider error): 1" in captured.err
    assert target.id in captured.err
    assert "429" in captured.err


def test_describe_provider_error_surfaces_type_status_message_body() -> None:
    from openai import RateLimitError

    response = httpx.Response(
        429, request=httpx.Request("POST", "https://api.openai.com/v1/x")
    )
    exc = RateLimitError(
        "429 Too Many Requests",
        response=response,
        body={"error": {"code": "RESOURCE_EXHAUSTED"}},
    )
    detail = _describe_provider_error(exc)
    assert "RateLimitError" in detail
    assert "429" in detail
    assert "429 Too Many Requests" in detail
    assert "RESOURCE_EXHAUSTED" in detail
    assert "\n" not in detail and "\r" not in detail  # single line

    # Never raises on a bare exception lacking status/message/body attributes.
    bare = _describe_provider_error(Exception("boom"))
    assert "Exception" in bare


def test_describe_provider_error_never_raises_on_missing_attrs() -> None:
    class _Weird(BaseException):
        pass

    # No status_code/code/body/response present -> still a single-line string.
    result = _describe_provider_error(_Weird())
    assert result == "_Weird" or result.startswith("_Weird")
    assert "\n" not in result



# --- Task 3.9: property-based tests (hypothesis, already pinned) ------------
def _synthetic_dataset(n: int) -> EvalDataset:
    """Build a synthetic dataset of ``n`` cases with unique fail markers."""
    cases = [
        EvalCase(
            id=f"syn-{i:03d}",
            language="en",
            description="synthetic",
            text=f"synthetic capture marker-zz{i}zz end",
            gold=Extraction(),
        )
        for i in range(n)
    ]
    return EvalDataset(cases=cases)


class _MultiFailProvider(AIProvider):
    """Raises a provider error for any prompt containing a configured marker."""

    def __init__(self, fail_markers: list[str]) -> None:
        self._fail_markers = fail_markers
        self._delegate = FakeProvider()

    async def complete(
        self, prompt: str, *, schema: dict | None = None
    ) -> Completion:
        if any(m in prompt for m in self._fail_markers):
            from openai import RateLimitError

            response = httpx.Response(
                429, request=httpx.Request("POST", "https://api.openai.com/v1/x")
            )
            raise RateLimitError("429", response=response, body=None)
        return await self._delegate.complete(prompt, schema=schema)

    async def embed(self, text: str) -> Embedding:  # pragma: no cover - unused
        raise NotImplementedError

    async def transcribe(
        self, audio_bytes: bytes, content_type: str
    ) -> Completion:  # pragma: no cover - unused
        raise NotImplementedError


@given(data=st.data())
@hyp_settings(max_examples=25, deadline=None)
def test_pbt_provider_errors_are_isolated_and_counted(data: st.DataObject) -> None:
    # Property 1 & 3: k errored cases -> len(errors)==k, n_cases==n-k, and no
    # errored id appears in per_case (excluded from scoring entirely).
    n = data.draw(st.integers(min_value=1, max_value=8))
    fail_indices = data.draw(
        st.sets(st.integers(min_value=0, max_value=n - 1))
    )
    dataset = _synthetic_dataset(n)
    markers = [f"marker-zz{i}zz" for i in fail_indices]
    report, errors = asyncio.run(
        run_eval(_MultiFailProvider(markers), dataset)
    )

    k = len(fail_indices)
    assert len(errors) == k
    assert report.n_cases == n - k
    errored_ids = {e.case_id for e in errors}
    assert errored_ids == {f"syn-{i:03d}" for i in fail_indices}
    assert errored_ids.isdisjoint({s.case_id for s in report.per_case})
    assert all(e.detail for e in errors)


@given(n=st.integers(min_value=0, max_value=8))
@hyp_settings(max_examples=10, deadline=None)
def test_pbt_zero_error_runs_have_empty_errors(n: int) -> None:
    # Property 2: a zero-provider-error run always yields errors == [] and
    # scores every case.
    dataset = _synthetic_dataset(n)
    report, errors = asyncio.run(run_eval(FakeProvider(), dataset))
    assert errors == []
    assert report.n_cases == n


@given(
    status=st.one_of(st.none(), st.integers(min_value=100, max_value=599)),
    code=st.one_of(st.none(), st.text(max_size=20)),
    message=st.one_of(st.none(), st.text(max_size=40)),
    body=st.one_of(
        st.none(),
        st.dictionaries(st.text(max_size=5), st.text(max_size=5), max_size=3),
    ),
)
@hyp_settings(max_examples=60, deadline=None)
def test_pbt_describe_provider_error_single_line_never_raises(
    status: int | None,
    code: str | None,
    message: str | None,
    body: dict | None,
) -> None:
    # Property 4: over arbitrary subsets of attributes, the helper always
    # returns a non-empty single-line string and never raises.
    class _Fake(BaseException):
        pass

    exc = _Fake()
    if status is not None:
        exc.status_code = status  # type: ignore[attr-defined]
    if code is not None:
        exc.code = code  # type: ignore[attr-defined]
    if message is not None:
        exc.message = message  # type: ignore[attr-defined]
    if body is not None:
        exc.body = body  # type: ignore[attr-defined]

    result = _describe_provider_error(exc)
    assert isinstance(result, str)
    assert result  # non-empty (at least the type name)
    assert "\n" not in result
    assert "\r" not in result
    assert "_Fake" in result
