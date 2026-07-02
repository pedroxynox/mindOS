"""Tests for provider selection by configuration."""

import pytest

from app.config import Settings
from app.providers.factory import build_provider
from app.providers.fake_provider import FakeProvider


def _settings(**overrides: object) -> Settings:
    base = {"llm_provider": "fake", "openai_api_key": None}
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
