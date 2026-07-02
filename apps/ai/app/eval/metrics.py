"""Pure, testable evaluation metrics (design §13.1).

All functions are side-effect free and operate on plain values so they can be
unit-tested with known inputs -> known outputs. Higher-level helpers adapt an
:class:`Extraction` and a gold :class:`Extraction` into the primitive
multiset comparisons.

Matching rule: entities match by ``(type, normalized_label)``, tasks by
``normalized_label``, connections by ``(type, normalized_source,
normalized_target)`` — see :func:`app.understanding.text_utils.normalize_label`.
"""

import math
from collections import Counter
from collections.abc import Sequence
from dataclasses import dataclass, field
from typing import Hashable

from app.understanding.extract import Extraction
from app.understanding.text_utils import normalize_label


@dataclass(frozen=True)
class PRF:
    """Precision/recall/F1 counts for a single comparison."""

    tp: int
    fp: int
    fn: int

    @property
    def precision(self) -> float:
        denom = self.tp + self.fp
        return self.tp / denom if denom > 0 else 1.0

    @property
    def recall(self) -> float:
        denom = self.tp + self.fn
        return self.tp / denom if denom > 0 else 1.0

    @property
    def f1(self) -> float:
        p, r = self.precision, self.recall
        return (2 * p * r) / (p + r) if (p + r) > 0 else 0.0

    def __add__(self, other: "PRF") -> "PRF":
        return PRF(self.tp + other.tp, self.fp + other.fp, self.fn + other.fn)


def prf(predicted: Sequence[Hashable], gold: Sequence[Hashable]) -> PRF:
    """Multiset precision/recall counts of predicted vs gold items.

    Duplicates are honored (a gold item can be matched at most once).
    """
    pc = Counter(predicted)
    gc = Counter(gold)
    tp = sum((pc & gc).values())
    fp = sum(pc.values()) - tp
    fn = sum(gc.values()) - tp
    return PRF(tp=tp, fp=fp, fn=fn)


def hallucination_rate(
    predicted: Sequence[Hashable], gold: Sequence[Hashable]
) -> float:
    """Fraction of predicted items unsupported by gold: ``FP / total_proposed``.

    Zero when nothing is proposed (no hallucination possible). Upper bound on
    invented entities (design §13.1).
    """
    total = len(predicted)
    if total == 0:
        return 0.0
    scores = prf(predicted, gold)
    return scores.fp / total


def mean(values: list[float]) -> float:
    """Arithmetic mean; 0.0 for an empty list."""
    return sum(values) / len(values) if values else 0.0


def p95(values: list[float]) -> float:
    """95th percentile by the nearest-rank method; 0.0 for an empty list."""
    if not values:
        return 0.0
    ordered = sorted(values)
    rank = math.ceil(0.95 * len(ordered))
    index = min(max(rank, 1), len(ordered)) - 1
    return ordered[index]


# --- Adapters from Extraction to primitive item lists -------------------------
def entity_pairs(extraction: Extraction) -> list[tuple[str, str]]:
    """``(type, normalized_label)`` across all node types (tasks folded in)."""
    return [(t, normalize_label(label)) for t, label in extraction.typed_entities()]


def task_labels(extraction: Extraction) -> list[str]:
    """Normalized labels of extracted tasks only."""
    return [normalize_label(t.label) for t in extraction.tasks]


def connection_triples(extraction: Extraction) -> list[tuple[str, str, str]]:
    """``(type, normalized_source, normalized_target)`` for each connection."""
    return [
        (c.type, normalize_label(c.source), normalize_label(c.target))
        for c in extraction.connections
    ]


# --- Per-case and aggregate reports -------------------------------------------
@dataclass(frozen=True)
class CaseScore:
    """Scores for a single eval case."""

    case_id: str
    entity: PRF
    task: PRF
    connection: PRF
    hallucination: float
    cost_usd: float
    latency_ms: float


@dataclass(frozen=True)
class Thresholds:
    """Acceptance gate (design §13.2). PROVISIONAL — pending product sign-off."""

    f1_entities_min: float
    task_precision_min: float
    hallucination_max: float
    cost_per_capture_max_usd: float


@dataclass(frozen=True)
class EvalReport:
    """Aggregate quality across the eval set plus per-case detail."""

    entity: PRF
    task: PRF
    connection: PRF
    hallucination_rate: float
    mean_cost_usd: float
    p95_latency_ms: float
    n_cases: int
    per_case: list[CaseScore] = field(default_factory=list)

    def gate(self, thresholds: Thresholds) -> tuple[bool, list[str]]:
        """Return ``(passed, failures)`` against the acceptance thresholds."""
        failures: list[str] = []
        if self.entity.f1 < thresholds.f1_entities_min:
            failures.append(
                f"F1 entities {self.entity.f1:.3f} < {thresholds.f1_entities_min}"
            )
        if self.task.precision < thresholds.task_precision_min:
            failures.append(
                f"task precision {self.task.precision:.3f} "
                f"< {thresholds.task_precision_min}"
            )
        if self.hallucination_rate > thresholds.hallucination_max:
            failures.append(
                f"hallucination {self.hallucination_rate:.3f} "
                f"> {thresholds.hallucination_max}"
            )
        if self.mean_cost_usd > thresholds.cost_per_capture_max_usd:
            failures.append(
                f"mean cost/capture ${self.mean_cost_usd:.6f} "
                f"> ${thresholds.cost_per_capture_max_usd}"
            )
        return (len(failures) == 0, failures)


def score_case(
    case_id: str,
    predicted: Extraction,
    gold: Extraction,
    cost_usd: float,
    latency_ms: float,
) -> CaseScore:
    """Score one predicted extraction against its gold labels."""
    ent = prf(entity_pairs(predicted), entity_pairs(gold))
    tsk = prf(task_labels(predicted), task_labels(gold))
    con = prf(connection_triples(predicted), connection_triples(gold))
    hall = hallucination_rate(entity_pairs(predicted), entity_pairs(gold))
    return CaseScore(
        case_id=case_id,
        entity=ent,
        task=tsk,
        connection=con,
        hallucination=hall,
        cost_usd=cost_usd,
        latency_ms=latency_ms,
    )


def aggregate(scores: list[CaseScore]) -> EvalReport:
    """Aggregate per-case scores into an :class:`EvalReport` (micro-averaged)."""
    zero = PRF(0, 0, 0)
    entity_total = sum((s.entity for s in scores), zero)
    task_total = sum((s.task for s in scores), zero)
    conn_total = sum((s.connection for s in scores), zero)
    # Hallucination is the total unsupported proposals over total proposals.
    total_fp = entity_total.fp
    total_proposed = entity_total.tp + entity_total.fp
    hall = total_fp / total_proposed if total_proposed > 0 else 0.0
    return EvalReport(
        entity=entity_total,
        task=task_total,
        connection=conn_total,
        hallucination_rate=hall,
        mean_cost_usd=mean([s.cost_usd for s in scores]),
        p95_latency_ms=p95([s.latency_ms for s in scores]),
        n_cases=len(scores),
        per_case=scores,
    )
