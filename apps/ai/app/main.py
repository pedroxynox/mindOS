"""mindOS AI service — FastAPI entrypoint.

Exposes a health check and, when enabled, starts the comprehension worker (the
BullMQ consumer of the ``understanding`` queue) as part of the app lifespan, so
a single deployment can both answer ``/health`` and drain the queue (design
§8/§11). The understanding pipeline, embeddings and graph writes live behind the
provider-agnostic AIProvider layer (ADR-09) and are only touched when the worker
is enabled.
"""

import logging
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from typing import Literal

from fastapi import FastAPI
from pydantic import BaseModel

from app import __version__
from app.config import settings

logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    """Start/stop the comprehension worker alongside the API.

    Gated by ``settings.worker_enabled`` (OFF by default) so health-only
    deployments and the offline test suite never open Redis/Postgres. A startup
    failure is logged loudly but does NOT take the service down — ``/health``
    stays up so the problem is observable instead of a silent crash loop.
    """
    worker = None
    if settings.worker_enabled:
        try:
            # Lazy import: pulls the optional 'ai' deps (bullmq/asyncpg) only
            # when the worker is actually enabled.
            from app.understanding.worker import build_worker

            worker = await build_worker(settings)
            logger.info(
                "understanding worker started: consuming the queue "
                "(provider=%s)",
                settings.llm_provider,
            )
        except Exception:
            logger.exception(
                "understanding worker failed to start; /health stays up so the "
                "problem is visible — fix config/infra and restart"
            )
            worker = None
    else:
        logger.info(
            "understanding worker disabled (set WORKER_ENABLED=true to run it)"
        )
    try:
        yield
    finally:
        if worker is not None:
            try:
                await worker.close()
                logger.info("understanding worker stopped")
            except Exception:
                logger.exception("error while closing the understanding worker")


app = FastAPI(title="mindOS AI Service", version=__version__, lifespan=lifespan)


class HealthStatus(BaseModel):
    """Response model for the liveness endpoint."""

    status: Literal["ok"]
    service: Literal["ai"]
    version: str
    timestamp: str


@app.get("/health", response_model=HealthStatus)
def health() -> HealthStatus:
    """Liveness endpoint. Confirms the AI service process is up."""
    return HealthStatus(
        status="ok",
        service="ai",
        version=__version__,
        timestamp=datetime.now(timezone.utc).isoformat(),
    )
