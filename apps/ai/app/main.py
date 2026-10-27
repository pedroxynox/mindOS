"""mindOS AI service — FastAPI entrypoint.

Exposes a health check and, when enabled, starts the comprehension worker (the
BullMQ consumer of the ``understanding`` queue) as part of the app lifespan, so
a single deployment can both answer ``/health`` and drain the queue (design
§8/§11). The understanding pipeline, embeddings and graph writes live behind the
provider-agnostic AIProvider layer (ADR-09) and are only touched when the worker
is enabled.
"""

import asyncio
import hmac
import logging
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from typing import Literal

from fastapi import FastAPI, Header, HTTPException, Request
from pydantic import BaseModel, Field

from app import __version__
from app.config import settings
from app.providers.factory import build_provider
from app.query.service import MAX_CONTEXT_NOTES, answer_question

logger = logging.getLogger(__name__)

# Lazily-created singletons for the RAG endpoint. The DB pool and provider are
# only opened on the first /internal/query call, so health-only deployments and
# the offline test suite never touch Postgres or a real LLM.
_pool: object | None = None
_pool_lock = asyncio.Lock()
_provider: object | None = None


async def _get_pool() -> object:
    global _pool
    if _pool is None:
        async with _pool_lock:
            if _pool is None:
                from app.understanding.rls import create_pool

                # Small pool: the worker holds its own; keep Neon connections low.
                _pool = await create_pool(
                    settings.database_url, min_size=1, max_size=3
                )
    return _pool


def _get_provider() -> object:
    global _provider
    if _provider is None:
        _provider = build_provider(settings)
    return _provider


def _require_internal_auth(token: str | None) -> None:
    """Fail-closed guard for the internal endpoint (constant-time compare)."""
    secret = settings.query_internal_secret
    if not secret:
        raise HTTPException(status_code=503, detail="query endpoint not configured")
    if not token or not hmac.compare_digest(token, secret):
        raise HTTPException(status_code=401, detail="unauthorized")


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
        # Close the RAG pool if it was opened on demand.
        global _pool
        if _pool is not None:
            try:
                await _pool.close()  # type: ignore[attr-defined]
            except Exception:
                logger.exception("error while closing the query DB pool")
            finally:
                _pool = None


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


class QueryRequest(BaseModel):
    """Internal RAG request. ``user_id`` is trusted: the API sets it after
    authenticating the end user; this endpoint is not exposed publicly."""

    user_id: str = Field(min_length=1)
    question: str = Field(min_length=1, max_length=1000)
    limit: int | None = Field(default=None, ge=1, le=20)


class QuerySource(BaseModel):
    """A cited capture backing the answer."""

    capture_id: str
    snippet: str


class QueryResponse(BaseModel):
    """The grounded answer plus its citations."""

    answer: str
    sources: list[QuerySource]


class TranscribeResponse(BaseModel):
    """Transcript of one voice note plus what it cost (ADR-021)."""

    text: str
    provider: str
    model: str
    duration_s: float | None
    cost_usd: float


_AUDIO_TYPES = {
    "audio/webm",
    "audio/ogg",
    "audio/opus",
    "audio/mp4",
    "audio/m4a",
    "audio/x-m4a",
    "audio/aac",
    "audio/mpeg",
    "audio/mp3",
    "audio/wav",
    "audio/x-wav",
    "audio/wave",
    "audio/flac",
}


@app.post("/internal/transcribe", response_model=TranscribeResponse)
async def internal_transcribe(
    request: Request,
    duration_ms: int | None = None,
    x_internal_token: str | None = Header(default=None),
) -> TranscribeResponse:
    """Transcribe a voice note sent as the raw request body (ADR-021).

    Called only by the API (shared internal token). The audio is held in memory
    for the duration of this request and never written anywhere — voice is
    transcribed and discarded.
    """
    _require_internal_auth(x_internal_token)
    content_type = (request.headers.get("content-type") or "").split(";")[0]
    content_type = content_type.strip().lower()
    if content_type not in _AUDIO_TYPES:
        raise HTTPException(status_code=415, detail="unsupported audio type")

    audio = await request.body()
    if not audio:
        raise HTTPException(status_code=422, detail="empty audio")
    if len(audio) > settings.transcribe_max_bytes:
        raise HTTPException(status_code=413, detail="audio too large")

    duration_s = duration_ms / 1000.0 if duration_ms and duration_ms > 0 else None
    provider = _get_provider()
    try:
        completion = await provider.transcribe(  # type: ignore[attr-defined]
            audio, content_type, duration_s=duration_s
        )
    except NotImplementedError as exc:
        raise HTTPException(status_code=501, detail=str(exc)) from exc
    except Exception as exc:  # upstream failure: the API retries later
        logger.warning("transcription failed: %s", exc)
        raise HTTPException(status_code=502, detail="transcription failed") from exc

    usage = completion.usage
    return TranscribeResponse(
        text=completion.text.strip(),
        provider=usage.provider,
        model=usage.model,
        duration_s=duration_s,
        cost_usd=usage.cost_usd,
    )


@app.post("/internal/query", response_model=QueryResponse)
async def internal_query(
    req: QueryRequest,
    x_internal_token: str | None = Header(default=None),
) -> QueryResponse:
    """Answer a question from the user's own notes (RAG).

    Guarded by the shared internal token. Called only by the API, which has
    already authenticated the end user and supplies ``user_id``. RLS still scopes
    every read to that user inside the AI service (defense in depth).
    """
    _require_internal_auth(x_internal_token)
    question = req.question.strip()
    if not question:
        raise HTTPException(status_code=422, detail="question must not be empty")

    pool = await _get_pool()
    provider = _get_provider()
    result = await answer_question(
        req.user_id,
        question,
        pool=pool,
        provider=provider,  # type: ignore[arg-type]
        settings=settings,
        limit=req.limit or MAX_CONTEXT_NOTES,
    )
    return QueryResponse(
        answer=result.answer,
        sources=[
            QuerySource(capture_id=s.capture_id, snippet=s.snippet)
            for s in result.sources
        ],
    )
