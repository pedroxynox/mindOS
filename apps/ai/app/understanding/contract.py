"""Understanding-handoff contract (mirror of F1's queue port).

This is the Python mirror of ``apps/api/src/capture/understanding.queue.port.ts``
(the ``UnderstandingJobData`` interface F1 produces to BullMQ). The consumer must
accept EXACTLY the message the producer already ships in production, so this is a
deliberate, versioned duplication of a cross-service contract — not shared code.

``schema_version`` lets the message evolve without breaking the consumer: an
unknown value is rejected explicitly (design §14) rather than guessed.
"""

from pydantic import BaseModel, Field

# Shared with F1: same queue name and same job name (understanding.queue.ts).
UNDERSTANDING_QUEUE = "understanding"
UNDERSTANDING_JOB = "understanding.process"

# The only schema version F2 understands today. Bump (and branch) when F1 emits
# a new shape; never silently accept an unknown version.
SUPPORTED_SCHEMA_VERSION = 1


class UnderstandingJobData(BaseModel):
    """Payload of an ``understanding.process`` job (design §6).

    Validated at the boundary (Engineering Standards #07): a malformed job is a
    hard error, never a silent guess.
    """

    schema_version: int = Field(..., ge=1)
    capture_id: str = Field(..., min_length=1)
    user_id: str = Field(..., min_length=1)
    # ISO-8601 timestamp set by the producer; carried through for observability.
    enqueued_at: str = Field(..., min_length=1)
