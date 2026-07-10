"""Tests for the RAG query service and the internal endpoint guard.

Pure helpers (vector formatting, snippet, prompt) and the answer synthesis are
tested with a fake provider and no database. The endpoint tests only cover the
fail-closed auth guard (no DB is touched on those paths).
"""

import app.main as main
from app.providers.base import Completion, Usage
from app.query.service import (
    Source,
    answer_from_sources,
    build_answer_prompt,
    format_vector,
    snippet_of,
)
from fastapi.testclient import TestClient

client = TestClient(main.app)


class _StubProvider:
    """Records the prompt it was given and returns a canned completion."""

    def __init__(self) -> None:
        self.prompt: str | None = None

    async def complete(self, prompt: str, *, schema: dict | None = None) -> Completion:
        self.prompt = prompt
        return Completion(
            text="  Tienes que llamar a Marcos [1].  ",
            usage=Usage("fake", "m", "complete", 1, 1, 0.0),
        )

    async def embed(self, text: str):  # pragma: no cover - unused here
        raise NotImplementedError

    async def transcribe(self, audio_bytes: bytes, content_type: str):  # pragma: no cover
        raise NotImplementedError


def test_format_vector_pads_and_truncates() -> None:
    assert format_vector([1.0, 2.0], 4) == "[1.0,2.0,0.0,0.0]"
    assert format_vector([1.0, 2.0, 3.0], 2) == "[1.0,2.0]"


def test_snippet_trims_and_caps_length() -> None:
    assert snippet_of("  hola\nmundo  ") == "hola mundo"
    long = "x" * 500
    assert len(snippet_of(long)) == 280
    assert snippet_of(None) == ""


def test_prompt_numbers_notes_and_includes_question() -> None:
    prompt = build_answer_prompt("¿Qué debo hacer?", ["nota A", "nota B"])
    assert "[1] nota A" in prompt
    assert "[2] nota B" in prompt
    assert "¿Qué debo hacer?" in prompt
    # It must instruct grounding + citation + no-invention.
    assert "ÚNICAMENTE" in prompt


async def test_answer_from_sources_empty_returns_no_notes_message() -> None:
    provider = _StubProvider()
    result = await answer_from_sources("cualquier cosa", [], provider=provider)
    assert result.sources == []
    assert "Todavía no tengo notas" in result.answer
    # No LLM call when there is nothing to ground on.
    assert provider.prompt is None


async def test_answer_from_sources_synthesizes_and_keeps_sources() -> None:
    provider = _StubProvider()
    sources = [Source(capture_id="c1", snippet="Llamar a Marcos mañana")]
    result = await answer_from_sources("¿Qué tengo con Marcos?", sources, provider=provider)
    assert result.answer == "Tienes que llamar a Marcos [1]."  # trimmed
    assert result.sources == sources
    assert provider.prompt is not None
    assert "Llamar a Marcos mañana" in provider.prompt


def test_internal_query_without_config_is_fail_closed(monkeypatch) -> None:
    monkeypatch.setattr(main.settings, "query_internal_secret", None)
    res = client.post(
        "/internal/query",
        json={"user_id": "u1", "question": "hola"},
    )
    assert res.status_code == 503


def test_internal_query_rejects_wrong_token(monkeypatch) -> None:
    monkeypatch.setattr(main.settings, "query_internal_secret", "right-secret")
    res = client.post(
        "/internal/query",
        json={"user_id": "u1", "question": "hola"},
        headers={"X-Internal-Token": "wrong"},
    )
    assert res.status_code == 401
