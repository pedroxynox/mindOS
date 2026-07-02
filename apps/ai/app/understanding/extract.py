"""Structured entity/task/connection extraction (comprehension PoC core).

``extract_entities`` asks an :class:`AIProvider` for typed JSON output and
validates it with Pydantic. It is provider-agnostic: the same code runs against
the deterministic ``FakeProvider`` (offline eval) and a real ``OpenAIProvider``.

The prompt is a versioned constant (``EXTRACTION_PROMPT_V1``) so prompt changes
are explicit and diffable — the eval harness (design §13) iterates on exactly
this string when de-risking R-001.
"""

import json
import time
from dataclasses import dataclass
from typing import Literal

from pydantic import BaseModel, Field, ValidationError

from app.providers.base import AIProvider, Usage

# --- Taxonomy (design §4.1, v1) ------------------------------------------------
# ``task`` is a first-class node type but is carried in its own field so we can
# measure task precision separately (design §13.1). Non-task entities live in
# ``entities``. ``derived_from`` is provenance added at write time, so it is not
# an *extracted* connection type here.
EntityType = Literal["person", "project", "event", "topic", "note"]
ConnectionType = Literal["mentions", "assigned_to", "relates_to"]


class Entity(BaseModel):
    """A non-task entity mentioned in the capture."""

    type: EntityType
    label: str = Field(min_length=1)
    confidence: float = Field(default=1.0, ge=0.0, le=1.0)


class TaskItem(BaseModel):
    """An action item / pending task expressed in the capture."""

    label: str = Field(min_length=1)
    confidence: float = Field(default=1.0, ge=0.0, le=1.0)


class Connection(BaseModel):
    """A proposed semantic edge between two labels (by label, resolved later)."""

    type: ConnectionType
    source: str = Field(min_length=1)
    target: str = Field(min_length=1)
    confidence: float = Field(default=1.0, ge=0.0, le=1.0)


class Extraction(BaseModel):
    """Validated structured output of the comprehension step."""

    entities: list[Entity] = Field(default_factory=list)
    tasks: list[TaskItem] = Field(default_factory=list)
    connections: list[Connection] = Field(default_factory=list)

    def typed_entities(self) -> list[tuple[str, str]]:
        """Flatten to ``(type, label)`` pairs, tasks folded in as ``task``.

        Used by entity-level precision/recall/F1 which score across *all* node
        types (design §13.1).
        """
        pairs: list[tuple[str, str]] = [("task", t.label) for t in self.tasks]
        pairs += [(e.type, e.label) for e in self.entities]
        return pairs


@dataclass(frozen=True)
class ExtractionResult:
    """Extraction plus the observability the eval harness needs (cost, latency)."""

    extraction: Extraction
    usage: Usage
    latency_ms: float


# --- Prompt (versioned) --------------------------------------------------------
# The capture text is delimited by explicit markers so a provider can locate it
# unambiguously. Keep the markers stable: the FakeProvider relies on them too.
CAPTURE_OPEN = "<<<CAPTURE"
CAPTURE_CLOSE = "CAPTURE>>>"

EXTRACTION_SCHEMA: dict = {
    "type": "object",
    "properties": {
        "entities": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "type": {
                        "type": "string",
                        "enum": ["person", "project", "event", "topic", "note"],
                    },
                    "label": {"type": "string"},
                    "confidence": {"type": "number"},
                },
                "required": ["type", "label"],
            },
        },
        "tasks": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "label": {"type": "string"},
                    "confidence": {"type": "number"},
                },
                "required": ["label"],
            },
        },
        "connections": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "type": {
                        "type": "string",
                        "enum": ["mentions", "assigned_to", "relates_to"],
                    },
                    "source": {"type": "string"},
                    "target": {"type": "string"},
                    "confidence": {"type": "number"},
                },
                "required": ["type", "source", "target"],
            },
        },
    },
    "required": ["entities", "tasks", "connections"],
}

EXTRACTION_PROMPT_VERSION = "v1"
EXTRACTION_PROMPT_V1 = (
    "You are an information-extraction engine for a personal knowledge graph.\n"
    "Read the capture and extract structured knowledge. The capture may be in\n"
    "Spanish or English; preserve the original language of each label.\n"
    "\n"
    "Extract three things:\n"
    "1. entities — people, projects, events, topics, or reflective notes. Use\n"
    "   type one of: person, project, event, topic, note.\n"
    "2. tasks — concrete action items / pending things to do (imperatives,\n"
    '   "need to", "hay que", "tengo que", TODO, ...). Only real actions.\n'
    "3. connections — plausible relations between labels: mentions, assigned_to\n"
    "   (task -> person responsible), relates_to (generic semantic link).\n"
    "\n"
    "Rules:\n"
    "- Do not invent entities that are not supported by the text.\n"
    "- Prefer precision over recall for tasks (avoid noise).\n"
    "- Return ONLY a JSON object matching this schema, no prose:\n"
    + json.dumps(EXTRACTION_SCHEMA, ensure_ascii=False)
)


def build_extraction_prompt(text: str) -> str:
    """Render the versioned prompt with the capture text embedded."""
    return (
        f"{EXTRACTION_PROMPT_V1}\n\n"
        f"Capture:\n{CAPTURE_OPEN}\n{text}\n{CAPTURE_CLOSE}\n"
    )


def parse_extraction(raw_json: str) -> Extraction:
    """Parse and validate a provider's JSON output into an :class:`Extraction`.

    Raises ``ValueError`` on malformed JSON or schema violations (design §14:
    invalid LLM output is treated as a failed attempt, never silently guessed).
    """
    try:
        data = json.loads(raw_json)
    except json.JSONDecodeError as exc:
        raise ValueError(f"provider returned malformed JSON: {exc}") from exc
    try:
        return Extraction.model_validate(data)
    except ValidationError as exc:
        raise ValueError(f"provider output failed schema validation: {exc}") from exc


async def run_extraction(text: str, provider: AIProvider) -> ExtractionResult:
    """Extract with full observability (usage + latency) for the eval harness."""
    prompt = build_extraction_prompt(text)
    started = time.perf_counter()
    completion = await provider.complete(prompt, schema=EXTRACTION_SCHEMA)
    latency_ms = (time.perf_counter() - started) * 1000.0
    extraction = parse_extraction(completion.text)
    return ExtractionResult(
        extraction=extraction, usage=completion.usage, latency_ms=latency_ms
    )


async def extract_entities(text: str, provider: AIProvider) -> Extraction:
    """Extract structured entities/tasks/connections from a capture text.

    Matches the design skeleton signature (§13.3). For cost/latency-aware
    callers (the eval runner) use :func:`run_extraction`.
    """
    result = await run_extraction(text, provider)
    return result.extraction
