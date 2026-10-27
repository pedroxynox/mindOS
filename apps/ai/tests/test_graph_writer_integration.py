"""Integration: PgGraphStore against a REAL Postgres + pgvector under RLS.

Skipped unless RUN_INTEGRATION=1 (needs a live DB — see infra/ and R-007). This
validates the correctness properties that the in-memory store cannot: real RLS
isolation (P-COMP-4), idempotent writes on the partial unique indexes
(P-COMP-1/2/3), mandatory provenance, the embedding column write, and per-user
cost rows — all as the non-owner ``mindos_app`` role so FORCE ROW LEVEL SECURITY
is exercised for real.
"""

import os
import uuid

import pytest

pytestmark = pytest.mark.skipif(
    os.environ.get("RUN_INTEGRATION") != "1",
    reason="integration test; set RUN_INTEGRATION=1 with a live Postgres+pgvector",
)

pytest.importorskip("asyncpg")

from app.providers.fake_provider import FakeProvider  # noqa: E402
from app.understanding.graph_writer import PgGraphStore  # noqa: E402
from app.understanding.pipeline import Outcome, run_understanding  # noqa: E402
from app.understanding.rls import create_pool, rls_tx  # noqa: E402

APP_DSN = os.environ.get(
    "APP_DATABASE_URL", "postgresql://mindos_app:mindos_app@127.0.0.1:5432/mindos"
)


async def _seed_user(pool, user_id: str) -> None:
    # users has no RLS; insert directly (mindos_app has INSERT on users).
    async with pool.acquire() as conn:
        await conn.execute(
            "INSERT INTO users (id, email, password_hash, updated_at) "
            "VALUES ($1, $2, 'x', now())",
            user_id,
            f"{user_id}@example.test",
        )


async def _seed_capture(pool, user_id: str, capture_id: str, body: str) -> None:
    async with rls_tx(pool, user_id) as conn:
        await conn.execute(
            "INSERT INTO nodes (id, user_id, type, body, status, origin, updated_at) "
            "VALUES ($1, $2, 'capture', $3, 'raw', 'manual_text', now())",
            capture_id,
            user_id,
            body,
        )


async def _count(pool, user_id: str, sql: str) -> int:
    async with rls_tx(pool, user_id) as conn:
        return await conn.fetchval(sql)


async def test_pipeline_enriches_graph_under_real_rls() -> None:
    pool = await create_pool(APP_DSN)
    try:
        user_id = str(uuid.uuid4())
        capture_id = str(uuid.uuid4())
        await _seed_user(pool, user_id)
        await _seed_capture(pool, user_id, capture_id, "Call Ana about the invoice.")

        store = PgGraphStore(pool, embedding_dim=1536)
        result = await run_understanding(
            capture_id, user_id, provider=FakeProvider(), store=store
        )
        assert result.outcome is Outcome.PROCESSED

        # Capture processed + embedding written (pgvector column).
        async with rls_tx(pool, user_id) as conn:
            row = await conn.fetchrow(
                "SELECT status, (embedding IS NOT NULL) AS has_emb, embedding_model "
                "FROM nodes WHERE id = $1",
                capture_id,
            )
        assert row["status"] == "processed"
        assert row["has_emb"] is True
        assert row["embedding_model"]

        # Derived nodes (origin='ai'), each with exactly one derived_from edge.
        derived = await _count(
            pool, user_id, "SELECT count(*) FROM nodes WHERE origin='ai'"
        )
        provenance = await _count(
            pool, user_id, "SELECT count(*) FROM edges WHERE type='derived_from'"
        )
        assert derived > 0
        assert provenance == derived  # P-COMP-3

        # Edges are AI proposals, never pre-confirmed (P-COMP-6).
        unconfirmed = await _count(
            pool,
            user_id,
            "SELECT count(*) FROM edges WHERE origin='ai' AND user_confirmed=false",
        )
        total_edges = await _count(pool, user_id, "SELECT count(*) FROM edges")
        assert unconfirmed == total_edges

        # Per-user cost rows recorded (complete + embed).
        usage = await _count(pool, user_id, "SELECT count(*) FROM llm_usage")
        assert usage == 2
    finally:
        await pool.close()


async def test_reprocess_is_idempotent_on_real_indexes() -> None:
    pool = await create_pool(APP_DSN)
    try:
        user_id = str(uuid.uuid4())
        capture_id = str(uuid.uuid4())
        await _seed_user(pool, user_id)
        await _seed_capture(pool, user_id, capture_id, "Call Ana about the budget.")
        store = PgGraphStore(pool, embedding_dim=1536)

        await run_understanding(
            capture_id, user_id, provider=FakeProvider(), store=store
        )
        nodes1 = await _count(pool, user_id, "SELECT count(*) FROM nodes")
        edges1 = await _count(pool, user_id, "SELECT count(*) FROM edges")

        # Force the write path again (reset status), simulating a duplicate.
        async with rls_tx(pool, user_id) as conn:
            await conn.execute(
                "UPDATE nodes SET status='raw' WHERE id=$1", capture_id
            )
        await run_understanding(
            capture_id, user_id, provider=FakeProvider(), store=store
        )

        nodes2 = await _count(pool, user_id, "SELECT count(*) FROM nodes")
        edges2 = await _count(pool, user_id, "SELECT count(*) FROM edges")
        assert nodes2 == nodes1  # P-COMP-1/2 (ON CONFLICT DO NOTHING)
        assert edges2 == edges1  # P-COMP-3
    finally:
        await pool.close()


async def test_another_user_cannot_see_the_capture() -> None:
    pool = await create_pool(APP_DSN)
    try:
        owner = str(uuid.uuid4())
        intruder = str(uuid.uuid4())
        capture_id = str(uuid.uuid4())
        await _seed_user(pool, owner)
        await _seed_user(pool, intruder)
        await _seed_capture(pool, owner, capture_id, "Private note.")

        store = PgGraphStore(pool, embedding_dim=1536)
        # RLS: the intruder's context cannot load the owner's capture (P-COMP-4).
        assert await store.load_capture(intruder, capture_id) is None
        # And an empty context sees nothing (fail-closed).
        async with pool.acquire() as conn:
            visible = await conn.fetchval(
                "SELECT count(*) FROM nodes WHERE id = $1", capture_id
            )
        assert visible == 0
    finally:
        await pool.close()


async def test_detected_expense_is_written_in_the_users_currency() -> None:
    # mejoras-v2 §E: the ambiguous "$" resolves to users.currency, read in the
    # same RLS-scoped load as the capture; the expense is a `note` with
    # kind=expense and its derived_from edge, like a manual one.
    pool = await create_pool(APP_DSN)
    try:
        user_id = str(uuid.uuid4())
        capture_id = str(uuid.uuid4())
        await _seed_user(pool, user_id)
        async with pool.acquire() as conn:
            await conn.execute(
                "UPDATE users SET currency = 'MXN' WHERE id = $1", user_id
            )
        await _seed_capture(pool, user_id, capture_id, "Paid $12 for lunch.")

        store = PgGraphStore(pool, embedding_dim=1536)
        capture = await store.load_capture(user_id, capture_id)
        assert capture is not None
        assert capture.user_currency == "MXN"
        assert capture.created_at is not None

        await run_understanding(
            capture_id, user_id, provider=FakeProvider(), store=store
        )

        async with rls_tx(pool, user_id) as conn:
            rows = await conn.fetch(
                "SELECT id, type, attributes->>'currency' AS currency, "
                "(attributes->>'amount')::float AS amount, "
                "attributes->>'category' AS category, "
                "attributes->>'spent_at' AS spent_at "
                "FROM nodes WHERE attributes->>'kind' = 'expense'"
            )
            assert len(rows) == 1
            expense = rows[0]
            edges = await conn.fetchval(
                "SELECT count(*) FROM edges WHERE source_node_id = $1 "
                "AND target_node_id = $2 AND type = 'derived_from'",
                expense["id"],
                capture_id,
            )
        assert expense["type"] == "note"
        assert (expense["currency"], expense["amount"]) == ("MXN", 12.0)
        assert expense["category"] == "food"
        assert expense["spent_at"].endswith("Z")
        assert edges == 1
        # extraction + expense + embedding cost rows.
        assert await _count(pool, user_id, "SELECT count(*) FROM llm_usage") == 3
    finally:
        await pool.close()
