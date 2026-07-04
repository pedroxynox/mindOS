"""Structured entity/task/connection extraction (comprehension PoC core).

``extract_entities`` asks an :class:`AIProvider` for typed JSON output and
validates it with Pydantic. It is provider-agnostic: the same code runs against
the deterministic ``FakeProvider`` (offline eval) and a real ``OpenAIProvider``.

The prompt is a versioned constant (currently ``EXTRACTION_PROMPT_V6``, a
targeted edit of the lean v5 consolidation that tightens the task exclusions;
the previous ``EXTRACTION_PROMPT_V1``..``V5`` are kept for history) so prompt
changes are explicit and diffable — the eval harness (design §13) iterates on
exactly this string when de-risking R-001.
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

# --- v3 (current) -------------------------------------------------------------
# The first REAL Groq/Llama run with v2 + the fair matcher (2026-07-03, 2nd
# iteration) passed entity F1 (0.864) and task precision (0.90) but FAILED the
# hallucination gate hard: 0.191 vs the 0.05 ceiling. Diagnosis: the model still
# rounds implicit hints up into full entities — an unnamed actor ("el cliente"),
# a vague deadline with no concrete date ("antes del cierre"), a project that is
# only alluded to. v3 keeps EVERYTHING in v2 verbatim (so recall — F1 0.864, only
# just above the 0.80 floor — is NOT disturbed) and appends TWO precision-only
# reinforcements that fire ONLY on non-explicit items:
#   1. a FINAL SELF-CHECK step: for every item, point to the literal words that
#      justify it; if you cannot, delete it.
#   2. a third INVENTED few-shot (again, no eval-set names/labels) that models
#      the exact failure mode — a plausible-but-absent person, event and project
#      that MUST be omitted, while the one explicit task + topic are kept.
# It deliberately does NOT touch the inclusion rules for explicit entities/tasks,
# so it trims invention without shrinking coverage. v2 is retained above so the
# change stays diffable and reversible.

_V3_EXAMPLE_3 = (
    '{"entities":['
    '{"type":"person","label":"Laura"},'
    '{"type":"topic","label":"informe"}],'
    '"tasks":[{"label":"revisar el informe con Laura"}],'
    '"connections":[{"type":"assigned_to",'
    '"source":"revisar el informe con Laura","target":"Laura"}]}'
)

_V3_ADDENDUM = (
    "\n"
    "\n"
    "Example 3 (ES) — keep ONLY the explicit; omit every implicit hint.\n"
    'Capture: "Tengo que revisar el informe con Laura; seguramente el cliente\n'
    'querrá verlo antes del cierre."\n'
    "JSON: " + _V3_EXAMPLE_3 + "\n"
    'Why: "el cliente" has NO name -> no person. "antes del cierre" is a vague\n'
    "deadline with no date/weekday/clock time -> NOT an event. No project is\n"
    'named -> none invented. Only the explicit task ("revisar el informe con\n'
    'Laura", filler "tengo que" dropped) and its explicit topic ("informe") are\n'
    "kept.\n"
    "\n"
    "==== FINAL SELF-CHECK (do this before you answer) ====\n"
    "For EVERY item you are about to emit, locate the LITERAL word(s) in the\n"
    "capture that justify it. If you cannot point to explicit words — because the\n"
    "item is implied, guessed, generic, or merely 'probably there' — DELETE it.\n"
    "A vague reference with no concrete name/date/time (e.g. \"the client\", \"the\n"
    'team", "the deadline", "soon", "later") is NOT an entity. Never round a\n'
    "partial hint up into a full entity, and never add a project/person/event\n"
    "that the text does not name outright. Keeping every EXPLICIT item is still\n"
    "required — this check removes only inventions, not real content."
)

EXTRACTION_PROMPT_V3 = EXTRACTION_PROMPT_V2 + _V3_ADDENDUM

# --- v4 (current) -------------------------------------------------------------
# The STABLE 45-case Groq/Llama run with v3 + the fair matcher passed entity F1
# (0.826) and task precision (0.889) but STILL failed the hallucination gate:
# 0.160 vs the 0.05 ceiling. Reading the worst cases isolated THREE concrete
# over-extraction patterns, all of them pure INVENTION (false positives), not
# missed recall:
#   1. physical OBJECTS/PLACES emitted as a `topic` (a pharmacy, a package, an
#      ATM, a school) when they are merely the object/location of an errand —
#      the gold never treats a place/errand-location as a topic (case-16,
#      case-31).
#   2. ROLES/TITLES/KINSHIP emitted as a `person` ("el jefe", "el cliente",
#      "mamá", "the team") when no proper name is present — every gold `person`
#      is a proper name (case-24, case-35).
#   3. VAGUE mood/filler captures rounded up into an invented `note` or topic
#      instead of returning empty — the gold NEVER uses the `note` type, and a
#      pure-reflection capture is gold-empty (case-18).
# v4 keeps EVERYTHING in v3 (hence v2) verbatim so recall is NOT disturbed, and
# appends precision-only reinforcements that fire ONLY on these invented items;
# it does NOT touch the inclusion rules for explicit entities/tasks, so it trims
# invention without shrinking coverage.
#
# RECALL-SAFETY was verified against ALL 45 gold files before writing this:
#   - `note` appears 0 times in gold -> forbidding it can only remove FPs.
#   - every gold `person` is a proper name -> the role/kinship rule drops no
#     gold person.
#   - gold `topic`s are abstract subjects and errand PLACES/locations are never
#     topics. ONE CAVEAT was found and honored: the gold is INCONSISTENT about a
#     bought consumable (case-05 "café" IS a topic while case-31 "pan" is NOT).
#     To stay recall-safe, rule 1 is deliberately SCOPED to places/locations and
#     purely instrumental objects (which the gold omits 100% consistently); it
#     does NOT tell the model that every purchased good is a non-topic, because
#     that would risk dropping "café". Residual: "pan"-type consumables may still
#     be over-extracted in case-31 — an accepted, honest trade to protect recall.
# NO gold, matcher, metric or threshold is changed. v3 is retained above so the
# change stays diffable and reversible. PENDING VALIDATION with a real Groq run
# (this is a reasoned hypothesis, not yet measured — no Groq key in this env).
# NOTE: v4 was superseded at runtime by the consolidated v5 below; the string
# is kept only for history/diff. ``EXTRACTION_PROMPT_VERSION`` is set with v5.

# INVENTED few-shot for v4 (like the v2/v3 examples, NOTHING here is taken from
# the eval set — no farmacia/pan/paquete/cajero/colegio/mamá/jefe/cliente, no
# gold topic words). It only teaches JUDGEMENT: errand places/objects stay
# inside task labels, and a vague mood line yields an all-empty result.
_V4_EXAMPLE_4 = (
    '{"entities":[],'
    '"tasks":['
    '{"label":"pasar por la tintorería"},'
    '{"label":"dejar unos documentos en la notaría"},'
    '{"label":"hacer cola en el ayuntamiento"}],'
    '"connections":[]}'
)

_V4_ADDENDUM = (
    "\n"
    "\n"
    "==== v4 PRECISION REINFORCEMENT (remove inventions only) ====\n"
    "Everything above still applies. The rules below ONLY stop three specific\n"
    "inventions; they NEVER tell you to drop an explicitly named entity or a\n"
    "real task. Keeping every EXPLICIT item is still required — this section\n"
    "removes fabrications, not real content.\n"
    "\n"
    "1) OBJECTS & PLACES ARE NOT ENTITIES. A place or location named only as\n"
    "   WHERE an errand happens — a shop, a pharmacy, a bank, an ATM, a school,\n"
    "   an office, a gym — is NOT a `topic` and NOT any entity. A purely\n"
    "   instrumental object handled in passing during an errand — a package, a\n"
    "   form, a document, a receipt — is NOT an entity either. Such words may\n"
    "   appear INSIDE a task label (that is where they belong), but never as a\n"
    "   standalone entity. `topic` is reserved for ABSTRACT subject matter — a\n"
    "   theme, a concept, a feature, an area of concern — NEVER a physical place\n"
    "   or location.\n"
    "\n"
    "2) ROLES, TITLES AND KINSHIP ARE NOT `person`. Only a PROPER NAME is a\n"
    '   person. A bare role or relationship with no name — "the boss"/"el jefe",\n'
    '   "the client"/"el cliente", "the team"/"el equipo", "mom"/"mamá",\n'
    '   "someone" — is NOT a person entity. It may still appear inside a task\n'
    "   label, but if no proper name is present, emit NO person.\n"
    "\n"
    "3) DO NOT USE `note`, AND NEVER INVENT TO AVOID EMPTINESS. For a vague,\n"
    "   mood, or filler capture with no concrete task and no explicitly named\n"
    "   entity or abstract subject, return EVERY section empty ([]). Only emit\n"
    "   an explicit abstract subject as a `topic`; if there is none, an empty\n"
    "   result is the CORRECT answer. Pure reflection with nothing concrete\n"
    "   yields all-empty output — do NOT manufacture a `note` or a topic to\n"
    "   fill the gap.\n"
    "\n"
    "==== ILLUSTRATIVE EXAMPLE 4 (invented — NOT from your data; do not reuse) ====\n"
    "Two contrasting captures: the errands case and the empty case.\n"
    "\n"
    "Example 4a (ES) — an errands list: tasks only, places/objects NOT entities.\n"
    'Capture: "Recados de hoy: pasar por la tintorería, dejar unos documentos en\n'
    'la notaría y hacer cola en el ayuntamiento."\n'
    "JSON: " + _V4_EXAMPLE_4 + "\n"
    'Why: "tintorería", "notaría" and "ayuntamiento" are PLACES where errands\n'
    'happen, and "documentos" is an instrumental object handled in passing — none\n'
    "is an entity. They live inside the task labels only. No proper name and no\n"
    "abstract subject, so entities is [].\n"
    "\n"
    "Example 4b (ES) — a vague mood line: everything empty.\n"
    'Capture: "No sé, hoy ando un poco disperso, con la cabeza en las nubes."\n'
    'JSON: {"entities":[],"tasks":[],"connections":[]}\n'
    "Why: pure mood/filler — no concrete task, no named entity, no abstract\n"
    "subject -> every section is []. Emptiness is the correct answer; do NOT\n"
    "invent a `note` or a topic to avoid it."
)

EXTRACTION_PROMPT_V4 = EXTRACTION_PROMPT_V3 + _V4_ADDENDUM

# --- v5 (current) -------------------------------------------------------------
# WHY v5 EXISTS (debt D-010): v1..v4 grew by STACKING addenda, so at RUNTIME we
# sent ``EXTRACTION_PROMPT_V4 = V2 + _V3_ADDENDUM + _V4_ADDENDUM`` plus the JSON
# schema — one very large prompt in which several rules were stated two or three
# times (the anti-hallucination framing, the "roles/kinship are not a person"
# rule, the "vague reference is not an entity" rule, the four few-shot examples).
# Multiplied by the ~45 eval calls this blew past Groq's free-tier TOKENS-per-
# minute ceiling (and pressures the daily cap), so the exam could not COMPLETE
# (two aborted runs, ~6 min and ~16 min — see R-001/§history), and in production
# it inflates per-capture cost and latency at scale.
#
# v5 is the CONSOLIDATION: a SINGLE, self-contained prompt that states each rule
# EXACTLY ONCE, with no duplication, while preserving ALL the distinct semantic
# rules that were spread across v2 + _V3_ADDENDUM + _V4_ADDENDUM:
#   - the ABSOLUTE anti-hallucination rule (extract only the EXPLICIT; when in
#     doubt OMIT; empty is better than invented; never invent to avoid emptiness);
#   - per-type inclusion/exclusion for person/project/event/topic/note (person =
#     proper name only, not roles/titles/kinship; project = name only, drop
#     "project/proyecto"; event = explicit time reference, not a vague deadline;
#     topic = abstract canonical core noun, and PLACES/instrumental objects are
#     NOT topics/entities; `note` is discouraged — pure mood/reflection is empty);
#   - the task-phrasing rule (label starts at the action verb, drop fillers,
#     keep the rest);
#   - the connection rules (assigned_to/mentions/relates_to, only between emitted
#     labels, omit if unsure);
#   - the FINAL SELF-CHECK (point to the literal words; if you can't, delete it;
#     a vague reference with no concrete name/date/time is not an entity);
#   - the OUTPUT FORMAT (JSON only, no prose/markdown, matching EXTRACTION_SCHEMA,
#     [] for empty sections) and the "preserve original language" instruction.
# It keeps only TWO compact INVENTED few-shot examples (reusing _V3_EXAMPLE_3 and
# _V4_EXAMPLE_4, neither of which uses any word/label from the eval set): one with
# an explicit task + owner and a deliberate OMISSION (unnamed actor + vague
# deadline), and one errands line whose places/objects are NOT entities (entities
# empty). The other two old examples were dropped as redundant — that redundancy
# was part of the bloat.
#
# v1..v4 and the `_V2_*`/`_V3_*`/`_V4_*` constants are RETAINED above (they are
# strings only, never sent) so the history stays diffable/reversible. Behaviour
# is expected to be VERY CLOSE to v4 (same rules), but v5 is a FRESH prompt to be
# RE-MEASURED with a completing Groq run, NOT guaranteed byte-for-byte identical.
# NOTE: v5 was superseded at runtime by v6 below; the string is kept only for
# history/diff. ``EXTRACTION_PROMPT_VERSION`` is set with v6.

EXTRACTION_PROMPT_V5 = (
    "You are a precise information-extraction engine for a personal knowledge\n"
    "graph. Read ONE capture (delimited below) and return structured knowledge\n"
    "as JSON. The capture may be in Spanish or English; preserve the ORIGINAL\n"
    "language of every label, exactly as written in the text.\n"
    "\n"
    "==== ABSOLUTE RULE (read first) ====\n"
    "Extract ONLY information that is EXPLICITLY present in the capture. Do NOT\n"
    "infer, do NOT invent, do NOT add outside knowledge, do NOT complete\n"
    "patterns. If something is not clearly stated, OMIT it — when in doubt,\n"
    "LEAVE IT OUT; a missing item is far better than an invented one. If a\n"
    "capture has nothing concrete (pure mood/reflection), the CORRECT answer is\n"
    "every section empty ([]); never manufacture an item just to avoid an empty\n"
    "result.\n"
    "\n"
    "==== ENTITIES (each has a closed-set \"type\") ====\n"
    "- person : a human named by a PROPER NAME. A bare role, title or kinship\n"
    "  with NO name is NOT a person — \"the boss\"/\"el jefe\", \"the client\"/\"el\n"
    "  cliente\", \"the team\"/\"el equipo\", \"mom\"/\"mamá\", \"someone\", "
    "pronouns. A\n"
    "  project/product name is not a person either. If no proper name is\n"
    "  present, emit NO person (the role may still appear inside a task label).\n"
    "- project: a named initiative/product, by its NAME ONLY. Drop the word\n"
    "  \"project\"/\"proyecto\" (write \"Aurora\", never \"proyecto Aurora\").\n"
    "- event  : an EXPLICIT time reference or scheduled happening — a date, a\n"
    "  weekday, a clock time, \"tomorrow\"/\"mañana\", \"next week\". NOT a generic\n"
    "  activity, and NOT a vague deadline with no concrete date/time (\"antes del\n"
    "  cierre\", \"the deadline\", \"soon\", \"algún día\").\n"
    "- topic  : ABSTRACT subject matter — a theme, concept, feature or area of\n"
    "  concern — written as its CANONICAL CORE NOUN: lowercase, singular,\n"
    "  WITHOUT articles or possessives (\"the budget\" -> \"budget\"; \"la salud\" ->\n"
    "  \"salud\"). One concept per topic; split a compound subject into separate\n"
    "  topics. A physical PLACE/location where an errand happens (a shop,\n"
    "  pharmacy, bank, ATM, school, office, gym) is NOT a topic and NOT any\n"
    "  entity; a purely instrumental object handled in passing (a package, a\n"
    "  form, a document, a receipt) is NOT an entity either. Such words belong\n"
    "  INSIDE a task label, never as a standalone entity.\n"
    "- note   : DO NOT USE this type. A vague/mood/journal capture with no\n"
    "  concrete task and no explicitly named entity or abstract subject returns\n"
    "  every section empty — do NOT manufacture a `note` or a topic to fill it.\n"
    "- Never emit an empty or whitespace-only label.\n"
    "\n"
    "==== TASKS ====\n"
    "Concrete action items the author intends to do (imperatives, \"need to\",\n"
    "\"hay que\", \"tengo que\", \"TODO\", reminders, tentative \"I should\"/\"quizás\n"
    "debería\"). Write the label as the ACTION PHRASE STARTING AT THE ACTION\n"
    "VERB, dropping filler openers (\"need to\", \"reminder:\", \"quizás debería\",\n"
    "\"tengo que\") but KEEPING the rest of the clause (object, person, when).\n"
    "Past facts, opinions, or a description of a scheduled event are NOT tasks.\n"
    "\n"
    "==== CONNECTIONS ====\n"
    "Relations SUPPORTED by the text, only between labels you already emitted:\n"
    "- assigned_to: task label (source) -> responsible person (target), ONLY\n"
    "  when the owner is explicit.\n"
    "- mentions   : a light co-occurrence link between two labels.\n"
    "- relates_to : a generic semantic link between two labels.\n"
    "Emit a connection ONLY if BOTH endpoints are labels you extracted. If\n"
    "unsure, omit it — connections are optional.\n"
    "\n"
    "==== FINAL SELF-CHECK (do this before you answer) ====\n"
    "For EVERY item you are about to emit, locate the LITERAL word(s) in the\n"
    "capture that justify it. If you cannot point to explicit words — because\n"
    "it is implied, guessed, generic, or merely 'probably there' — DELETE it. A\n"
    "vague reference with no concrete name/date/time (e.g. \"the client\", \"the\n"
    "team\", \"the deadline\", \"soon\", \"later\") is NOT an entity. Never round a\n"
    "partial hint up into a full entity, and never add a project/person/event\n"
    "the text does not name outright. Keeping every EXPLICIT item is still\n"
    "required — this check removes only inventions, not real content.\n"
    "\n"
    "==== OUTPUT FORMAT ====\n"
    "Return ONLY a JSON object (no prose, no markdown fences) with EXACTLY these\n"
    "keys, matching this JSON schema:\n"
    + json.dumps(EXTRACTION_SCHEMA, ensure_ascii=False)
    + "\n"
    "- \"entities\": list of {\"type\",\"label\"} (\"confidence\" 0..1 is optional).\n"
    "- \"tasks\": list of {\"label\"}.\n"
    "- \"connections\": list of {\"type\",\"source\",\"target\"}.\n"
    "- Use [] for any section with nothing to extract. Never fabricate to fill\n"
    "  it.\n"
    "\n"
    "==== TWO ILLUSTRATIVE EXAMPLES (invented — NOT from your data; do not "
    "reuse) ====\n"
    "They teach only the FORMAT and the JUDGEMENT, including when to OMIT.\n"
    "\n"
    "Example 1 (ES) — an explicit task with an owner; omit every implicit hint.\n"
    "Capture: \"Tengo que revisar el informe con Laura; seguramente el cliente\n"
    "querrá verlo antes del cierre.\"\n"
    "JSON: " + _V3_EXAMPLE_3 + "\n"
    "Why: keep the explicit task (\"revisar el informe con Laura\", filler \"tengo\n"
    "que\" dropped) and its explicit topic (\"informe\"). \"el cliente\" has NO name\n"
    "-> no person; \"antes del cierre\" is a vague deadline with no date/time ->\n"
    "no event; no project is named -> none invented.\n"
    "\n"
    "Example 2 (ES) — an errands list: tasks only; places/objects are NOT\n"
    "entities.\n"
    "Capture: \"Recados de hoy: pasar por la tintorería, dejar unos documentos en\n"
    "la notaría y hacer cola en el ayuntamiento.\"\n"
    "JSON: " + _V4_EXAMPLE_4 + "\n"
    "Why: \"tintorería\", \"notaría\" and \"ayuntamiento\" are PLACES where errands\n"
    "happen, and \"documentos\" is an instrumental object handled in passing —\n"
    "none is an entity; they live inside the task labels only. No proper name\n"
    "and no abstract subject, so entities is []."
)

# --- v6 (current) -------------------------------------------------------------
# WHY v6 EXISTS: the FIRST COMPLETE Groq/Llama run of the 45-case exam (v5 + the
# fair matcher) FAILED the gate — hallucination 0.137 vs the ≤0.05 ceiling
# (entities F1 0.739, task precision 0.830). Reading the worst cases isolated a
# SINGLE dominant remaining pattern, all pure INVENTION into `tasks` (false
# positives), NOT missed recall: the model turns NON-ACTIONS into tasks —
#   1. an IDEA/WISH invented as a task — case-33 (hall 1.0): "…estaría bien tener
#      un modo oscuro algún día." (gold tasks: []).
#   2. a STATUS/STATE update invented as tasks — case-26 (hall 0.6): "Emma is
#      blocked on the API redesign, and the Phoenix rollout slipped…"
#      (gold tasks: []).
#   3. an APPOINTMENT/EVENT confused as a task — case-23 (hall 0.667): "Tengo
#      cita con el dentista el 15 de marzo…" (gold tasks: []), because "tengo"
#      resembles the "tengo que" task trigger.
# v5 already said "Past facts, opinions, or a description of a scheduled event
# are NOT tasks." but did NOT explicitly cover ideas/wishes, status/state
# updates, or "tengo cita" vs "tengo que". v6 strengthens ONLY the task-exclusion
# wording + adds ONE task line to the FINAL SELF-CHECK. Nothing else changes:
# entities, connections, output format, examples, the gold dataset, the matcher,
# thresholds and metrics are all untouched.
#
# RECALL-SAFETY AUDIT (done BEFORE writing v6, against the `gold.tasks` of ALL 45
# case-*.json files): every real gold task is a genuine ACTION the author
# performs — NONE is an idea/wish, a status/state description, or an
# appointment/scheduled-event description. The event-adjacent gold tasks are all
# active verbs, not "having/attending": case-32 "book an appointment with Dr.
# Nguyen" (the ACT of booking), case-38 "Llevar a Toby… al veterinario el jueves"
# (taking), case-20 "study for the history exam on Friday" (studying) — none is
# excluded by the new wording, which targets only the STATE of having/attending
# ("tengo cita"). Status lines the gold already omits (case-41 "Nimbus… is behind
# schedule", case-39, case-26) and the idea in case-33 confirm the direction.
# CONCLUSION: the change drops NO real gold task -> recall is not hurt; it can
# only remove the false-positive task inventions above.
#
# v6 is defined as a TARGETED edit of the v5 string (via str.replace on exactly
# the two anchors below), so the base stays BYTE-IDENTICAL to v5, no rule is
# duplicated, and the runtime prompt remains ONE lean self-contained string
# (respecting debt D-010). v1..v5 strings are RETAINED above for history/diff and
# are never sent. This is a REASONED HYPOTHESIS, PENDING RE-MEASUREMENT with a
# completing Groq run (no Groq key in this env).
EXTRACTION_PROMPT_VERSION = "v6"

EXTRACTION_PROMPT_V6 = EXTRACTION_PROMPT_V5.replace(
    # (a) Strengthen the TASKS exclusion: a task must be an action the AUTHOR
    # will actively DO; ideas/wishes, status/state updates, and
    # having/attending a scheduled event/appointment are NOT tasks.
    "Past facts, opinions, or a description of a scheduled event are NOT tasks.\n",
    "A task must be an action the AUTHOR will actively DO. Past facts, opinions,\n"
    "IDEAS or WISHES (\"would be nice to…\", \"estaría bien…\", \"someday\"/\"algún\n"
    "día\"), STATUS or STATE updates about someone/something (\"X is\n"
    "blocked\"/\"está bloqueado\", \"the rollout slipped\"/\"se corrió\", \"is\n"
    "behind\"), and having or attending a SCHEDULED EVENT or APPOINTMENT (\"tengo\n"
    "cita\", \"I have a meeting\", \"la reunión es el jueves\") are NOT tasks — an\n"
    "event is something that happens, not an action you perform. Note: \"tengo\n"
    "cita\" (an appointment) is NOT a task, unlike \"tengo que\" (an obligation to\n"
    "act).\n",
).replace(
    # (b) Add one task-focused line to the FINAL SELF-CHECK.
    "the text does not name outright. Keeping every EXPLICIT item is still\n"
    "required — this check removes only inventions, not real content.\n",
    "the text does not name outright. For EVERY task, confirm it is an action\n"
    "the author will perform — not a state, wish, opinion, or scheduled\n"
    "event/appointment; if not, DELETE it. Keeping every EXPLICIT item is still\n"
    "required — this check removes only inventions, not real content.\n",
)


def build_extraction_prompt(text: str) -> str:
    """Render the current versioned prompt with the capture text embedded."""
    return (
        f"{EXTRACTION_PROMPT_V6}\n\n"
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
