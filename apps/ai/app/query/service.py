"""Question answering over the user's own knowledge (RAG).

Given a question, embed it, retrieve the most semantically similar captures for
that user (pgvector, RLS-scoped so a user can only ever match their own notes),
and ask the LLM to answer USING ONLY those notes — citing them and refusing to
guess. This is the "ask mindOS" value loop (design §7 retrieval).

The DB retrieval and the answer synthesis are separated so the synthesis (and
the prompt/format) can be unit-tested with a fake provider and no database.
"""

from __future__ import annotations

from dataclasses import dataclass, field

from app.config import Settings
from app.providers.base import AIProvider
from app.understanding.rls import rls_tx

# How many notes to feed the model as grounding context, and how much of each.
MAX_CONTEXT_NOTES = 6
SNIPPET_LEN = 280


@dataclass(frozen=True)
class Source:
    """A capture used to ground the answer (shown to the user as a citation)."""

    capture_id: str
    snippet: str


@dataclass(frozen=True)
class QueryAnswer:
    """The synthesized answer plus the notes it was grounded on."""

    answer: str
    sources: list[Source] = field(default_factory=list)


def format_vector(vector: list[float], dim: int) -> str:
    """Render a vector as a pgvector literal, padded/truncated to ``dim``."""
    values = list(vector[:dim]) + [0.0] * max(0, dim - len(vector))
    return "[" + ",".join(repr(float(x)) for x in values) + "]"


def snippet_of(body: str | None) -> str:
    """A short, trimmed preview of a capture body for a citation."""
    text = (body or "").strip().replace("\n", " ")
    return text[:SNIPPET_LEN]


def build_answer_prompt(question: str, notes: list[str]) -> str:
    """Grounded RAG prompt: answer ONLY from the notes, cite them, never guess."""
    numbered = "\n".join(f"[{i + 1}] {note}" for i, note in enumerate(notes))
    return (
        "Eres el asistente personal de mindOS. Responde la pregunta del usuario\n"
        "USANDO ÚNICAMENTE la información de sus notas listadas abajo.\n"
        "\n"
        "Reglas:\n"
        "- No inventes ni añadas nada que no esté en las notas.\n"
        "- Responde en el MISMO idioma de la pregunta.\n"
        "- Sé breve y directo (2 a 4 frases).\n"
        "- Cita las notas que uses con su número entre corchetes, por ejemplo [1].\n"
        "- Si las notas no contienen la respuesta, dilo con claridad: que no tienes\n"
        "  esa información registrada. No adivines.\n"
        "\n"
        f"NOTAS DEL USUARIO:\n{numbered}\n"
        "\n"
        f"PREGUNTA: {question}\n"
        "\n"
        "RESPUESTA:"
    )


# Shown when the user has no processed notes matching the question yet.
_NO_NOTES_ANSWER = (
    "Todavía no tengo notas para responder eso. Captura algo primero y, cuando "
    "mindOS lo procese, vuelve a preguntar."
)


async def answer_from_sources(
    question: str,
    sources: list[Source],
    *,
    provider: AIProvider,
) -> QueryAnswer:
    """Synthesize an answer from already-retrieved sources (no DB access here)."""
    if not sources:
        return QueryAnswer(answer=_NO_NOTES_ANSWER, sources=[])
    prompt = build_answer_prompt(question, [s.snippet for s in sources])
    completion = await provider.complete(prompt)
    return QueryAnswer(answer=completion.text.strip(), sources=sources)


async def retrieve_sources(
    user_id: str,
    query_vector_literal: str,
    *,
    pool: object,
    limit: int,
) -> list[Source]:
    """Top-N most similar processed captures for the user (RLS-scoped)."""
    async with rls_tx(pool, user_id) as conn:
        rows = await conn.fetch(
            "SELECT id, body FROM nodes "
            "WHERE type = 'capture' AND status = 'processed' "
            "AND embedding IS NOT NULL AND body IS NOT NULL "
            "ORDER BY embedding <=> $1::vector LIMIT $2",
            query_vector_literal,
            limit,
        )
    return [Source(capture_id=str(r["id"]), snippet=snippet_of(r["body"])) for r in rows]


async def answer_question(
    user_id: str,
    question: str,
    *,
    pool: object,
    provider: AIProvider,
    settings: Settings,
    limit: int = MAX_CONTEXT_NOTES,
) -> QueryAnswer:
    """Full RAG: embed → retrieve the user's notes → grounded answer with citations."""
    embedding = await provider.embed(question)
    vector_literal = format_vector(embedding.vector, settings.embedding_dim)
    sources = await retrieve_sources(
        user_id, vector_literal, pool=pool, limit=limit
    )
    return await answer_from_sources(question, sources, provider=provider)
