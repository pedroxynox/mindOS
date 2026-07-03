"""Tests for the eval runner and the acceptance-gate logic."""

from unittest import mock

import httpx
import pytest

from app.config import settings
from app.eval.loader import load_dataset
from app.eval.metrics import aggregate
from app.eval.run_eval import (
    EXIT_PROVIDER_UNAVAILABLE,
    main,
    render_report,
    run_eval,
    thresholds_from_settings,
)
from app.providers.base import AIProvider, Completion, Embedding
from app.providers.fake_provider import FakeProvider


def test_dataset_loads_expected_cases() -> None:
    dataset = load_dataset()
    # Eval set expanded to ~45 cases for a stable, low-noise measurement (R-001).
    assert 40 <= len(dataset) <= 50
    ids = [c.id for c in dataset.cases]
    assert ids == sorted(ids)  # deterministic ordering
    assert len(set(ids)) == len(ids)  # unique ids


async def test_run_eval_over_dataset_produces_bounded_metrics() -> None:
    dataset = load_dataset()
    report = await run_eval(FakeProvider(), dataset)
    assert report.n_cases == len(dataset)
    assert 0.0 <= report.entity.f1 <= 1.0
    assert 0.0 <= report.task.precision <= 1.0
    assert 0.0 <= report.hallucination_rate <= 1.0
    # FakeProvider has zero cost.
    assert report.mean_cost_usd == 0.0


async def test_render_report_contains_verdict() -> None:
    dataset = load_dataset()
    report = await run_eval(FakeProvider(), dataset)
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
    # When the provider keeps returning 429 after retries, run_eval must exit
    # non-zero with a clear operator message instead of a raw stacktrace.
    with mock.patch(
        "app.eval.run_eval.build_provider", return_value=_RateLimitedProvider()
    ):
        code = main(["--provider", "openai"])
    assert code == EXIT_PROVIDER_UNAVAILABLE
    err = capsys.readouterr().err
    # The message must name the ACTUAL provider in use (not a hardcoded
    # "OpenAI") and mention the rate limit so the operator knows to wait/retry.
    assert "openai" in err
    assert "límite" in err


def test_rate_limit_message_names_the_actual_provider() -> None:
    # A Groq run that hits the limit must say "groq", never a hardcoded "OpenAI".
    from openai import RateLimitError

    from app.eval.run_eval import _classify_provider_error

    response = httpx.Response(
        429, request=httpx.Request("POST", "https://api.groq.com/openai/v1/x")
    )
    exc = RateLimitError("429", response=response, body=None)
    message = _classify_provider_error(exc, "groq")
    assert message is not None
    assert "groq" in message
    assert "OpenAI" not in message


async def test_run_eval_propagates_rate_limit_error() -> None:
    from openai import RateLimitError

    dataset = load_dataset()
    with pytest.raises(RateLimitError):
        await run_eval(_RateLimitedProvider(), dataset)
