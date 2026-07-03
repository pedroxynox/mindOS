"""Structured entity/task/connection extraction (comprehension PoC core).

``extract_entities`` asks an :class:`AIProvider` for typed JSON output and
validates it with Pydantic. It is provider-agnostic: the same code runs against
the deterministic ``FakeProvider`` (offline eval) and a real ``OpenAIProvider``.

The prompt is a versioned constant (currently ``EXTRACTION_PROMPT_V2``; the
previous ``EXTRACTION_PROMPT_V1`` is kept for history) so prompt changes are
explicit and diffable — the eval harness (design §13) iterates on exactly this
string when de-risking R-001.
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

# --- v1 (superseded, kept for history/diff) -----------------------------------
# The first prompt was terse: it named the three outputs and a couple of soft
# rules ("do not invent", "prefer precision"). The first REAL run (Groq/Llama,
# 2026-07-03) failed the gate hard — F1 entities 0.524, task precision 0.500,
# hallucination 0.488 — i.e. the model invented a lot and worded tasks freely.
# v2 (below) is the response: hard anti-hallucination framing, explicit
# inclusion/exclusion criteria per type, a stated label convention that matches
# how the gold set is written, and two INVENTED few-shot examples (never from
# the eval set) that teach the format AND when to OMIT. v1 is retained here so
# the change is diffable and reversible.
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

# --- v2 (current) -------------------------------------------------------------
# NOTE ON THE FEW-SHOT EXAMPLES: they are fully INVENTED for this prompt. None of
# their texts or labels are taken from the evaluation set (no Marcos/Ana/Aurora/
# Titan/Delta/… , no gold topic words like "budget"/"invoice"/"reunión"). Using
# the eval cases as examples would be dataset contamination and would make the
# score meaningless. The examples only teach FORMAT and JUDGEMENT (including an
# explicit OMISSION), not answers.
EXTRACTION_PROMPT_VERSION = "v2"

_V2_EXAMPLE_1 = (
    '{"entities":['
    '{"type":"person","label":"Elena"},'
    '{"type":"topic","label":"roadmap"}],'
    '"tasks":[{"label":"Send the Q4 roadmap to Elena"}],'
    '"connections":[{"type":"assigned_to",'
    '"source":"Send the Q4 roadmap to Elena","target":"Elena"}]}'
)
_V2_EXAMPLE_2 = (
    '{"entities":['
    '{"type":"person","label":"Elena"},'
    '{"type":"event","label":"jueves"},'
    '{"type":"topic","label":"logística"},'
    '{"type":"project","label":"Neptuno"}],'
    '"tasks":[],'
    '"connections":[]}'
)

EXTRACTION_PROMPT_V2 = (
    "You are a precise information-extraction engine for a personal knowledge\n"
    "graph. Read ONE capture (delimited below) and return structured knowledge\n"
    "as JSON. The capture may be in Spanish or English; preserve the ORIGINAL\n"
    "language of every label, exactly as written in the text.\n"
    "\n"
    "==== ABSOLUTE RULE (read first) ====\n"
    "Extract ONLY information that is EXPLICITLY present in the capture. Do NOT\n"
    "infer, do NOT invent, do NOT add outside knowledge, do NOT complete\n"
    "patterns. If something is not clearly stated, OMIT it. When in doubt, LEAVE\n"
    "IT OUT — a missing item is far better than an invented one.\n"
    "\n"
    "==== WHAT TO EXTRACT ====\n"
    "1) entities — things NAMED or clearly referred to. Each has a closed-set\n"
    "   \"type\":\n"
    "   - person : a named human (proper name). NOT job titles, NOT \"someone\",\n"
    "     NOT pronouns, NOT a project/product name.\n"
    "   - project: a named initiative/product, by its NAME ONLY. Drop the word\n"
    '     "project"/"proyecto" (write "Aurora", never "project Aurora").\n'
    "   - event  : an explicit time reference or scheduled happening — a date, a\n"
    '     weekday, a clock time, "tomorrow"/"mañana", "next week". NOT a generic\n'
    "     activity.\n"
    "   - topic  : the subject matter, as its CANONICAL CORE NOUN — lowercase,\n"
    '     singular, WITHOUT articles or possessives ("the budget" -> "budget";\n'
    '     "la salud" -> "salud"). One concept per topic; split a compound\n'
    "     subject into separate topics.\n"
    "   - note   : a reflective/journal thought that is none of the above.\n"
    "2) tasks — concrete action items the author intends to do (imperatives,\n"
    '   "need to", "hay que", "tengo que", "TODO", reminders, tentative\n'
    '   "I should"/"quizás debería"). Write the label as the ACTION PHRASE\n'
    '   STARTING AT THE ACTION VERB, dropping filler openers ("need to",\n'
    '   "reminder:", "quizás debería", "tengo que"), but KEEPING the rest of the\n'
    "   clause (object, person, when). Past facts, opinions or descriptions of a\n"
    "   scheduled event are NOT tasks.\n"
    "3) connections — relations SUPPORTED by the text, between labels you already\n"
    "   emitted:\n"
    "   - assigned_to: task label (source) -> responsible person (target). Only\n"
    "     when the owner is explicit.\n"
    "   - mentions   : a light co-occurrence link between two labels.\n"
    "   - relates_to : a generic semantic link between two labels.\n"
    "   Emit a connection ONLY if BOTH endpoints are labels you extracted. If\n"
    "   unsure, omit it — connections are optional.\n"
    "\n"
    "==== JUDGEMENT (inclusion / exclusion) ====\n"
    '   - "someone from finance" -> NO person (no name given).\n'
    '   - "call me later" with no addressee -> a task, but NO person entity.\n'
    "   - a greeting, filler, or a past-tense recollection -> usually nothing.\n"
    "   - never emit an empty or whitespace-only label.\n"
    "\n"
    "==== OUTPUT FORMAT ====\n"
    "Return ONLY a JSON object (no prose, no markdown fences) with EXACTLY these\n"
    "keys, matching this JSON schema:\n"
    + json.dumps(EXTRACTION_SCHEMA, ensure_ascii=False)
    + "\n"
    '- "entities": list of {"type","label"} ("confidence" 0..1 is optional).\n'
    '- "tasks": list of {"label"}.\n'
    '- "connections": list of {"type","source","target"}.\n'
    "- Use [] for any section with nothing to extract. Never fabricate to fill\n"
    "  it.\n"
    "\n"
    "==== ILLUSTRATIVE EXAMPLES (invented — NOT from your data; do not reuse) ====\n"
    "These show only the FORMAT and the JUDGEMENT, including when to OMIT.\n"
    "\n"
    "Example 1 (EN) — one task with an explicit owner, and an OMISSION.\n"
    'Capture: "Send the Q4 roadmap to Elena. Someone mentioned a new client but\n'
    'no name was given yet."\n'
    "JSON: " + _V2_EXAMPLE_1 + "\n"
    'Why: the "new client" is OMITTED — no explicit name, so no person is\n'
    "invented. The filler \"Send\" IS the action verb, so the task keeps it.\n"
    "\n"
    "Example 2 (ES) — a scheduled event with NO action item, and an omission.\n"
    'Capture: "Charla con Elena el jueves sobre la logística del proyecto\n'
    'Neptuno; vendrá alguien de soporte."\n'
    "JSON: " + _V2_EXAMPLE_2 + "\n"
    "Why: a scheduled talk is an event, not an action item, so tasks is []. The\n"
    '"proyecto" prefix is dropped ("Neptuno"). The unnamed "alguien de soporte"\n'
    "is OMITTED."
)


def build_extraction_prompt(text: str) -> str:
    """Render the current versioned prompt with the capture text embedded."""
    return (
        f"{EXTRACTION_PROMPT_V2}\n\n"
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
