"""Unit + property tests for the pure evaluation metrics."""

from hypothesis import given
from hypothesis import strategies as st

from app.eval.metrics import (
    PRF,
    EvalReport,
    Thresholds,
    aggregate,
    connection_triples,
    entity_pairs,
    hallucination_rate,
    mean,
    p95,
    prf,
    score_case,
    task_labels,
)
from app.understanding.extract import Connection, Entity, Extraction, TaskItem


def test_prf_basic_counts() -> None:
    scores = prf(["a", "b", "c"], ["b", "c", "d"])
    assert (scores.tp, scores.fp, scores.fn) == (2, 1, 1)
    assert scores.precision == 2 / 3
    assert scores.recall == 2 / 3
    assert abs(scores.f1 - 2 / 3) < 1e-9


def test_prf_empty_both_is_perfect() -> None:
    scores = prf([], [])
    assert (scores.tp, scores.fp, scores.fn) == (0, 0, 0)
    assert scores.precision == 1.0
    assert scores.recall == 1.0
    assert scores.f1 == 1.0


def test_prf_honors_duplicates() -> None:
    scores = prf(["a", "a", "b"], ["a", "b"])
    # Only one of the two predicted "a" can match the single gold "a".
    assert (scores.tp, scores.fp, scores.fn) == (2, 1, 0)


def test_hallucination_rate() -> None:
    assert hallucination_rate(["a", "b"], ["a"]) == 0.5
    assert hallucination_rate([], ["a"]) == 0.0
    assert hallucination_rate(["a"], ["a"]) == 0.0


def test_mean_and_p95() -> None:
    assert mean([]) == 0.0
    assert mean([2.0, 4.0]) == 3.0
    assert p95([]) == 0.0
    # nearest-rank: ceil(0.95 * 10) = 10 -> the max.
    assert p95([float(i) for i in range(1, 11)]) == 10.0
    assert p95([5.0]) == 5.0


def test_entity_pairs_fold_tasks_and_normalize() -> None:
    ext = Extraction(
        entities=[Entity(type="topic", label="Reunión")],
        tasks=[TaskItem(label="Llamar a Ana")],
    )
    pairs = entity_pairs(ext)
    assert ("task", "llamar a ana") in pairs
    assert ("topic", "reunion") in pairs  # accent-folded, lowercased


def test_task_labels_and_connection_triples_normalize() -> None:
    ext = Extraction(
        tasks=[TaskItem(label="  Comprar Café. ")],
        connections=[Connection(type="assigned_to", source="Tarea", target="Ana")],
    )
    assert task_labels(ext) == ["comprar cafe"]
    assert connection_triples(ext) == [("assigned_to", "tarea", "ana")]


def test_score_case_and_aggregate() -> None:
    predicted = Extraction(
        entities=[Entity(type="person", label="Ana")],
        tasks=[TaskItem(label="Call Ana")],
    )
    gold = Extraction(
        entities=[Entity(type="person", label="Ana"), Entity(type="topic", label="x")],
        tasks=[TaskItem(label="Call Ana")],
    )
    case = score_case("c1", predicted, gold, cost_usd=0.0, latency_ms=1.0)
    # 2 correct (person Ana + task), 1 missing (topic x).
    assert case.entity.tp == 2
    assert case.entity.fn == 1
    assert case.task.precision == 1.0

    report = aggregate([case])
    assert report.n_cases == 1
    assert report.entity.tp == 2


def test_gate_pass_and_fail() -> None:
    thresholds = Thresholds(
        f1_entities_min=0.80,
        task_precision_min=0.85,
        hallucination_max=0.05,
        cost_per_capture_max_usd=0.01,
    )
    good = EvalReport(
        entity=PRF(tp=9, fp=1, fn=0),
        task=PRF(tp=10, fp=0, fn=0),
        connection=PRF(tp=1, fp=0, fn=0),
        hallucination_rate=0.0,
        mean_cost_usd=0.001,
        p95_latency_ms=5.0,
        n_cases=5,
    )
    passed, failures = good.gate(thresholds)
    assert passed is True
    assert failures == []

    bad = EvalReport(
        entity=PRF(tp=1, fp=9, fn=0),  # F1 low
        task=PRF(tp=1, fp=9, fn=0),  # precision low
        connection=PRF(tp=0, fp=0, fn=0),
        hallucination_rate=0.9,
        mean_cost_usd=1.0,
        p95_latency_ms=5.0,
        n_cases=5,
    )
    passed, failures = bad.gate(thresholds)
    assert passed is False
    assert len(failures) == 4  # all four thresholds violated


# --- Property-based tests ------------------------------------------------------
@given(st.lists(st.tuples(st.text(min_size=1, max_size=4), st.integers(0, 3))))
def test_prf_against_itself_is_perfect(items: list) -> None:
    """Comparing a prediction to itself yields no FP/FN (precision = recall = 1)."""
    scores = prf(items, items)
    assert scores.fp == 0
    assert scores.fn == 0
    assert scores.precision == 1.0
    assert scores.recall == 1.0
    assert hallucination_rate(items, items) == 0.0


@given(
    st.lists(st.integers(0, 5)),
    st.lists(st.integers(0, 5)),
)
def test_prf_bounds(predicted: list, gold: list) -> None:
    """Precision, recall and F1 always lie in [0, 1]; counts are consistent."""
    scores = prf(predicted, gold)
    assert 0.0 <= scores.precision <= 1.0
    assert 0.0 <= scores.recall <= 1.0
    assert 0.0 <= scores.f1 <= 1.0
    assert scores.tp + scores.fp == len(predicted)
    assert scores.tp + scores.fn == len(gold)
