"""Unit + property tests for the pure enrichment mapping (design §8.3).

Verifies the correctness properties that do not need a database: no duplicate
derived nodes (P-COMP-2), total provenance (P-COMP-3), deterministic idempotent
shape (P-COMP-1 at the plan level), and "only extracted endpoints" for edges.
"""

from hypothesis import given
from hypothesis import strategies as st

from app.understanding.enrichment import (
    CAPTURE_REF,
    build_enrichment_plan,
    dedup_key,
)
from app.understanding.extract import Connection, Entity, Extraction, TaskItem

USER = "user-1"
CAP = "cap-1"


def _plan(extraction: Extraction):
    return build_enrichment_plan(USER, CAP, extraction)


def test_tasks_and_entities_become_typed_nodes() -> None:
    extraction = Extraction(
        entities=[
            Entity(type="person", label="Ana"),
            Entity(type="topic", label="invoice"),
        ],
        tasks=[TaskItem(label="Call Ana")],
        connections=[],
    )
    plan = _plan(extraction)
    typed = {(n.node_type, n.title) for n in plan.nodes}
    assert ("task", "Call Ana") in typed
    assert ("person", "Ana") in typed
    assert ("topic", "invoice") in typed


def test_every_node_has_exactly_one_provenance_edge() -> None:
    extraction = Extraction(
        entities=[Entity(type="person", label="Ana")],
        tasks=[TaskItem(label="Call Ana")],
        connections=[],
    )
    plan = _plan(extraction)
    provenance = [e for e in plan.edges if e.type == "derived_from"]
    # One derived_from per node, all pointing at the capture.
    assert len(provenance) == len(plan.nodes)
    assert all(e.target == CAPTURE_REF for e in provenance)
    assert {e.source for e in provenance} == {n.dedup_key for n in plan.nodes}


def test_duplicate_labels_collapse_to_one_node() -> None:
    extraction = Extraction(
        entities=[
            Entity(type="topic", label="Budget"),
            Entity(type="topic", label="budget"),  # same after normalization
        ],
        tasks=[],
        connections=[],
    )
    plan = _plan(extraction)
    topic_nodes = [n for n in plan.nodes if n.node_type == "topic"]
    assert len(topic_nodes) == 1


def test_dedup_key_is_deterministic_and_type_scoped() -> None:
    k1 = dedup_key(USER, CAP, "person", "Ana")
    k2 = dedup_key(USER, CAP, "person", " ana ")  # normalized equal
    k3 = dedup_key(USER, CAP, "topic", "Ana")  # different type
    assert k1 == k2
    assert k1 != k3


def test_assigned_to_connection_resolves_task_and_person() -> None:
    extraction = Extraction(
        entities=[Entity(type="person", label="Ana")],
        tasks=[TaskItem(label="Call Ana")],
        connections=[
            Connection(type="assigned_to", source="Call Ana", target="Ana")
        ],
    )
    plan = _plan(extraction)
    assigned = [e for e in plan.edges if e.type == "assigned_to"]
    assert len(assigned) == 1
    node_keys = {n.dedup_key for n in plan.nodes}
    assert assigned[0].source in node_keys
    assert assigned[0].target in node_keys


def test_connection_with_unknown_endpoint_is_dropped() -> None:
    extraction = Extraction(
        entities=[Entity(type="person", label="Ana")],
        tasks=[],
        connections=[
            # "Bob" was never extracted -> the edge must not be invented.
            Connection(type="mentions", source="Ana", target="Bob")
        ],
    )
    plan = _plan(extraction)
    assert [e for e in plan.edges if e.type == "mentions"] == []


# --- property-based -----------------------------------------------------------

_labels = st.text(min_size=1, max_size=12)
_conf = st.floats(min_value=0.0, max_value=1.0, allow_nan=False, allow_infinity=False)
_entities = st.lists(
    st.builds(
        Entity,
        type=st.sampled_from(["person", "project", "event", "topic", "note"]),
        label=_labels,
        confidence=_conf,
    ),
    max_size=6,
)
_tasks = st.lists(st.builds(TaskItem, label=_labels, confidence=_conf), max_size=4)
_connections = st.lists(
    st.builds(
        Connection,
        type=st.sampled_from(["mentions", "assigned_to", "relates_to"]),
        source=_labels,
        target=_labels,
        confidence=_conf,
    ),
    max_size=4,
)
_extractions = st.builds(
    Extraction, entities=_entities, tasks=_tasks, connections=_connections
)


@given(_extractions)
def test_plan_is_deterministic(extraction: Extraction) -> None:
    assert build_enrichment_plan(USER, CAP, extraction) == build_enrichment_plan(
        USER, CAP, extraction
    )


@given(_extractions)
def test_no_duplicate_node_keys(extraction: Extraction) -> None:
    keys = [n.dedup_key for n in _plan(extraction).nodes]
    assert len(keys) == len(set(keys))  # P-COMP-2


@given(_extractions)
def test_provenance_is_total(extraction: Extraction) -> None:
    plan = _plan(extraction)
    provenance = [e for e in plan.edges if e.type == "derived_from"]
    assert len(provenance) == len(plan.nodes)  # P-COMP-3
    assert all(e.target == CAPTURE_REF for e in provenance)


@given(_extractions)
def test_edges_only_reference_known_endpoints(extraction: Extraction) -> None:
    plan = _plan(extraction)
    known = {n.dedup_key for n in plan.nodes} | {CAPTURE_REF}
    for e in plan.edges:
        assert e.source in known and e.target in known
        assert e.source != e.target  # no self-loops
