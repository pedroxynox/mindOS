"""Expense-detection eval (mejoras-v2 §E) — OUTSIDE the ADR-018 gate.

Measures the second, small call (:mod:`app.understanding.expenses`) on its own
hand-annotated set (``expenses_dataset.json``): amounts found (P/R/F1, one to
one), currency and category accuracy on the matched ones, how often a note
with NO expense (a future payment, income, a loan) gets one anyway, and the
recall of the cheap money-cue pre-filter.

    python -m app.eval.run_eval --suite expenses [--provider openai] [--gate]

Thresholds are provisional and live here, not in Settings: this suite never
touches the comprehension gate.
"""

import asyncio
import json
import sys
from dataclasses import dataclass, field
from pathlib import Path

from openai import APIError
from pydantic import BaseModel, Field

from app.providers.base import AIProvider
from app.understanding.expenses import (
    EXPENSE_PROMPT_VERSION,
    ExpenseItem,
    detect_expenses,
    has_money_cue,
)

DATASET_PATH = Path(__file__).parent / "expenses_dataset.json"
AMOUNT_TOLERANCE = 0.01


class GoldExpense(BaseModel):
    amount: float = Field(gt=0)
    currency: str | None = None
    category: str


class ExpenseCase(BaseModel):
    id: str
    language: str = Field(pattern="^(es|en|mixed)$")
    user_currency: str = Field(pattern="^[A-Z]{3}$")
    text: str
    gold: list[GoldExpense]


def load_expense_cases(path: Path = DATASET_PATH) -> list[ExpenseCase]:
    data = json.loads(path.read_text(encoding="utf-8"))
    cases = [ExpenseCase.model_validate(c) for c in data["cases"]]
    ids = [c.id for c in cases]
    if len(ids) != len(set(ids)):
        raise ValueError("duplicate case ids in the expenses dataset")
    return sorted(cases, key=lambda c: c.id)


@dataclass(frozen=True)
class ExpenseThresholds:
    f1_min: float = 0.85
    currency_accuracy_min: float = 0.90
    category_accuracy_min: float = 0.80
    false_expense_rate_max: float = 0.10
    cue_recall_min: float = 1.0


@dataclass
class CaseScore:
    case_id: str
    tp: int
    fp: int
    fn: int
    currency_ok: int
    category_ok: int
    cue: bool
    cost_usd: float


@dataclass
class ExpenseReport:
    scores: list[CaseScore] = field(default_factory=list)
    negatives: int = 0
    negatives_with_expense: int = 0
    positives: int = 0
    positives_with_cue: int = 0

    def _sum(self, attr: str) -> int:
        return sum(getattr(s, attr) for s in self.scores)

    @property
    def precision(self) -> float:
        tp, fp = self._sum("tp"), self._sum("fp")
        return tp / (tp + fp) if tp + fp else 1.0

    @property
    def recall(self) -> float:
        tp, fn = self._sum("tp"), self._sum("fn")
        return tp / (tp + fn) if tp + fn else 1.0

    @property
    def f1(self) -> float:
        p, r = self.precision, self.recall
        return 2 * p * r / (p + r) if p + r else 0.0

    @property
    def currency_accuracy(self) -> float:
        tp = self._sum("tp")
        return self._sum("currency_ok") / tp if tp else 1.0

    @property
    def category_accuracy(self) -> float:
        tp = self._sum("tp")
        return self._sum("category_ok") / tp if tp else 1.0

    @property
    def false_expense_rate(self) -> float:
        return self.negatives_with_expense / self.negatives if self.negatives else 0.0

    @property
    def cue_recall(self) -> float:
        return self.positives_with_cue / self.positives if self.positives else 1.0

    @property
    def mean_cost_usd(self) -> float:
        return (
            sum(s.cost_usd for s in self.scores) / len(self.scores)
            if self.scores
            else 0.0
        )

    def gate(self, t: ExpenseThresholds) -> tuple[bool, list[str]]:
        checks = [
            (self.f1 >= t.f1_min, f"F1 {self.f1:.3f} < {t.f1_min:.2f}"),
            (
                self.currency_accuracy >= t.currency_accuracy_min,
                f"currency {self.currency_accuracy:.3f}"
                f" < {t.currency_accuracy_min:.2f}",
            ),
            (
                self.category_accuracy >= t.category_accuracy_min,
                f"category {self.category_accuracy:.3f}"
                f" < {t.category_accuracy_min:.2f}",
            ),
            (
                self.false_expense_rate <= t.false_expense_rate_max,
                f"false expenses {self.false_expense_rate:.3f}"
                f" > {t.false_expense_rate_max:.2f}",
            ),
            (
                self.cue_recall >= t.cue_recall_min,
                f"money-cue recall {self.cue_recall:.3f} < {t.cue_recall_min:.2f}",
            ),
        ]
        failures = [msg for ok, msg in checks if not ok]
        return not failures, failures


def score_expense_case(
    case: ExpenseCase,
    predicted: list[ExpenseItem],
    *,
    cue: bool,
    cost_usd: float = 0.0,
) -> CaseScore:
    """One-to-one match by amount, then compare currency (ambiguous → the
    user's, same rule as the pipeline) and category on the matched pairs."""
    remaining = list(case.gold)
    tp = currency_ok = category_ok = 0
    for item in predicted:
        match = next(
            (g for g in remaining if abs(g.amount - item.amount) <= AMOUNT_TOLERANCE),
            None,
        )
        if match is None:
            continue
        remaining.remove(match)
        tp += 1
        resolved = item.currency or case.user_currency
        if resolved == (match.currency or case.user_currency):
            currency_ok += 1
        if item.category == match.category:
            category_ok += 1
    return CaseScore(
        case_id=case.id,
        tp=tp,
        fp=len(predicted) - tp,
        fn=len(remaining),
        currency_ok=currency_ok,
        category_ok=category_ok,
        cue=cue,
        cost_usd=cost_usd,
    )


async def run_expense_eval(
    provider: AIProvider,
    cases: list[ExpenseCase],
    *,
    request_delay_s: float = 0.0,
) -> tuple[ExpenseReport, list[tuple[str, str]]]:
    """Score every case; a provider error skips that case (reported apart)."""
    report = ExpenseReport()
    errors: list[tuple[str, str]] = []
    for index, case in enumerate(cases):
        if index > 0 and request_delay_s > 0:
            await asyncio.sleep(request_delay_s)
        cue = has_money_cue(case.text)
        try:
            result = await detect_expenses(case.text, provider)
        except APIError as exc:
            errors.append((case.id, f"{type(exc).__name__}: {exc}"))
            print(f"[expenses] provider error on {case.id}: {exc}", file=sys.stderr)
            continue
        cost = result.usage.cost_usd if result.usage else 0.0
        report.scores.append(
            score_expense_case(case, result.expenses, cue=cue, cost_usd=cost)
        )
        if case.gold:
            report.positives += 1
            report.positives_with_cue += int(cue)
        else:
            report.negatives += 1
            report.negatives_with_expense += int(bool(result.expenses))
    return report, errors


def render_expense_report(
    report: ExpenseReport, thresholds: ExpenseThresholds, provider_name: str
) -> str:
    passed, failures = report.gate(thresholds)

    def flag(ok: bool) -> str:
        return "PASS" if ok else "FAIL"

    lines = [
        "=" * 68,
        "  mindOS — Expense detection eval (mejoras-v2 §E, outside ADR-018)",
        "=" * 68,
        f"  provider     : {provider_name}",
        f"  prompt       : {EXPENSE_PROMPT_VERSION}",
        f"  cases        : {len(report.scores)}"
        f" ({report.positives} with expenses, {report.negatives} without)",
        "-" * 68,
        f"    expenses   P={report.precision:.3f}  R={report.recall:.3f}"
        f"  F1={report.f1:.3f}",
        f"    currency accuracy  : {report.currency_accuracy:.3f}",
        f"    category accuracy  : {report.category_accuracy:.3f}",
        f"    false expense rate : {report.false_expense_rate:.3f}",
        f"    money-cue recall   : {report.cue_recall:.3f}",
        f"    mean cost / capture: ${report.mean_cost_usd:.6f}",
        "-" * 68,
        "  Thresholds (PROVISIONAL, report-only unless --gate)",
        f"    F1 >= {thresholds.f1_min:.2f}  {flag(report.f1 >= thresholds.f1_min)}",
        f"    currency >= {thresholds.currency_accuracy_min:.2f}"
        f"  {flag(report.currency_accuracy >= thresholds.currency_accuracy_min)}",
        f"    category >= {thresholds.category_accuracy_min:.2f}"
        f"  {flag(report.category_accuracy >= thresholds.category_accuracy_min)}",
        f"    false expenses <= {thresholds.false_expense_rate_max:.2f}"
        f"  {flag(report.false_expense_rate <= thresholds.false_expense_rate_max)}",
        f"    money-cue recall >= {thresholds.cue_recall_min:.2f}"
        f"  {flag(report.cue_recall >= thresholds.cue_recall_min)}",
        "-" * 68,
        "  Per case (tp/fp/fn, currency ok, category ok)",
    ]
    for s in report.scores:
        lines.append(
            f"    {s.case_id:<8} tp={s.tp} fp={s.fp} fn={s.fn}"
            f"  cur={s.currency_ok}  cat={s.category_ok}"
            f"{'' if s.cue else '  (sin pista de dinero: sin llamada)'}"
        )
    lines.append("=" * 68)
    lines.append(f"  VERDICT: {'PASSED' if passed else 'BELOW THRESHOLDS'}")
    for f in failures:
        lines.append(f"    - {f}")
    lines.append("=" * 68)
    return "\n".join(lines)
