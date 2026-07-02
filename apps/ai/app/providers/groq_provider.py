"""Free, no-card :class:`AIProvider` backed by Groq.

Groq exposes an **OpenAI-compatible** API at ``https://api.groq.com/openai/v1``,
so we reuse the very same async ``openai`` SDK — only the ``base_url`` and the
API key differ. This lets the F2 comprehension exam run at **zero cost**: Groq's
free tier needs no credit card, just an API key from ``console.groq.com``.

Reuse notes:
- Chat completion, token accounting and the retry/backoff policy (429/5xx) are
  inherited unchanged from :class:`OpenAICompatibleProvider`.
- Groq's free tier has no published per-token price here, so the estimated cost
  is ``0.0`` (an explicit estimate, not a measured bill).
- Groq does **not** offer an embeddings endpoint, so ``embed`` raises a clear
  error. The extraction eval only uses ``complete``, so this is never hit there.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

from app.providers.openai_compatible import OpenAICompatibleProvider

if TYPE_CHECKING:
    from app.config import Settings

_PROVIDER_NAME = "groq"

# Groq's OpenAI-compatible endpoint. The same ``openai`` AsyncOpenAI client
# talks to it when pointed here.
_GROQ_BASE_URL = "https://api.groq.com/openai/v1"

# Free tier: no per-token price is attributed. Kept empty on purpose so
# ``estimate_cost`` resolves every model to 0.0 (an estimate of 0, not a bill).
_PRICES_PER_MTOK: dict[str, tuple[float, float]] = {}


class GroqProvider(OpenAICompatibleProvider):
    """OpenAI-compatible provider targeting Groq's free endpoint (cost = 0)."""

    def __init__(self, settings: "Settings") -> None:
        if not settings.groq_api_key:
            raise ValueError(
                "GROQ_API_KEY is not set; cannot use the 'groq' provider. "
                "Get a free key (no credit card) at https://console.groq.com "
                "or use llm_provider='fake' for offline runs."
            )
        super().__init__(
            provider_name=_PROVIDER_NAME,
            api_key=settings.groq_api_key,
            base_url=_GROQ_BASE_URL,
            model=settings.groq_model,
            # Groq has no embeddings endpoint; disable embed with a clear error.
            embedding_model=None,
            prices_per_mtok=_PRICES_PER_MTOK,
            # Reuse the shared resilience settings (same SDK, same 429 semantics).
            max_retries=settings.openai_max_retries,
            backoff_base_s=settings.openai_backoff_base_s,
        )
