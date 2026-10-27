"""Voice notes (ADR-021): the internal transcription endpoint and the
OpenAI-compatible ``transcribe`` implementation.

The endpoint is fail-closed like ``/internal/query``, validates the audio
(type, size, non-empty), and never persists it. The provider sends the
LatAm-first language hints to gpt-transcribe only, and attributes a
per-minute cost. All offline: the OpenAI client is a stub.
"""

from types import SimpleNamespace
from typing import Any

import pytest
from fastapi.testclient import TestClient

import app.main as main
from app.providers.fake_provider import FakeProvider
from app.providers.openai_compatible import OpenAICompatibleProvider

client = TestClient(main.app)
SECRET = "s3cret"


@pytest.fixture(autouse=True)
def _secret_and_fake(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(main.settings, "query_internal_secret", SECRET)
    monkeypatch.setattr(main, "_provider", FakeProvider())


def _post(body: bytes, content_type: str = "audio/webm", **params: Any) -> Any:
    return client.post(
        "/internal/transcribe",
        content=body,
        params=params,
        headers={"content-type": content_type, "x-internal-token": SECRET},
    )


def test_transcribes_a_voice_note() -> None:
    res = _post(b"\x1a\x45\xdf\xa3fake-webm", duration_ms=4200)
    assert res.status_code == 200
    data = res.json()
    assert data["text"].startswith("Nota de voz de prueba")
    assert data["duration_s"] == pytest.approx(4.2)
    assert data["provider"] == "fake"


def test_is_fail_closed_without_the_internal_token() -> None:
    res = client.post(
        "/internal/transcribe",
        content=b"x",
        headers={"content-type": "audio/webm", "x-internal-token": "wrong"},
    )
    assert res.status_code == 401


def test_rejects_non_audio_and_empty_bodies() -> None:
    assert _post(b"hello", content_type="text/plain").status_code == 415
    assert _post(b"").status_code == 422


def test_rejects_oversized_audio(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(main.settings, "transcribe_max_bytes", 10)
    assert _post(b"x" * 11).status_code == 413


def test_upstream_failure_is_a_502(monkeypatch: pytest.MonkeyPatch) -> None:
    class _Broken(FakeProvider):
        async def transcribe(self, *a: Any, **k: Any) -> Any:
            raise RuntimeError("provider down")

    monkeypatch.setattr(main, "_provider", _Broken())
    assert _post(b"audio").status_code == 502


class _StubTranscriptions:
    def __init__(self) -> None:
        self.kwargs: dict[str, Any] = {}

    async def create(self, **kwargs: Any) -> Any:
        self.kwargs = kwargs
        return SimpleNamespace(text="  Llamar a Marcos mañana  ")


def _provider_with_stub(model: str) -> tuple[OpenAICompatibleProvider, Any]:
    provider = OpenAICompatibleProvider(
        provider_name="openai",
        api_key="k",
        model="gpt-5.4-mini",
        embedding_model=None,
        prices_per_mtok={},
        max_retries=0,
        backoff_base_s=0.0,
        transcribe_model=model,
        transcribe_usd_per_min=0.0045,
    )
    stub = _StubTranscriptions()
    provider._client = SimpleNamespace(  # type: ignore[assignment]
        audio=SimpleNamespace(transcriptions=stub)
    )
    return provider, stub


async def test_gpt_transcribe_gets_language_hints_and_per_minute_cost() -> None:
    provider, stub = _provider_with_stub("gpt-transcribe")
    completion = await provider.transcribe(
        b"audio", "audio/webm;codecs=opus", duration_s=120
    )
    assert completion.text == "Llamar a Marcos mañana"
    assert completion.usage.operation == "transcribe"
    assert completion.usage.cost_usd == pytest.approx(0.009)
    assert stub.kwargs["extra_body"] == {"languages": ["es", "pt", "en"]}
    assert stub.kwargs["file"][0] == "voice.webm"
    assert stub.kwargs["response_format"] == "json"


async def test_whisper_models_get_no_language_array() -> None:
    provider, stub = _provider_with_stub("whisper-large-v3-turbo")
    await provider.transcribe(b"audio", "audio/mp4")
    assert stub.kwargs["extra_body"] is None
    assert stub.kwargs["file"][0] == "voice.m4a"


async def test_providers_without_speech_to_text_fail_clearly() -> None:
    provider = OpenAICompatibleProvider(
        provider_name="gemini",
        api_key="k",
        model="m",
        embedding_model=None,
        prices_per_mtok={},
        max_retries=0,
        backoff_base_s=0.0,
    )
    with pytest.raises(NotImplementedError):
        await provider.transcribe(b"audio", "audio/webm")
