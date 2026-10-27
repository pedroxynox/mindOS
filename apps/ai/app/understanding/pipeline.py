"""Comprehension pipeline orchestration (design §8.2).

    load ─▶ (transcribe?) ─▶ extract ─▶ (expenses?) ─▶ embed ─▶ persist
      │                         │            │            │         │
   RLS read                  LLM json    2nd small    AIProvider  GraphStore
   + status                  + usage     call, only   .embed()    (one RLS tx)
                                         on a money cue

The heavy model calls happen BETWEEN short transactions (never holding a DB lock
during a slow network call). The final write is a single all-or-nothing step, so
a failure never half-writes the graph and never mutates the raw capture
(Constitution §9/§10; P-COMP-5). Idempotent by delivery: a capture already
``processed`` is a no-op (P-COMP-1).
"""

import logging
from dataclasses import dataclass
from datetime import UTC, datetime
from enum import Enum
from typing import Awaitable, Callable

from app.providers.base import AIProvider, Usage
from app.understanding.enrichment import build_enrichment_plan, with_expenses
from app.understanding.expenses import ExpenseItem, detect_expenses
from app.understanding.extract import run_extraction
from app.understanding.store import CaptureRow, GraphStore

logger = logging.getLogger(__name__)

#: Currency of a detected expense when neither the note nor the user says.
FALLBACK_CURRENCY = "USD"

# Fetches (audio_bytes, content_type) for a voice capture with no body. Injected
# so the pipeline stays decoupled from S3; ``None`` means voice-without-body is
# not supported in this deployment (raises a clear error, treated as a failed
# attempt).
AudioLoader = Callable[[CaptureRow], Awaitable[tuple[bytes, str]]]


class Outcome(str, Enum):
    """Terminal result of processing one job (for the worker and tests)."""

    NOT_FOUND = "not_found"  # RLS: not this user's capture, or it doesn't exist
    ALREADY_PROCESSED = "already_processed"  # duplicate delivery → no-op
    PROCESSED = "processed"  # enriched successfully


@dataclass(frozen=True)
class UnderstandingResult:
    outcome: Outcome


async def run_understanding(
    capture_id: str,
    user_id: str,
    *,
    provider: AIProvider,
    store: GraphStore,
    audio_loader: AudioLoader | None = None,
) -> UnderstandingResult:
    """Comprehend one capture and enrich the graph. Idempotent per capture."""
    capture = await store.load_capture(user_id, capture_id)
    if capture is None:
        return UnderstandingResult(Outcome.NOT_FOUND)
    if capture.status == "processed":
        return UnderstandingResult(Outcome.ALREADY_PROCESSED)

    await store.mark_processing(user_id, capture_id)

    usages: list[Usage] = []
    text, transcribe_usage = await _resolve_text(capture, provider, audio_loader)
    if transcribe_usage is not None:
        usages.append(transcribe_usage)

    # Extraction (typed JSON) + its usage, then the embedding + its usage.
    extraction_result = await run_extraction(text, provider)
    usages.append(extraction_result.usage)
    expenses = await _detect_expenses(text, provider, usages, capture_id)
    embedding = await provider.embed(text)
    usages.append(embedding.usage)

    plan = build_enrichment_plan(user_id, capture_id, extraction_result.extraction)
    plan = with_expenses(
        plan,
        user_id,
        capture_id,
        expenses,
        default_currency=(capture.user_currency or FALLBACK_CURRENCY).upper(),
        spent_at=_spent_at(capture),
    )
    await store.persist_enrichment(user_id, capture_id, plan, embedding, usages)
    return UnderstandingResult(Outcome.PROCESSED)


async def _detect_expenses(
    text: str,
    provider: AIProvider,
    usages: list[Usage],
    capture_id: str,
) -> list[ExpenseItem]:
    """Best effort: the optional expense call never fails the capture."""
    try:
        result = await detect_expenses(text, provider)
    except Exception:  # noqa: BLE001 - auxiliary call; comprehension goes on
        logger.warning("expense detection failed for capture=%s", capture_id)
        return []
    if result.usage is not None:
        usages.append(result.usage)
    return result.expenses


def _spent_at(capture: CaptureRow) -> str:
    """An expense is dated when the capture happened (else when stored)."""
    when = capture.occurred_at or capture.created_at or datetime.now(UTC)
    if when.tzinfo is None:
        when = when.replace(tzinfo=UTC)
    # Millisecond precision, like JavaScript's toISOString() on the API side.
    stamp = when.astimezone(UTC).isoformat(timespec="milliseconds")
    return stamp.replace("+00:00", "Z")


async def _resolve_text(
    capture: CaptureRow,
    provider: AIProvider,
    audio_loader: AudioLoader | None,
) -> tuple[str, Usage | None]:
    """Return the text to comprehend, transcribing voice captures if needed."""
    if capture.body and capture.body.strip():
        return capture.body, None
    if audio_loader is None:
        raise ValueError(
            f"capture {capture.id} has no body and no audio_loader is configured "
            "(voice transcription is not wired in this deployment)"
        )
    audio_bytes, content_type = await audio_loader(capture)
    completion = await provider.transcribe(audio_bytes, content_type)
    return completion.text, completion.usage
