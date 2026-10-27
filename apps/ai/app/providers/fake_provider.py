"""Deterministic, offline ``FakeProvider`` (no network, no cost).

Backs the unit/property tests and the offline evaluation harness (design §7,
§13). It produces a *reasonable* structured extraction from a capture using
simple, transparent heuristics — enough for the metrics to yield a meaningful
number, while being fully reproducible (same input -> same output, cost = 0).

It implements the same ``AIProvider`` contract as the real vendors. For
``complete`` it recovers the capture text from the prompt (delimited by the
``CAPTURE`` markers) and applies the heuristics below.
"""

import hashlib
import json
import re
import unicodedata

from app.providers.base import AIProvider, Completion, Embedding, Usage
from app.understanding.text_utils import normalize_label

_PROVIDER_NAME = "fake"
_COMPLETE_MODEL = "fake-extract-1"
_EMBED_MODEL = "fake-embed-1"
_EMBED_DIM = 16

# --- Heuristic lexicons (normalized: lowercase + accent-folded) ---------------
# Imperative verbs / action keywords that mark a task, EN + ES.
_TASK_VERBS = {
    # English
    "call", "send", "buy", "finish", "review", "schedule", "email", "write",
    "fix", "prepare", "book", "remind", "update", "check", "pay", "read",
    "plan", "organize", "ship", "deploy", "test", "meet", "contact", "confirm",
    # Spanish (accent-folded)
    "llamar", "enviar", "comprar", "terminar", "revisar", "agendar", "escribir",
    "arreglar", "preparar", "reservar", "recordar", "hacer", "mandar", "pagar",
    "leer", "planear", "organizar", "actualizar", "contactar", "confirmar",
    "comprarle", "llama", "compra", "manda", "envia", "revisa",
}
# Multi-word phrases that signal an action item.
_TASK_PHRASES = (
    "need to", "have to", "has to", "todo:", "to-do", "don't forget",
    "hay que", "tengo que", "tenemos que", "debo", "debemos", "no olvidar",
    "acordarse de", "hay q",
)
# Time expressions that suggest an event.
_WEEKDAYS = {
    "monday", "tuesday", "wednesday", "thursday", "friday", "saturday",
    "sunday", "tomorrow", "today", "tonight",
    "lunes", "martes", "miercoles", "jueves", "viernes", "sabado", "domingo",
    "manana", "hoy",
}
_TIME_RE = re.compile(r"\b\d{1,2}(?::\d{2})?\s?(?:am|pm|h)\b", re.IGNORECASE)
# Topic lexicon: normalized keyword -> canonical topic label (display form).
_TOPIC_LEXICON = {
    "presupuesto": "presupuesto",
    "budget": "budget",
    "diseno": "diseño",
    "design": "design",
    "reunion": "reunión",
    "meeting": "meeting",
    "informe": "informe",
    "report": "report",
    "marketing": "marketing",
    "salud": "salud",
    "health": "health",
    "factura": "factura",
    "invoice": "invoice",
}
_PROJECT_RE = re.compile(
    r"\b(?:proyecto|project)\s+([A-ZÁÉÍÓÚÑ][\wÁÉÍÓÚÑáéíóúñ]+)"
)
_CAP_WORD_RE = re.compile(r"[A-ZÁÉÍÓÚÑ][a-záéíóúñ]+")
_SENTENCE_SPLIT_RE = re.compile(r"[.!?\n;¡¿]+")
_BULLET_RE = re.compile(r"^[\s\-*•\d.)]+")

# Capitalized words that are never person names (sentence starters, verbs,
# articles, pronouns, weekdays, topics...). Normalized (folded) form.
_NON_NAME = (
    _TASK_VERBS
    | _WEEKDAYS
    | set(_TOPIC_LEXICON.keys())
    | {
        "el", "la", "los", "las", "un", "una", "hoy", "necesito", "tengo",
        "tenemos", "debo", "debemos", "hay", "quiero", "voy", "estoy",
        "the", "a", "an", "i", "we", "need", "have", "want", "should",
        "remember", "please", "also", "then", "and", "or", "for", "with",
        "just", "reminder", "quizas", "tal", "vez", "solo", "solamente",
        "maybe", "today", "tonight", "proyecto", "project",
    }
)


def _clean_segment(segment: str) -> str:
    return _BULLET_RE.sub("", segment).strip()


def _is_task(segment: str) -> bool:
    norm = normalize_label(segment)
    if not norm:
        return False
    if any(phrase in norm for phrase in _TASK_PHRASES):
        return True
    first = norm.split(" ", 1)[0]
    return first in _TASK_VERBS


def _detect_persons(text: str) -> list[str]:
    """Detect person names as runs of capitalized words, minus known non-names.

    Capitalized words are matched individually and the ones that are verbs,
    articles, weekdays, topics, ... (``_NON_NAME``) are dropped. Adjacent
    survivors separated only by whitespace are merged into a full name, so
    "Call Ana" yields "Ana" and "John and Sarah" yields "John" and "Sarah".
    """
    kept: list[tuple[int, int, str]] = []
    for match in _CAP_WORD_RE.finditer(text):
        word = match.group(0)
        if normalize_label(word) in _NON_NAME:
            continue
        kept.append((match.start(), match.end(), word))

    names: list[str] = []
    seen: set[str] = set()
    i = 0
    while i < len(kept):
        start, end, word = kept[i]
        parts = [word]
        j = i + 1
        while j < len(kept):
            next_start, next_end, next_word = kept[j]
            if text[end:next_start].strip() == "":
                parts.append(next_word)
                end = next_end
                j += 1
            else:
                break
        name = " ".join(parts)
        key = normalize_label(name)
        if key not in seen:
            seen.add(key)
            names.append(name)
        i = j
    return names


def _detect_topics(text: str) -> list[str]:
    norm = normalize_label(text)
    tokens = set(norm.split(" "))
    topics: list[str] = []
    seen: set[str] = set()
    for keyword, label in _TOPIC_LEXICON.items():
        if keyword in tokens and label not in seen:
            seen.add(label)
            topics.append(label)
    return topics


def _detect_events(text: str) -> list[str]:
    events: list[str] = []
    seen: set[str] = set()
    for token_match in re.finditer(r"[A-Za-zÁÉÍÓÚÑáéíóúñ]+", text):
        token = token_match.group(0)
        if normalize_label(token) in _WEEKDAYS:
            key = normalize_label(token)
            if key not in seen:
                seen.add(key)
                events.append(token)
    for time_match in _TIME_RE.finditer(text):
        token = time_match.group(0).strip()
        key = normalize_label(token)
        if key not in seen:
            seen.add(key)
            events.append(token)
    return events


def _detect_projects(text: str) -> list[str]:
    projects: list[str] = []
    seen: set[str] = set()
    for match in _PROJECT_RE.finditer(text):
        name = match.group(1).strip()
        key = normalize_label(name)
        if key not in seen:
            seen.add(key)
            projects.append(name)
    return projects


def _extract_capture_text(prompt: str) -> str:
    """Recover the delimited capture text from the extraction prompt."""
    # Imported lazily to avoid a cycle at module import time.
    from app.understanding.extract import CAPTURE_CLOSE, CAPTURE_OPEN

    start = prompt.rfind(CAPTURE_OPEN)
    end = prompt.rfind(CAPTURE_CLOSE)
    if start == -1 or end == -1 or end <= start:
        return prompt
    return prompt[start + len(CAPTURE_OPEN) : end].strip()


def _heuristic_extraction(text: str) -> dict:
    segments = [
        _clean_segment(s) for s in _SENTENCE_SPLIT_RE.split(text) if s.strip()
    ]

    tasks: list[dict] = []
    task_segments: list[str] = []
    for seg in segments:
        if _is_task(seg):
            tasks.append({"label": seg, "confidence": 0.9})
            task_segments.append(seg)

    persons = _detect_persons(text)
    topics = _detect_topics(text)
    events = _detect_events(text)
    projects = _detect_projects(text)

    # A label already resolved as a project is not also a person (reduces the
    # obvious "proyecto Aurora" -> person Aurora false positive).
    project_norms = {normalize_label(p) for p in projects}
    persons = [p for p in persons if normalize_label(p) not in project_norms]

    entities: list[dict] = []
    for p in persons:
        entities.append({"type": "person", "label": p, "confidence": 0.8})
    for pr in projects:
        entities.append({"type": "project", "label": pr, "confidence": 0.75})
    for ev in events:
        entities.append({"type": "event", "label": ev, "confidence": 0.6})
    for t in topics:
        entities.append({"type": "topic", "label": t, "confidence": 0.7})

    # assigned_to: a task and a person co-occurring in the same segment.
    connections: list[dict] = []
    seen_conn: set[tuple[str, str, str]] = set()
    for seg in task_segments:
        seg_norm = normalize_label(seg)
        for p in persons:
            if normalize_label(p) in seg_norm:
                key = ("assigned_to", normalize_label(seg), normalize_label(p))
                if key not in seen_conn:
                    seen_conn.add(key)
                    connections.append(
                        {
                            "type": "assigned_to",
                            "source": seg,
                            "target": p,
                            "confidence": 0.7,
                        }
                    )

    return {"entities": entities, "tasks": tasks, "connections": connections}


# --- Expense heuristic (second call, mejoras-v2 §E) ----------------------------
# An amount with an explicit currency marker, before or after the number.
_AMOUNT = r"(\d+(?:[.,]\d{3})*(?:[.,]\d{1,2})?)"
_MONEY_BEFORE = re.compile(
    r"(r\$|us\$|€|£|s/|\$|usd|eur|brl|mxn|cop|ars|clp|pen)\s?" + _AMOUNT,
    re.IGNORECASE,
)
_MONEY_AFTER = re.compile(
    _AMOUNT
    + r"\s?(€|(?:reais|euros?|dolares|dollars?|pesos?|soles|bucks|usd|eur|brl"
    r"|mxn|cop|ars|clp|pen)\b)",
    re.IGNORECASE,
)
_CURRENCY_OF = {
    "r$": "BRL", "reais": "BRL", "brl": "BRL",
    "€": "EUR", "euro": "EUR", "euros": "EUR", "eur": "EUR",
    "us$": "USD", "usd": "USD", "dolares": "USD", "dollar": "USD",
    "dollars": "USD", "bucks": "USD",
    "£": "GBP", "s/": "PEN", "soles": "PEN", "pen": "PEN",
    "mxn": "MXN", "cop": "COP", "ars": "ARS", "clp": "CLP",
}
# A sentence about a FUTURE or pending payment is a task, not an expense.
_FUTURE_MARKERS = (
    "tengo que", "hay que", "tenemos que", "debo", "vou ", "preciso",
    "need to", "have to", "will ", "going to", "manana", "tomorrow", "amanha",
    "pagar ", "pay ",
)
_EXPENSE_CATEGORY_LEXICON = (
    ("food", ("almuerzo", "almoco", "comida", "cena", "jantar", "cafe", "coffee",
              "lunch", "dinner", "super", "mercado", "groceries", "restaurante",
              "pizza", "pan")),
    ("transport", ("uber", "taxi", "bus", "onibus", "gasolina", "nafta", "fuel",
                   "metro", "parking", "estacionamiento", "pasaje")),
    ("health", ("farmacia", "pharmacy", "medico", "doctor", "dentista",
                "remedio", "medicina")),
    ("bills", ("luz", "agua", "internet", "telefono", "celular", "electricity",
               "water bill", "phone bill", "seguro", "impuesto")),
    ("home", ("alquiler", "aluguel", "rent", "arriendo", "renta", "mueble")),
    ("leisure", ("cine", "cinema", "movie", "bar", "netflix", "spotify",
                 "concierto", "show", "viaje")),
    ("shopping", ("ropa", "roupa", "zapatos", "clothes", "shoes", "regalo",
                  "gift", "celular nuevo")),
    ("education", ("curso", "course", "libro", "book", "escuela", "school",
                   "universidad", "matricula")),
)


_SENTENCE_SPLIT = re.compile(r"[.!?;]+(?=\s|$)|\n+")
# Clause joins inside a sentence — never the separators inside "1.200,50".
_CLAUSE_SPLIT = re.compile(r",(?=\s)|\s(?:y|e|and)\s", re.IGNORECASE)
_PAST_SPEND = re.compile(
    r"\b(?:gaste|gastei|gasto|gastamos|pague|paguei|pago|pagamos|compre|"
    r"comprei|compro|compramos|spent|paid|bought|costo|custou|me salio)\b"
)


def _fold(text: str) -> str:
    """Drop diacritics only (keeps case, symbols and digits)."""
    decomposed = unicodedata.normalize("NFKD", text)
    return "".join(ch for ch in decomposed if not unicodedata.combining(ch))


def _clause_expenses(clause: str, folded: str) -> list[dict]:
    raw = _fold(clause)
    found: list[tuple[int, str, str]] = []
    for m in _MONEY_BEFORE.finditer(raw):
        found.append((m.start(), m.group(2), m.group(1)))
    for m in _MONEY_AFTER.finditer(raw):
        if not any(abs(m.start() - start) < 3 for start, _, _ in found):
            found.append((m.start(), m.group(1), m.group(2)))
    category = next(
        (
            c
            for c, words in _EXPENSE_CATEGORY_LEXICON
            if any(w in folded for w in words)
        ),
        "other",
    )
    return [
        {
            "amount": amount,
            "currency": _CURRENCY_OF.get(marker.lower()),
            "category": category,
            "description": clause.strip()[:60],
        }
        for _, amount, marker in sorted(found)
    ]


def _heuristic_expenses(text: str) -> dict:
    """Deterministic stand-in for the expense call: explicit amounts in
    clauses that are not about a future payment. Future intent carries over
    to the next clauses of the sentence until a past spending verb appears
    ("tengo que pagar la luz, son 300 pesos" is one pending payment)."""
    expenses: list[dict] = []
    for sentence in _SENTENCE_SPLIT.split(text):
        future = False
        for clause in _CLAUSE_SPLIT.split(sentence):
            folded = normalize_label(clause)
            if not folded:
                continue
            if _PAST_SPEND.search(folded):
                future = False
            if any(m in f"{folded} " for m in _FUTURE_MARKERS):
                future = True
            if not future:
                expenses.extend(_clause_expenses(clause, folded))
    return {"expenses": expenses}


def _estimate_tokens(text: str) -> int:
    return max(1, len(text) // 4)


class FakeProvider(AIProvider):
    """Deterministic provider for tests and offline evaluation (cost = 0)."""

    async def complete(
        self, prompt: str, *, schema: dict | None = None
    ) -> Completion:
        text = _extract_capture_text(prompt)
        if schema is not None and "expenses" in schema.get("properties", {}):
            payload = json.dumps(_heuristic_expenses(text), ensure_ascii=False)
        else:
            payload = json.dumps(_heuristic_extraction(text), ensure_ascii=False)
        usage = Usage(
            provider=_PROVIDER_NAME,
            model=_COMPLETE_MODEL,
            operation="complete",
            input_tokens=_estimate_tokens(prompt),
            output_tokens=_estimate_tokens(payload),
            cost_usd=0.0,
        )
        return Completion(text=payload, usage=usage)

    async def complete_text(self, prompt: str) -> Completion:
        # Deterministic "grounded" answer: echo the first numbered note of a RAG
        # prompt with its citation, so offline/dev runs look sensible.
        notes = re.findall(r"^\[(\d+)\]\s*(.+)$", prompt, flags=re.MULTILINE)
        if notes:
            number, note = notes[0]
            text = f"Según tus notas: {note.strip()} [{number}]."
        else:
            text = "No tengo esa información registrada en tus notas."
        usage = Usage(
            provider=_PROVIDER_NAME,
            model=_COMPLETE_MODEL,
            operation="complete",
            input_tokens=_estimate_tokens(prompt),
            output_tokens=_estimate_tokens(text),
            cost_usd=0.0,
        )
        return Completion(text=text, usage=usage)

    async def embed(self, text: str) -> Embedding:
        # Deterministic pseudo-embedding derived from a stable hash of the text.
        digest = hashlib.sha256(text.encode("utf-8")).digest()
        vector = [
            ((digest[i % len(digest)]) / 255.0) * 2.0 - 1.0
            for i in range(_EMBED_DIM)
        ]
        usage = Usage(
            provider=_PROVIDER_NAME,
            model=_EMBED_MODEL,
            operation="embed",
            input_tokens=_estimate_tokens(text),
            output_tokens=0,
            cost_usd=0.0,
        )
        return Embedding(vector=vector, dim=_EMBED_DIM, usage=usage)

    async def transcribe(
        self,
        audio_bytes: bytes,
        content_type: str,
        *,
        duration_s: float | None = None,
    ) -> Completion:
        # Deterministic offline stand-in: empty audio -> empty transcript (lets
        # the API's "nothing was heard" path be exercised end to end).
        text = (
            f"Nota de voz de prueba ({len(audio_bytes)} bytes)"
            if audio_bytes
            else ""
        )
        usage = Usage(
            provider=_PROVIDER_NAME,
            model="fake-stt-1",
            operation="transcribe",
            input_tokens=0,
            output_tokens=_estimate_tokens(text),
            cost_usd=0.0,
        )
        return Completion(text=text, usage=usage)
