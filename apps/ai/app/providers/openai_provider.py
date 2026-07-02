"""Real OpenAI-backed :class:`AIProvider` (minimal, robust).

Reads ``OPENAI_API_KEY`` from the environment (via ``Settings``). If no key is
configured, construction fails fast with a clear error — the eval harness
defaults to the ``FakeProvider`` so this is only reached when explicitly asked
for (``llm_provider = "openai"``).

Kept intentionally small: chat completion with JSON output for extraction and a
single embedding call, each recording token usage and an estimated cost.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

from app.providers.base import AIProvider, Completion, Embedding, Usage

if TYPE_CHECKING:
    from app.config import Settings

_PROVIDER_NAME = "openai"

# Approximate public prices (USD per 1M tokens), provisional — used only to
# attribute an estimated cost. Update as pricing changes.
_PRICES_PER_MTOK: dict[str, tuple[float, float]] = {
    # model: (input_price, output_price)
    "gpt-4o-mini": (0.15, 0.60),
    "gpt-4o": (2.50, 10.00),
    "text-embedding-3-small": (0.02, 0.0),
    "text-embedding-3-large": (0.13, 0.0),
}


def _estimate_cost(model: str, input_tokens: int, output_tokens: int) -> float:
    in_price, out_price = _PRICES_PER_MTOK.get(model, (0.0, 0.0))
    return (input_tokens * in_price + output_tokens * out_price) / 1_000_000.0


class OpenAIProvider(AIProvider):
    """Thin wrapper over the OpenAI async SDK."""

    def __init__(self, settings: "Settings") -> None:
        if not settings.openai_api_key:
            raise ValueError(
                "OPENAI_API_KEY is not set; cannot use the 'openai' provider. "
                "Export the key or use llm_provider='fake' for offline runs."
            )
        # Imported lazily so the package (and the fake path) works without the
        # optional 'openai' dependency installed.
        try:
            from openai import AsyncOpenAI
        except ImportError as exc:  # pragma: no cover - depends on env
            raise ImportError(
                "The 'openai' package is required for the OpenAI provider. "
                "Install it with: pip install -e '.[ai]'"
            ) from exc

        self._client = AsyncOpenAI(api_key=settings.openai_api_key)
        self._model = settings.openai_model
        self._embedding_model = settings.openai_embedding_model

    async def complete(
        self, prompt: str, *, schema: dict | None = None
    ) -> Completion:
        response = await self._client.chat.completions.create(
            model=self._model,
            messages=[
                {
                    "role": "system",
                    "content": "You output only valid JSON. No prose, no markdown.",
                },
                {"role": "user", "content": prompt},
            ],
            response_format={"type": "json_object"},
            temperature=0,
        )
        text = response.choices[0].message.content or "{}"
        u = response.usage
        input_tokens = u.prompt_tokens if u else 0
        output_tokens = u.completion_tokens if u else 0
        usage = Usage(
            provider=_PROVIDER_NAME,
            model=self._model,
            operation="complete",
            input_tokens=input_tokens,
            output_tokens=output_tokens,
            cost_usd=_estimate_cost(self._model, input_tokens, output_tokens),
        )
        return Completion(text=text, usage=usage)

    async def embed(self, text: str) -> Embedding:
        response = await self._client.embeddings.create(
            model=self._embedding_model, input=text
        )
        vector = list(response.data[0].embedding)
        u = response.usage
        input_tokens = u.prompt_tokens if u else 0
        usage = Usage(
            provider=_PROVIDER_NAME,
            model=self._embedding_model,
            operation="embed",
            input_tokens=input_tokens,
            output_tokens=0,
            cost_usd=_estimate_cost(self._embedding_model, input_tokens, 0),
        )
        return Embedding(vector=vector, dim=len(vector), usage=usage)

    async def transcribe(self, audio_bytes: bytes, content_type: str) -> Completion:
        # Declared for contract completeness; the comprehension PoC never calls
        # this. Wire up Whisper here when voice transcription lands.
        raise NotImplementedError("transcribe is out of scope for the F2 PoC")
