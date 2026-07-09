"""End-to-end comprehension pipeline tests (FakeProvider + InMemoryGraphStore).

Exercises the pipeline's correctness with zero infrastructure: idempotent
delivery (P-COMP-1), per-user isolation (P-COMP-4), the capture surviving a
failure (P-COMP-5), and "the AI proposes" (P-COMP-6).
"""

import pytest

from app.providers.fake_provider import FakeProvider
from app.understanding.pipeline import Outcome, run_understanding
from app.understanding.store import InMemoryGraphStore

USER = "user-1"
CAP = "cap-1"


def _store_with_capture(body: str, status: str = "raw") -> InMemoryGraphStore:
    store = InMemoryGraphStore()
    store.seed_capture(USER, CAP, body=body, status=status)
    return store


async def _run(store: InMemoryGraphStore, user: str = USER):
    return await run_understanding(
        CAP, user, provider=FakeProvider(), store=store
    )


async def test_processes_capture_and_enriches_graph() -> None:
    store = _store_with_capture("Call Ana tomorrow about the invoice.")
    result = await _run(store)

    assert result.outcome is Outcome.PROCESSED
    assert (await store.load_capture(USER, CAP)).status == "processed"

    nodes = store.nodes_for(USER)
    assert any(n["type"] == "task" for n in nodes)
    assert any(n["type"] == "person" and n["title"] == "Ana" for n in nodes)
    # Every derived node is AI-proposed, never pre-confirmed (P-COMP-6).
    assert all(n["origin"] == "ai" for n in nodes)
    assert all(0.0 <= n["confidence"] <= 1.0 for n in nodes)
    # Edges are unconfirmed proposals.
    assert all(e["user_confirmed"] is False for e in store.edges_for(USER))
    # The capture got an embedding + a cost row per model call (complete+embed).
    assert CAP in store.embeddings
    assert len(store.llm_usage) == 2
    assert {u["operation"] for u in store.llm_usage} == {"complete", "embed"}


async def test_every_derived_node_has_provenance_to_capture() -> None:
    store = _store_with_capture("Call Ana about the budget.")
    await _run(store)
    provenance = [e for e in store.edges_for(USER) if e["type"] == "derived_from"]
    node_ids = {n["id"] for n in store.nodes_for(USER)}
    assert len(provenance) == len(node_ids)  # P-COMP-3
    assert all(e["target_node_id"] == CAP for e in provenance)
    assert {e["source_node_id"] for e in provenance} == node_ids


async def test_reprocessing_is_idempotent() -> None:
    """Re-running the write (P-COMP-1) adds no duplicate nodes/edges."""
    store = _store_with_capture("Call Ana about the invoice.")
    await _run(store)
    nodes_after_first = len(store.nodes_for(USER))
    edges_after_first = len(store.edges_for(USER))

    # Force a re-run of the write path (simulate a duplicate delivery that
    # bypassed the 'processed' short-circuit) by resetting status to raw.
    store.seed_capture(USER, CAP, body="Call Ana about the invoice.", status="raw")
    await _run(store)

    assert len(store.nodes_for(USER)) == nodes_after_first
    assert len(store.edges_for(USER)) == edges_after_first


async def test_already_processed_is_a_noop() -> None:
    store = _store_with_capture("Buy milk.", status="processed")
    result = await _run(store)
    assert result.outcome is Outcome.ALREADY_PROCESSED
    assert store.nodes_for(USER) == []  # nothing written


async def test_capture_of_another_user_is_not_found() -> None:
    store = _store_with_capture("Buy milk.")
    result = await _run(store, user="intruder")  # P-COMP-4: RLS-style isolation
    assert result.outcome is Outcome.NOT_FOUND
    assert store.nodes_for("intruder") == []
    assert (await store.load_capture(USER, CAP)).status == "raw"  # untouched


async def test_voice_without_body_and_no_loader_raises() -> None:
    store = _store_with_capture("", status="raw")
    with pytest.raises(ValueError):
        await _run(store)
    # The capture was moved to 'processing' but its body is untouched (P-COMP-5);
    # the worker's on_failed will later transition it to 'failed'.
    assert (await store.load_capture(USER, CAP)).body == ""
