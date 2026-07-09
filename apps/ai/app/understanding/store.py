"""GraphStore port + an in-memory adapter for offline tests.

The pipeline (design §8.2) depends on this **port**, not on Postgres directly —
the same dependency-inversion the codebase already uses for ``AIProvider`` and
F1's ``UnderstandingQueuePort``. The production adapter is ``PgGraphStore``
(``graph_writer.py``, raw SQL under RLS); ``InMemoryGraphStore`` here lets the
whole comprehension pipeline and its correctness properties (P-COMP-1/2/3/6)
run with zero infrastructure.

Every operation is scoped to a ``user_id``: the in-memory adapter mimics RLS by
refusing to see or touch rows of another user (fail-closed), so tests exercise
the isolation contract (P-COMP-4) at the logic level.
"""

import uuid
from abc import ABC, abstractmethod
from dataclasses import dataclass, field

from app.providers.base import Embedding, Usage
from app.understanding.enrichment import CAPTURE_REF, EnrichmentPlan


@dataclass(frozen=True)
class CaptureRow:
    """The subset of a capture node the pipeline needs to comprehend it."""

    id: str
    status: str  # raw | processing | processed | failed
    body: str | None
    attributes: dict = field(default_factory=dict)


class GraphStore(ABC):
    """Contract for reading a capture and writing its enrichment under RLS."""

    @abstractmethod
    async def load_capture(self, user_id: str, capture_id: str) -> CaptureRow | None:
        """Return the capture if it belongs to ``user_id``, else ``None`` (RLS)."""

    @abstractmethod
    async def mark_processing(self, user_id: str, capture_id: str) -> None:
        """Transition the capture ``* -> processing``."""

    @abstractmethod
    async def mark_failed(self, user_id: str, capture_id: str) -> None:
        """Transition the capture to ``failed`` WITHOUT touching its raw body."""

    @abstractmethod
    async def persist_enrichment(
        self,
        user_id: str,
        capture_id: str,
        plan: EnrichmentPlan,
        embedding: Embedding,
        usages: list[Usage],
    ) -> None:
        """Atomically write the enrichment and mark the capture ``processed``.

        Idempotent: reprocessing the same capture yields the same graph (no
        duplicate nodes/edges) — P-COMP-1/2/3.
        """


class InMemoryGraphStore(GraphStore):
    """Deterministic, infra-free adapter for unit/property tests."""

    def __init__(self) -> None:
        # (user_id, capture_id) -> CaptureRow. Seeding a capture makes it visible
        # only to that user, mimicking RLS.
        self._captures: dict[tuple[str, str], CaptureRow] = {}
        # (user_id, dedup_key) -> node id
        self._node_ids: dict[tuple[str, str], str] = {}
        # node id -> stored node record
        self.nodes: dict[str, dict] = {}
        # (user_id, source_id, target_id, type) -> stored edge record
        self.edges: dict[tuple[str, str, str, str], dict] = {}
        # capture id -> (vector, model)
        self.embeddings: dict[str, tuple[list[float], str]] = {}
        self.llm_usage: list[dict] = []

    # --- test seeding helpers -------------------------------------------------
    def seed_capture(
        self,
        user_id: str,
        capture_id: str,
        *,
        body: str | None,
        status: str = "raw",
        attributes: dict | None = None,
    ) -> None:
        self._captures[(user_id, capture_id)] = CaptureRow(
            id=capture_id, status=status, body=body, attributes=attributes or {}
        )

    def nodes_for(self, user_id: str) -> list[dict]:
        return [n for n in self.nodes.values() if n["user_id"] == user_id]

    def edges_for(self, user_id: str) -> list[dict]:
        return [e for e in self.edges.values() if e["user_id"] == user_id]

    # --- GraphStore -----------------------------------------------------------
    async def load_capture(self, user_id: str, capture_id: str) -> CaptureRow | None:
        return self._captures.get((user_id, capture_id))

    async def _set_status(self, user_id: str, capture_id: str, status: str) -> None:
        current = self._captures.get((user_id, capture_id))
        if current is None:
            return  # RLS: not this user's row — silent no-op
        self._captures[(user_id, capture_id)] = CaptureRow(
            id=current.id,
            status=status,
            body=current.body,
            attributes=current.attributes,
        )

    async def mark_processing(self, user_id: str, capture_id: str) -> None:
        await self._set_status(user_id, capture_id, "processing")

    async def mark_failed(self, user_id: str, capture_id: str) -> None:
        await self._set_status(user_id, capture_id, "failed")

    async def persist_enrichment(
        self,
        user_id: str,
        capture_id: str,
        plan: EnrichmentPlan,
        embedding: Embedding,
        usages: list[Usage],
    ) -> None:
        # 1) embedding on the capture node.
        self.embeddings[capture_id] = (list(embedding.vector), embedding.usage.model)

        # 2) upsert nodes (idempotent by (user_id, dedup_key)).
        key_to_id: dict[str, str] = {CAPTURE_REF: capture_id}
        for node in plan.nodes:
            store_key = (user_id, node.dedup_key)
            node_id = self._node_ids.get(store_key)
            if node_id is None:
                node_id = str(uuid.uuid4())
                self._node_ids[store_key] = node_id
                self.nodes[node_id] = {
                    "id": node_id,
                    "user_id": user_id,
                    "type": node.node_type,
                    "title": node.title,
                    "attributes": dict(node.attributes),
                    "origin": "ai",
                    "status": "processed",
                    "confidence": node.confidence,
                }
            else:
                # existing node: refresh confidence, matching ON CONFLICT DO UPDATE.
                self.nodes[node_id]["confidence"] = node.confidence
            key_to_id[node.dedup_key] = node_id

        # 3) upsert edges (idempotent by (user_id, source, target, type)).
        for edge in plan.edges:
            source_id = key_to_id.get(edge.source)
            target_id = key_to_id.get(edge.target)
            if source_id is None or target_id is None:
                continue  # an unresolved endpoint is never written
            ekey = (user_id, source_id, target_id, edge.type)
            if ekey not in self.edges:
                self.edges[ekey] = {
                    "user_id": user_id,
                    "type": edge.type,
                    "source_node_id": source_id,
                    "target_node_id": target_id,
                    "origin": "ai",
                    "confidence": edge.confidence,
                    "user_confirmed": False,
                }

        # 4) cost rows.
        for usage in usages:
            self.llm_usage.append(
                {
                    "user_id": user_id,
                    "capture_id": capture_id,
                    "provider": usage.provider,
                    "model": usage.model,
                    "operation": usage.operation,
                    "input_tokens": usage.input_tokens,
                    "output_tokens": usage.output_tokens,
                    "cost_usd": usage.cost_usd,
                }
            )

        # 5) mark processed.
        await self._set_status(user_id, capture_id, "processed")
