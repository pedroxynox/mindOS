"""Unit tests for the worker's pure job-handling logic (no BullMQ/Redis)."""

import pytest

from app.providers.fake_provider import FakeProvider
from app.understanding.pipeline import Outcome
from app.understanding.store import InMemoryGraphStore
from app.understanding.worker import handle_failed, handle_job

USER = "user-1"
CAP = "cap-1"


def _job_data() -> dict:
    return {
        "schema_version": 1,
        "capture_id": CAP,
        "user_id": USER,
        "enqueued_at": "2026-07-09T00:00:00Z",
    }


def _store() -> InMemoryGraphStore:
    store = InMemoryGraphStore()
    store.seed_capture(USER, CAP, body="Call Ana about the invoice.")
    return store


async def test_handle_job_runs_pipeline() -> None:
    store = _store()
    result = await handle_job(
        "understanding.process", _job_data(), provider=FakeProvider(), store=store
    )
    assert result.outcome is Outcome.PROCESSED
    assert (await store.load_capture(USER, CAP)).status == "processed"


async def test_handle_job_rejects_unknown_job_name() -> None:
    with pytest.raises(ValueError):
        await handle_job(
            "something.else", _job_data(), provider=FakeProvider(), store=_store()
        )


async def test_handle_job_rejects_unsupported_schema_version() -> None:
    data = _job_data()
    data["schema_version"] = 2
    with pytest.raises(ValueError):
        await handle_job(
            "understanding.process", data, provider=FakeProvider(), store=_store()
        )


async def test_handle_failed_marks_failed_only_on_final_attempt() -> None:
    store = _store()

    # Not the last attempt yet -> leave it for BullMQ to retry.
    did = await handle_failed(_job_data(), attempts_made=2, max_attempts=5, store=store)
    assert did is False
    assert (await store.load_capture(USER, CAP)).status == "raw"

    # Retries exhausted -> transition to failed (raw body untouched, P-COMP-5).
    did = await handle_failed(_job_data(), attempts_made=5, max_attempts=5, store=store)
    assert did is True
    assert (await store.load_capture(USER, CAP)).status == "failed"
