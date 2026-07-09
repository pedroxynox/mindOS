"""Unit tests for the understanding-job contract (mirror of F1)."""

import pytest
from pydantic import ValidationError

from app.understanding.contract import (
    SUPPORTED_SCHEMA_VERSION,
    UNDERSTANDING_JOB,
    UNDERSTANDING_QUEUE,
    UnderstandingJobData,
)


def _valid() -> dict:
    return {
        "schema_version": 1,
        "capture_id": "cap-1",
        "user_id": "user-1",
        "enqueued_at": "2026-07-09T00:00:00Z",
    }


def test_queue_and_job_names_match_f1() -> None:
    # These MUST equal the producer's constants (understanding.queue.ts).
    assert UNDERSTANDING_QUEUE == "understanding"
    assert UNDERSTANDING_JOB == "understanding.process"
    assert SUPPORTED_SCHEMA_VERSION == 1


def test_valid_job_parses() -> None:
    data = UnderstandingJobData(**_valid())
    assert data.capture_id == "cap-1"
    assert data.user_id == "user-1"


@pytest.mark.parametrize("missing", ["capture_id", "user_id", "enqueued_at"])
def test_missing_required_field_rejected(missing: str) -> None:
    payload = _valid()
    del payload[missing]
    with pytest.raises(ValidationError):
        UnderstandingJobData(**payload)


@pytest.mark.parametrize("blank", ["capture_id", "user_id"])
def test_blank_identifiers_rejected(blank: str) -> None:
    payload = _valid()
    payload[blank] = ""
    with pytest.raises(ValidationError):
        UnderstandingJobData(**payload)


def test_schema_version_must_be_positive() -> None:
    payload = _valid()
    payload["schema_version"] = 0
    with pytest.raises(ValidationError):
        UnderstandingJobData(**payload)
