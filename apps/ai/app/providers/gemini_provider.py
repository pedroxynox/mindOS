"""Free, no-card :class:`AIProvider` backed by Google Gemini (AI Studio).

Google exposes an **OpenAI-compatible** API for its Gemini models at
``https://generativelanguage.googleapis.com/v1beta/openai/``, so we reuse the
very same async ``openai`` SDK — only the ``base_url`` and the API key differ
(exactly like :class:`GroqProvider`). This lets the F2 comprehension exam run at
**zero cost** on Gemini's much more generous free tier: a key from
``https://aistudio.google.com/app/apikey`` needs **no credit card**, and the
free limits are notably higher than Groq's (~15 requests/min, ~1M tokens/min).

Reuse notes:
- Chat completion, token accounting and the retry/backoff policy (429/5xx) are
  inherited unchanged from :class:`OpenAICompatibleProvider`.
- Gemini's free tier has no published per-token price here, so the estimated
  cost is ``0.0`` (an explicit estimate, not a measured bill).
- Embeddings are skipped for this PoC (``embedding_model=None``), like Groq, so
  a call to ``embed`` fails with a clear error. The extraction eval only uses
  ``complete``, so this is never hit there.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

from app.providers.openai_compatible import OpenAICompatibleProvider

if TYPE_CHECKING:
    from app.config import Settings

_PROVIDER_NAME = "gemini"

# Google's OpenAI-compatible endpoint for the Gemini models. The same
# ``openai`` AsyncOpenAI client talks to it when pointed here.
_GEMINI_BASE_URL = "https://generativelanguage.googleapis.com/v1beta/openai/"

# Free tier: no per-token price is attributed. Kept empty on purpose so
# ``estimate_cost`` resolves every model to 0.0 (an estimate of 0, not a bill).
_PRICES_PER_MTOK: dict[str, tuple[float, float]] = {}


class GeminiProvider(OpenAICompatibleProvider):
    """OpenAI-compatible provider targeting Gemini's free endpoint (cost = 0)."""

    def __init__(self, settings: "Settings") -> None:
        if not settings.gemini_api_key:
            raise ValueError(
                "GEMINI_API_KEY is not set; cannot use the 'gemini' provider. "
                "Get a free key (no credit card) at "
                "https://aistudio.google.com/app/apikey "
                "or use llm_provider='fake' for offline runs."
            )
        super().__init__(
            provider_name=_PROVIDER_NAME,
            api_key=settings.gemini_api_key,
            base_url=_GEMINI_BASE_URL,
            model=settings.gemini_model,
            # No embeddings for the PoC; disable embed with a clear error.
            embedding_model=None,
            prices_per_mtok=_PRICES_PER_MTOK,
            # Reuse the shared resilience settings (same SDK, same 429 semantics).
            max_retries=settings.openai_max_retries,
            backoff_base_s=settings.openai_backoff_base_s,
        )
