"""Integration: the BullMQ worker against REAL Redis + Postgres.

Skipped unless RUN_INTEGRATION=1 (needs live Redis + Postgres — see R-007).
Validates handoff dedup by ``jobId`` (P-COMP-1) and end-to-end consumption:
a job on the same queue F1 produces to drives the pipeline until the capture is
``processed``.
"""

import asyncio
import os
import uuid

import pytest

pytestmark = pytest.mark.skipif(
    os.environ.get("RUN_INTEGRATION") != "1",
    reason="integration test; set RUN_INTEGRATION=1 with live Redis + Postgres",
)

pytest.importorskip("asyncpg")
pytest.importorskip("bullmq")

from bullmq import Queue, Worker  # noqa: E402

from app.providers.fake_provider import FakeProvider  # noqa: E402
from app.understanding.contract import (  # noqa: E402
    UNDERSTANDING_JOB,
    UNDERSTANDING_QUEUE,
)
from app.understanding.graph_writer import PgGraphStore  # noqa: E402
from app.understanding.rls import create_pool, rls_tx  # noqa: E402
from app.understanding.worker import handle_job  # noqa: E402

REDIS_URL = os.environ.get("REDIS_URL", "redis://127.0.0.1:6379")
APP_DSN = os.environ.get(
    "APP_DATABASE_URL", "postgresql://mindos_app:mindos_app@127.0.0.1:5432/mindos"
)


def _job_data(user_id: str, capture_id: str) -> dict:
    return {
        "schema_version": 1,
        "capture_id": capture_id,
        "user_id": user_id,
        "enqueued_at": "2026-07-09T00:00:00Z",
    }


async def test_dedup_by_job_id() -> None:
    queue = Queue(UNDERSTANDING_QUEUE, {"connection": REDIS_URL})
    try:
        await queue.obliterate(force=True)
        capture_id = str(uuid.uuid4())
        data = _job_data(str(uuid.uuid4()), capture_id)
        # Same jobId twice -> BullMQ keeps a single job (handoff idempotency, P7).
        await queue.add(UNDERSTANDING_JOB, data, {"jobId": capture_id})
        await queue.add(UNDERSTANDING_JOB, data, {"jobId": capture_id})
        counts = await queue.getJobCounts("waiting", "active", "delayed")
        assert sum(counts.values()) == 1
    finally:
        await queue.obliterate(force=True)
        await queue.close()


async def test_worker_processes_job_end_to_end() -> None:
    pool = await create_pool(APP_DSN)
    queue = Queue(UNDERSTANDING_QUEUE, {"connection": REDIS_URL})
    await queue.obliterate(force=True)

    user_id = str(uuid.uuid4())
    capture_id = str(uuid.uuid4())
    async with pool.acquire() as conn:
        await conn.execute(
            "INSERT INTO users (id, email, password_hash, updated_at) "
            "VALUES ($1, $2, 'x', now())",
            user_id,
            f"{user_id}@example.test",
        )
    async with rls_tx(pool, user_id) as conn:
        await conn.execute(
            "INSERT INTO nodes (id, user_id, type, body, status, origin, updated_at) "
            "VALUES ($1, $2, 'capture', 'Call Ana about the invoice.', 'raw', "
            "'manual_text', now())",
            capture_id,
            user_id,
        )

    store = PgGraphStore(pool, embedding_dim=1536)
    provider = FakeProvider()

    async def process(job, token):
        return await handle_job(job.name, job.data, provider=provider, store=store)

    worker = Worker(UNDERSTANDING_QUEUE, process, {"connection": REDIS_URL})
    try:
        await queue.add(
            UNDERSTANDING_JOB, _job_data(user_id, capture_id), {"jobId": capture_id}
        )
        # Poll until the worker has processed the capture (bounded wait).
        status = None
        for _ in range(40):
            async with rls_tx(pool, user_id) as conn:
                status = await conn.fetchval(
                    "SELECT status FROM nodes WHERE id = $1", capture_id
                )
            if status == "processed":
                break
            await asyncio.sleep(0.5)
        assert status == "processed"

        derived = None
        async with rls_tx(pool, user_id) as conn:
            derived = await conn.fetchval(
                "SELECT count(*) FROM nodes WHERE origin='ai'"
            )
        assert derived > 0
    finally:
        await worker.close()
        await queue.obliterate(force=True)
        await queue.close()
        await pool.close()
