"""Tests for provider selection by configuration."""

import pytest

from app.config import Settings
from app.providers.factory import build_provider
from app.providers.fake_provider import FakeProvider
from app.providers.gemini_provider import GeminiProvider
from app.providers.groq_provider import GroqProvider


def _settings(**overrides: object) -> Settings:
    base = {
        "llm_provider": "fake",
        "openai_api_key": None,
        "groq_api_key": None,
        "gemini_api_key": None,
    }
    base.update(overrides)
    return Settings(**base)


def test_build_provider_defaults_to_fake() -> None:
    provider = build_provider(_settings(llm_provider="fake"))
    assert isinstance(provider, FakeProvider)


def test_build_provider_unknown_raises() -> None:
    with pytest.raises(ValueError, match="unknown LLM provider"):
        build_provider(_settings(llm_provider="megamind"))


def test_build_provider_openai_without_key_raises() -> None:
    with pytest.raises(ValueError, match="OPENAI_API_KEY"):
        build_provider(_settings(llm_provider="openai", openai_api_key=None))


def test_build_provider_groq_returns_groq_provider() -> None:
    provider = build_provider(
        _settings(llm_provider="groq", groq_api_key="gsk-test-key")
    )
    assert isinstance(provider, GroqProvider)


def test_build_provider_groq_without_key_raises() -> None:
    with pytest.raises(ValueError, match="GROQ_API_KEY"):
        build_provider(_settings(llm_provider="groq", groq_api_key=None))


@pytest.mark.asyncio
async def test_groq_embed_raises_clear_error() -> None:
    # Groq has no embeddings endpoint: embed must fail with a clear message
    # (no network call is made — it raises before touching the client).
    provider = build_provider(
        _settings(llm_provider="groq", groq_api_key="gsk-test-key")
    )
    with pytest.raises(NotImplementedError, match="does not support"):
        await provider.embed("hello world")


def test_build_provider_gemini_returns_gemini_provider() -> None:
    provider = build_provider(
        _settings(llm_provider="gemini", gemini_api_key="test-key")
    )
    assert isinstance(provider, GeminiProvider)


def test_build_provider_gemini_without_key_raises() -> None:
    with pytest.raises(ValueError, match="GEMINI_API_KEY"):
        build_provider(_settings(llm_provider="gemini", gemini_api_key=None))


@pytest.mark.asyncio
async def test_gemini_embed_raises_clear_error() -> None:
    # Gemini skips embeddings for the PoC: embed must fail with a clear message
    # (no network call is made — it raises before touching the client).
    provider = build_provider(
        _settings(llm_provider="gemini", gemini_api_key="test-key")
    )
    with pytest.raises(NotImplementedError, match="does not support"):
        await provider.embed("hello world")
