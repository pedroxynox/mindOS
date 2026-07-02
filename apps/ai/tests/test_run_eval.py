"""Tests for the eval runner and the acceptance-gate logic."""

from app.config import settings
from app.eval.loader import load_dataset
from app.eval.metrics import aggregate
from app.eval.run_eval import (
    main,
    render_report,
    run_eval,
    thresholds_from_settings,
)
from app.providers.fake_provider import FakeProvider


def test_dataset_loads_expected_cases() -> None:
    dataset = load_dataset()
    assert 8 <= len(dataset) <= 12
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
