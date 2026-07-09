"""Postgres adapter of :class:`GraphStore` — idempotent writes under RLS.

This is the production implementation of the port (design §8.3). It speaks raw
SQL (matching the F2 migration) inside ``rls_tx`` so every read/write is scoped
to the job's user by PostgreSQL, not just by application code. Idempotency comes
from the two partial unique indexes the F2 migration created:
``uq_nodes_ai_dedup_key`` and ``uq_edges_ai_src_tgt_type`` — reprocessing the
same capture hits ``ON CONFLICT`` and adds nothing (P-COMP-1/2/3).

``asyncpg`` and JSON serialization live here; the pure shape is decided upstream
in ``enrichment.py``. The offline test suite uses ``InMemoryGraphStore`` and
never imports this module's driver.
"""

import json
from typing import Any

from app.providers.base import Embedding, Usage
from app.understanding.cost_meter import CostMeter
from app.understanding.enrichment import CAPTURE_REF, EnrichmentPlan
from app.understanding.rls import rls_tx
from app.understanding.store import CaptureRow, GraphStore


def _format_vector(vector: list[float], dim: int) -> str:
    """Render a vector as a pgvector literal, padded/truncated to ``dim``.

    Real providers should emit exactly ``dim`` values; padding is a safety net so
    a dev/offline vector of a different size still satisfies the ``vector(dim)``
    column contract instead of raising.
    """
    values = list(vector[:dim]) + [0.0] * max(0, dim - len(vector))
    return "[" + ",".join(repr(float(x)) for x in values) + "]"


class PgGraphStore(GraphStore):
    """RLS-scoped, idempotent graph writer backed by asyncpg."""

    def __init__(
        self,
        pool: Any,
        *,
        embedding_dim: int,
        cost_meter: CostMeter | None = None,
    ):
        self._pool = pool
        self._embedding_dim = embedding_dim
        self._cost = cost_meter or CostMeter()

    async def load_capture(self, user_id: str, capture_id: str) -> CaptureRow | None:
        async with rls_tx(self._pool, user_id) as conn:
            row = await conn.fetchrow(
                "SELECT id, status, body, attributes FROM nodes "
                "WHERE id = $1 AND type = 'capture'",
                capture_id,
            )
        if row is None:
            return None
        attributes = row["attributes"]
        if isinstance(attributes, str):
            attributes = json.loads(attributes)
        return CaptureRow(
            id=str(row["id"]),
            status=str(row["status"]),
            body=row["body"],
            attributes=attributes or {},
        )

    async def mark_processing(self, user_id: str, capture_id: str) -> None:
        await self._set_status(user_id, capture_id, "processing")

    async def mark_failed(self, user_id: str, capture_id: str) -> None:
        await self._set_status(user_id, capture_id, "failed")

    async def _set_status(self, user_id: str, capture_id: str, status: str) -> None:
        async with rls_tx(self._pool, user_id) as conn:
            await conn.execute(
                "UPDATE nodes SET status = $1::capture_status "
                "WHERE id = $2 AND type = 'capture'",
                status,
                capture_id,
            )

    async def persist_enrichment(
        self,
        user_id: str,
        capture_id: str,
        plan: EnrichmentPlan,
        embedding: Embedding,
        usages: list[Usage],
    ) -> None:
        """Write embedding + nodes + edges + cost + status in ONE transaction."""
        async with rls_tx(self._pool, user_id) as conn:
            # 1) embedding on the capture node.
            await conn.execute(
                "UPDATE nodes SET embedding = $1::vector, embedding_model = $2 "
                "WHERE id = $3 AND type = 'capture'",
                _format_vector(embedding.vector, self._embedding_dim),
                embedding.usage.model,
                capture_id,
            )

            # 2) upsert derived nodes (idempotent by dedup_key).
            key_to_id: dict[str, str] = {CAPTURE_REF: capture_id}
            for node in plan.nodes:
                node_id = await conn.fetchval(
                    """
                    INSERT INTO nodes
                        (user_id, type, title, attributes, origin, status, confidence)
                    VALUES ($1, $2::node_type, $3, $4::jsonb, 'ai',
                            'processed'::capture_status, $5)
                    ON CONFLICT (user_id, ((attributes->>'dedup_key')))
                        WHERE origin = 'ai'
                    DO UPDATE SET confidence = EXCLUDED.confidence
                    RETURNING id
                    """,
                    user_id,
                    node.node_type,
                    node.title,
                    json.dumps(node.attributes, ensure_ascii=False),
                    node.confidence,
                )
                key_to_id[node.dedup_key] = str(node_id)

            # 3) upsert edges (provenance + semantic), idempotent by natural key.
            for edge in plan.edges:
                source_id = key_to_id.get(edge.source)
                target_id = key_to_id.get(edge.target)
                if source_id is None or target_id is None:
                    continue
                await conn.execute(
                    """
                    INSERT INTO edges
                        (user_id, type, source_node_id, target_node_id,
                         origin, confidence, user_confirmed)
                    VALUES ($1, $2, $3, $4, 'ai', $5, false)
                    ON CONFLICT (user_id, source_node_id, target_node_id, type)
                        WHERE origin = 'ai'
                    DO NOTHING
                    """,
                    user_id,
                    edge.type,
                    source_id,
                    target_id,
                    edge.confidence,
                )

            # 4) per-user cost rows (same transaction, same RLS context).
            await self._cost.record_all(conn, user_id, capture_id, usages)

            # 5) mark the capture processed.
            await conn.execute(
                "UPDATE nodes SET status = 'processed'::capture_status "
                "WHERE id = $1 AND type = 'capture'",
                capture_id,
            )
