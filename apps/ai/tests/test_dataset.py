"""Schema + convention checks for the versioned eval set (design §13.1).

These guard the hand-annotated gold: every ``case-*.json`` must load, validate
against the :class:`EvalCase`/:class:`Extraction` schema, carry a unique stable
id, use only allowed types, and keep its connections referentially consistent
(every endpoint points at a label the case actually annotates). This is what
lets the eval set grow to ~45 cases without silent drift (R-001).
"""

import re

from app.eval.loader import EvalCase, load_dataset
from app.understanding.extract import ConnectionType, EntityType
from app.understanding.text_utils import normalize_label

_ID_RE = re.compile(r"^case-\d{2}$")
_ALLOWED_ENTITY_TYPES = set(EntityType.__args__)  # type: ignore[attr-defined]
_ALLOWED_CONNECTION_TYPES = set(ConnectionType.__args__)  # type: ignore[attr-defined]


def test_dataset_has_stable_size_for_low_noise() -> None:
    """~45 cases: enough mass per metric for a stable, low-noise reading."""
    dataset = load_dataset()
    assert 40 <= len(dataset) <= 50
    ids = [c.id for c in dataset.cases]
    assert ids == sorted(ids)  # deterministic ordering
    assert len(ids) == len(set(ids))  # unique ids


def test_every_case_conforms_to_schema_and_ids() -> None:
    """Each case validates and uses a well-formed, stable id."""
    for case in load_dataset().cases:
        assert isinstance(case, EvalCase)
        assert _ID_RE.match(case.id), f"bad id: {case.id}"
        assert case.language in {"es", "en", "mixed"}
        assert case.description.strip()
        assert case.text.strip()


def test_gold_uses_only_allowed_types_and_nonempty_labels() -> None:
    """Gold entities/tasks/connections use the closed taxonomy and real labels."""
    for case in load_dataset().cases:
        for entity in case.gold.entities:
            assert entity.type in _ALLOWED_ENTITY_TYPES
            assert entity.label.strip()
        for task in case.gold.tasks:
            assert task.label.strip()
        for conn in case.gold.connections:
            assert conn.type in _ALLOWED_CONNECTION_TYPES
            assert conn.source.strip() and conn.target.strip()


def test_connection_endpoints_reference_annotated_labels() -> None:
    """Every connection endpoint must point at a label the case annotates.

    Guards against dangling edges: a ``source``/``target`` that matches no task
    or entity label (normalized) would be an annotation mistake.
    """
    for case in load_dataset().cases:
        known = {normalize_label(e.label) for e in case.gold.entities}
        known |= {normalize_label(t.label) for t in case.gold.tasks}
        for conn in case.gold.connections:
            assert normalize_label(conn.source) in known, (
                f"{case.id}: connection source not annotated: {conn.source!r}"
            )
            assert normalize_label(conn.target) in known, (
                f"{case.id}: connection target not annotated: {conn.target!r}"
            )


def test_dataset_covers_the_intended_diversity() -> None:
    """The set has enough mass per metric AND the hard-case buckets we designed."""
    cases = load_dataset().cases

    # Language mix: Spanish predominates (LatAm-first), with English + a mix.
    langs = [c.language for c in cases]
    assert langs.count("es") >= 15
    assert langs.count("en") >= 12
    assert langs.count("mixed") >= 1

    # Per-metric mass: plenty of cases exercise tasks, persons, topics, events.
    with_tasks = [c for c in cases if c.gold.tasks]
    with_person = [c for c in cases if any(e.type == "person" for e in c.gold.entities)]
    with_topic = [c for c in cases if any(e.type == "topic" for e in c.gold.entities)]
    with_event = [c for c in cases if any(e.type == "event" for e in c.gold.entities)]
    assert len(with_tasks) >= 15
    assert len(with_person) >= 10
    assert len(with_topic) >= 15
    assert len(with_event) >= 8

    # Hard cases: at least one capture with NOTHING actionable (all-empty gold),
    # so the exam measures that the model does not invent.
    empty_gold = [
        c
        for c in cases
        if not c.gold.entities and not c.gold.tasks and not c.gold.connections
    ]
    assert len(empty_gold) >= 2

    # Hard cases: at least one "tasks only, no entities" capture.
    tasks_only = [c for c in cases if c.gold.tasks and not c.gold.entities]
    assert len(tasks_only) >= 2
