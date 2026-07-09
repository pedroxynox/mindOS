"""BullMQ consumer for the ``understanding`` queue (design §8.1, ADR-019).

A single Python process consumes the queue F1 already produces to and runs the
comprehension pipeline. The job-handling *logic* (``handle_job`` /
``handle_failed``) is pure and unit-testable with fakes; only ``build_worker``
touches BullMQ, imported lazily so the offline test suite needs neither the
``bullmq`` package nor a Redis connection.

Retries/backoff and ``removeOnFail:false`` are configured by the F1 producer;
this consumer only reacts to the terminal ``failed`` event to transition the
capture to ``failed`` once retries are exhausted — the raw capture is never
touched (P-COMP-5).
"""

import logging
from typing import Any

from app.config import Settings
from app.providers.base import AIProvider
from app.understanding.contract import (
    SUPPORTED_SCHEMA_VERSION,
    UNDERSTANDING_JOB,
    UNDERSTANDING_QUEUE,
    UnderstandingJobData,
)
from app.understanding.pipeline import (
    UnderstandingResult,
    run_understanding,
)
from app.understanding.store import GraphStore

logger = logging.getLogger(__name__)


async def handle_job(
    job_name: str,
    job_data: dict,
    *,
    provider: AIProvider,
    store: GraphStore,
) -> UnderstandingResult:
    """Validate one job's contract and run the pipeline (pure, testable).

    Rejects an unexpected job name or an unsupported ``schema_version`` loudly
    (design §14): a contract we do not understand is never guessed.
    """
    if job_name != UNDERSTANDING_JOB:
        raise ValueError(f"unexpected job: {job_name!r}")
    data = UnderstandingJobData(**job_data)
    if data.schema_version != SUPPORTED_SCHEMA_VERSION:
        raise ValueError(f"unsupported schema_version: {data.schema_version}")
    return await run_understanding(
        data.capture_id, data.user_id, provider=provider, store=store
    )


async def handle_failed(
    job_data: dict,
    attempts_made: int,
    max_attempts: int,
    *,
    store: GraphStore,
) -> bool:
    """On the FINAL failed attempt, mark the capture ``failed``. Returns whether
    it did (so callers/tests can assert). Earlier attempts are left for BullMQ to
    retry; the capture stays ``processing`` until then.
    """
    if attempts_made < max_attempts:
        return False
    try:
        data = UnderstandingJobData(**job_data)
    except Exception:  # a job we can't even parse — nothing to transition
        logger.error("failed job has unparseable data: %r", job_data)
        return False
    await store.mark_failed(data.user_id, data.capture_id)
    logger.error(
        "comprehension failed capture=%s user=%s (attempts=%d)",
        data.capture_id,
        data.user_id,
        attempts_made,
    )
    return True


async def build_worker(settings: Settings) -> Any:
    """Construct the live BullMQ worker (lazy deps: bullmq + asyncpg).

    Wires the configured provider and a Postgres-backed graph store, consuming
    the same queue/connection as F1. Kept thin — all judgement is in
    ``handle_job`` / the pipeline.
    """
    from bullmq import Worker  # lazy: optional 'ai' dependency

    from app.providers.factory import build_provider
    from app.understanding.graph_writer import PgGraphStore
    from app.understanding.rls import create_pool

    provider = build_provider(settings)
    pool = await create_pool(settings.database_url)
    store = PgGraphStore(pool, embedding_dim=settings.embedding_dim)

    async def process(job: Any, token: str) -> None:
        await handle_job(job.name, job.data, provider=provider, store=store)

    worker = Worker(
        UNDERSTANDING_QUEUE,
        process,
        {"connection": settings.redis_url, "concurrency": 4},
    )

    async def on_failed(job: Any, err: Any) -> None:
        max_attempts = (job.opts or {}).get("attempts", 1)
        await handle_failed(
            job.data, job.attemptsMade, max_attempts, store=store
        )

    worker.on("failed", on_failed)
    return worker
