"""Evaluation runner + acceptance gate (design §13.3).

Loads the eval set, runs extraction with the chosen provider, aggregates the
metrics, prints a human-readable report, and compares against the acceptance
thresholds. In "gate" mode a failed threshold exits non-zero (for future CI).

Run it with:

    python -m app.eval.run_eval                 # FakeProvider (offline), report only
    python -m app.eval.run_eval --gate          # exit != 0 if thresholds not met
    python -m app.eval.run_eval --provider openai --gate

Thresholds are PROVISIONAL (design §13.2) — pending ratification by the product
owner. They are read from Settings so they can be tuned without code changes.
"""

import argparse
import asyncio
import sys
from dataclasses import dataclass

from openai import APIError

from app.config import Settings
from app.config import settings as default_settings
from app.eval.loader import EvalDataset, load_dataset
from app.eval.metrics import (
    EvalReport,
    Thresholds,
    aggregate,
    score_case,
)
from app.providers.base import AIProvider
from app.providers.factory import build_provider
from app.understanding.extract import Extraction, run_extraction


@dataclass(frozen=True)
class ProviderCaseError:
    """One un-evaluated case: its id plus the raw provider error detail."""

    case_id: str
    detail: str


def thresholds_from_settings(s: Settings) -> Thresholds:
    return Thresholds(
        f1_entities_min=s.eval_f1_entities_min,
        task_precision_min=s.eval_task_precision_min,
        hallucination_max=s.eval_hallucination_max,
        cost_per_capture_max_usd=s.eval_cost_per_capture_max_usd,
    )


async def run_eval(
    provider: AIProvider,
    dataset: EvalDataset,
    *,
    request_delay_s: float = 0.0,
) -> tuple[EvalReport, list[ProviderCaseError]]:
    """Score every case in the dataset and aggregate into a report.

    Cases run strictly sequentially (never a concurrent burst) and an optional
    ``request_delay_s`` pause is inserted between them so a real-provider run
    stays under the requests-per-minute limit of a fresh account.

    Provider/transport errors are isolated PER CASE: an ``openai.APIError``
    (or subclass such as ``RateLimitError``) raised for a single case — after
    the provider's own retries are exhausted — is recorded as a
    :class:`ProviderCaseError`, logged to stderr, and skipped so the run still
    completes over every other evaluable case. Those errored cases are excluded
    from scoring entirely (never counted as empty extractions). The function
    returns ``(report, errors)`` so the caller can render the completed-case
    metrics and the un-evaluated cases separately. A malformed/invalid provider
    *output* (``ValueError``) is unchanged: it stays a genuine quality miss
    scored as an empty extraction.
    """
    errors: list[ProviderCaseError] = []
    scores = []
    for index, case in enumerate(dataset.cases):
        if index > 0 and request_delay_s > 0:
            await asyncio.sleep(request_delay_s)
        try:
            result = await run_extraction(case.text, provider)
            predicted = result.extraction
            cost = result.usage.cost_usd
            latency = result.latency_ms
        except ValueError:
            # Malformed/invalid provider output counts as an empty extraction
            # (all gold items become false negatives) — never a crash.
            predicted = Extraction()
            cost = 0.0
            latency = 0.0
        except APIError as exc:
            # Provider/transport failure for THIS case only: record, log, and
            # skip scoring so it is never counted as an empty extraction.
            detail = _describe_provider_error(exc)
            errors.append(ProviderCaseError(case.id, detail))
            print(
                f"[run_eval] provider error on {case.id}: {detail}",
                file=sys.stderr,
            )
            continue
        scores.append(
            score_case(case.id, predicted, case.gold, cost, latency)
        )
    return aggregate(scores), errors


def _describe_provider_error(exc: BaseException) -> str:
    """Return a readable single-line diagnostic for a provider exception.

    Surfaces the exception type name plus any of ``status_code``, ``code``,
    ``message`` and ``body``/``response`` that are present. All attribute access
    is defensive (``getattr(..., None)``) and the whole body is wrapped so this
    helper NEVER raises — diagnostics must not crash the run.
    """
    try:
        parts: list[str] = [type(exc).__name__]
        status = getattr(exc, "status_code", None)
        if status is not None:
            parts.append(f"status={status}")
        code = getattr(exc, "code", None)  # e.g. RESOURCE_EXHAUSTED
        if code:
            parts.append(f"code={code}")
        message = getattr(exc, "message", None) or str(exc)
        if message:
            parts.append(f"message={message!r}")
        body = getattr(exc, "body", None)
        if body is not None:
            parts.append(f"body={body!r}")
        else:
            response = getattr(exc, "response", None)
            if response is not None:
                text = getattr(response, "text", None)
                parts.append(
                    f"response={text!r}" if text else f"response={response!r}"
                )
        return " ".join(parts).replace("\n", " ").replace("\r", " ")
    except Exception:  # noqa: BLE001 - diagnostics must never crash the run
        return type(exc).__name__


def _render_unevaluated(errors: list[ProviderCaseError]) -> str:
    """Render the delimited "casos no evaluados" section for the error list."""
    lines = [
        "=" * 68,
        f"  CASOS NO EVALUADOS (provider error): {len(errors)}",
        "-" * 68,
    ]
    for e in errors:
        lines.append(f"  {e.case_id:<12} {e.detail}")
    lines.append("=" * 68)
    return "\n".join(lines)


def render_report(
    report: EvalReport,
    thresholds: Thresholds,
    provider_name: str,
) -> str:
    """Build the human-readable evaluation report."""
    passed, failures = report.gate(thresholds)
    lines: list[str] = []
    lines.append("=" * 68)
    lines.append("  mindOS — F2 Comprehension Evaluation Report (de-risk R-001)")
    lines.append("=" * 68)
    lines.append(f"  provider     : {provider_name}")
    lines.append(f"  cases        : {report.n_cases}")
    lines.append("-" * 68)
    lines.append("  Aggregate metrics (micro-averaged)")
    lines.append(
        f"    entities   P={report.entity.precision:.3f}  "
        f"R={report.entity.recall:.3f}  F1={report.entity.f1:.3f}  "
        f"(tp={report.entity.tp} fp={report.entity.fp} fn={report.entity.fn})"
    )
    lines.append(
        f"    tasks      P={report.task.precision:.3f}  "
        f"R={report.task.recall:.3f}  F1={report.task.f1:.3f}  "
        f"(tp={report.task.tp} fp={report.task.fp} fn={report.task.fn})"
    )
    lines.append(
        f"    connections P={report.connection.precision:.3f}  "
        f"R={report.connection.recall:.3f}  F1={report.connection.f1:.3f}"
    )
    lines.append(f"    hallucination rate : {report.hallucination_rate:.3f}")
    lines.append(f"    mean cost / capture: ${report.mean_cost_usd:.6f}")
    lines.append(f"    latency p95        : {report.p95_latency_ms:.2f} ms")
    lines.append("-" * 68)
    lines.append("  Acceptance gate (PROVISIONAL — pending product sign-off)")

    def flag(ok: bool) -> str:
        return "PASS" if ok else "FAIL"

    f1_ok = report.entity.f1 >= thresholds.f1_entities_min
    task_ok = report.task.precision >= thresholds.task_precision_min
    hall_ok = report.hallucination_rate <= thresholds.hallucination_max
    cost_ok = report.mean_cost_usd <= thresholds.cost_per_capture_max_usd
    lines.append(
        f"    F1 entities        >= {thresholds.f1_entities_min:.2f}   "
        f"-> {report.entity.f1:.3f}  {flag(f1_ok)}"
    )
    lines.append(
        f"    task precision     >= {thresholds.task_precision_min:.2f}   "
        f"-> {report.task.precision:.3f}  {flag(task_ok)}"
    )
    lines.append(
        f"    hallucination      <= {thresholds.hallucination_max:.2f}   "
        f"-> {report.hallucination_rate:.3f}  {flag(hall_ok)}"
    )
    lines.append(
        f"    mean cost/capture  <= ${thresholds.cost_per_capture_max_usd:.4f} "
        f"-> ${report.mean_cost_usd:.6f}  {flag(cost_ok)}"
    )
    lines.append("-" * 68)
    lines.append("  Per-case entity F1 / task precision")
    for s in report.per_case:
        lines.append(
            f"    {s.case_id:<9} F1={s.entity.f1:.3f}  "
            f"taskP={s.task.precision:.3f}  hall={s.hallucination:.3f}"
        )
    lines.append("=" * 68)
    verdict = "GATE PASSED" if passed else "GATE FAILED"
    lines.append(f"  VERDICT: {verdict}")
    if not passed:
        for f in failures:
            lines.append(f"    - {f}")
    lines.append("=" * 68)
    return "\n".join(lines)


def _parse_args(argv: list[str] | None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run the F2 comprehension eval.")
    parser.add_argument(
        "--provider",
        default=None,
        help="Override llm_provider (fake|openai). Defaults to Settings.",
    )
    parser.add_argument(
        "--gate",
        action="store_true",
        help="Exit non-zero if the acceptance thresholds are not met.",
    )
    return parser.parse_args(argv)


# Exit code used when the run aborts because the provider stayed unavailable
# (e.g. rate limit persisting after all retries). Distinct from the gate-fail
# code (1) so CI can tell "infra problem" apart from "quality below threshold".
EXIT_PROVIDER_UNAVAILABLE = 2


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(argv)
    s = default_settings
    if args.provider:
        s = Settings(**{**default_settings.model_dump(), "llm_provider": args.provider})
    provider = build_provider(s)
    dataset = load_dataset()
    try:
        report, errors = asyncio.run(
            run_eval(provider, dataset, request_delay_s=s.eval_request_delay_s)
        )
    except Exception as exc:  # noqa: BLE001 - catastrophic whole-run failure only
        message = _classify_provider_error(exc)
        if message is None:
            raise
        print(message, file=sys.stderr)
        return EXIT_PROVIDER_UNAVAILABLE
    thresholds = thresholds_from_settings(s)
    print(render_report(report, thresholds, s.llm_provider))
    if errors:
        # A partial run (any un-evaluated case) is never a clean pass.
        print(_render_unevaluated(errors), file=sys.stderr)
        return EXIT_PROVIDER_UNAVAILABLE
    if args.gate:
        passed, _ = report.gate(thresholds)
        return 0 if passed else 1
    return 0


def _classify_provider_error(exc: BaseException) -> str | None:
    """Map a provider failure to a clear operator message, or ``None``.

    Returns ``None`` when the error is not a recognised provider/transport
    problem, so unexpected bugs still surface as a normal traceback.
    """
    try:
        from openai import APIError, RateLimitError
    except ImportError:  # pragma: no cover - openai is a core dependency
        return None
    if isinstance(exc, RateLimitError):
        return (
            "ERROR: límite de OpenAI alcanzado; revisa facturación/saldo o los "
            "límites de peticiones de tu cuenta. La evaluación se ha detenido "
            "tras agotar los reintentos."
        )
    if isinstance(exc, APIError):
        return (
            "ERROR: no se pudo completar la evaluación por un problema "
            "transitorio con OpenAI tras agotar los reintentos. Inténtalo de "
            "nuevo más tarde."
        )
    return None


def _as_mutable(s: Settings) -> Settings:
    # Settings is a Pydantic model; build a fresh instance to override a field.
    return Settings(**s.model_dump())


if __name__ == "__main__":
    raise SystemExit(main())
