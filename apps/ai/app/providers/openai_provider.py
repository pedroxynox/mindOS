"""Real OpenAI-backed :class:`AIProvider` (minimal, robust).

Reads ``OPENAI_API_KEY`` from the environment (via ``Settings``). If no key is
configured, construction fails fast with a clear error — the eval harness
defaults to the ``FakeProvider`` so this is only reached when explicitly asked
for (``llm_provider = "openai"``).

The chat/embedding/retry machinery is shared with other OpenAI-compatible
vendors (e.g. Groq) via :class:`OpenAICompatibleProvider`; this class only
supplies OpenAI's identity, models and public prices. The retry predicates
``_is_retryable``/``_retry_after_seconds`` are re-exported from the shared base
for backwards compatibility (they are imported by the retry tests).
"""

from __future__ import annotations

from typing import TYPE_CHECKING

from app.providers.openai_compatible import (
    OpenAICompatibleProvider,
)
from app.providers.openai_compatible import (
    is_retryable as _is_retryable,
)
from app.providers.openai_compatible import (
    retry_after_seconds as _retry_after_seconds,
)

if TYPE_CHECKING:
    from app.config import Settings

__all__ = ["OpenAIProvider", "_is_retryable", "_retry_after_seconds"]

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


class OpenAIProvider(OpenAICompatibleProvider):
    """Thin wrapper over the OpenAI async SDK (default OpenAI endpoint)."""

    def __init__(self, settings: "Settings") -> None:
        if not settings.openai_api_key:
            raise ValueError(
                "OPENAI_API_KEY is not set; cannot use the 'openai' provider. "
                "Export the key or use llm_provider='fake' for offline runs."
            )
        super().__init__(
            provider_name=_PROVIDER_NAME,
            api_key=settings.openai_api_key,
            model=settings.openai_model,
            embedding_model=settings.openai_embedding_model,
            prices_per_mtok=_PRICES_PER_MTOK,
            max_retries=settings.openai_max_retries,
            backoff_base_s=settings.openai_backoff_base_s,
        )
