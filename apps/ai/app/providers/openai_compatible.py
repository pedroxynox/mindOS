"""Shared base for OpenAI-compatible providers (OpenAI, Groq, ...).

Groq (and several other vendors) expose an API that is wire-compatible with
OpenAI's, so the same official ``openai`` async SDK can talk to them by simply
pointing ``base_url`` at the vendor and supplying that vendor's API key. This
module factors out everything those providers share — client construction, the
retry/backoff wrapper, token accounting and cost estimation — so a concrete
provider only has to declare its identity (name, endpoint, models, prices).

The retry predicates live here because the exceptions are raised by the shared
``openai`` SDK regardless of which endpoint is targeted; they are re-exported
from :mod:`app.providers.openai_provider` for backwards compatibility.
"""

from __future__ import annotations

from collections.abc import Awaitable, Callable
from typing import TYPE_CHECKING, TypeVar

from app.providers.base import AIProvider, Completion, Embedding, Usage
from app.providers.retry import retry_async

if TYPE_CHECKING:  # pragma: no cover - typing only
    from openai import AsyncOpenAI

T = TypeVar("T")

# Model families that reject a custom ``temperature`` and only accept the
# default (1): the GPT-5 line and the o-series reasoning models. For those we
# must OMIT the parameter entirely (sending temperature=0 returns HTTP 400
# "Unsupported value: 'temperature' does not support 0 with this model").
# Everything else (gpt-4o, Groq's llama, Gemini's OpenAI-compatible endpoint)
# supports temperature=0, which we prefer for deterministic extraction.
_TEMPERATURE_LOCKED_PREFIXES = ("gpt-5", "o1", "o3", "o4")


def supports_custom_temperature(model: str) -> bool:
    """False for models that only allow the default temperature (GPT-5 / o-series)."""
    return not model.lower().startswith(_TEMPERATURE_LOCKED_PREFIXES)


def is_retryable(exc: BaseException) -> bool:
    """True for transient failures worth retrying (429 / timeout / 5xx).

    Unrecoverable errors (authentication 401, bad request 400, ...) are *not*
    listed here and therefore propagate immediately without a retry. The
    exception types come from the shared ``openai`` SDK, so this predicate
    works for any OpenAI-compatible endpoint (including Groq).
    """
    from openai import (
        APIConnectionError,
        APITimeoutError,
        InternalServerError,
        RateLimitError,
    )

    return isinstance(
        exc,
        (RateLimitError, APITimeoutError, APIConnectionError, InternalServerError),
    )


def retry_after_seconds(exc: BaseException) -> float | None:
    """Extract a ``Retry-After`` hint (seconds) from an API error, if any."""
    response = getattr(exc, "response", None)
    headers = getattr(response, "headers", None)
    if not headers:
        return None
    raw = headers.get("retry-after")
    if raw is None:
        return None
    try:
        # Header is typically an integer number of seconds. A date form is not
        # honoured here; falling back to computed backoff is acceptable.
        return float(raw)
    except (TypeError, ValueError):
        return None


def estimate_cost(
    prices_per_mtok: dict[str, tuple[float, float]],
    model: str,
    input_tokens: int,
    output_tokens: int,
) -> float:
    """Estimate USD cost from a (input, output) price-per-million table.

    Unknown models (or providers with no published price, e.g. a free tier)
    resolve to ``(0.0, 0.0)`` and therefore an estimated cost of ``0.0``.
    """
    in_price, out_price = prices_per_mtok.get(model, (0.0, 0.0))
    return (input_tokens * in_price + output_tokens * out_price) / 1_000_000.0


class OpenAICompatibleProvider(AIProvider):
    """Base class for providers backed by the OpenAI-compatible async SDK.

    Concrete providers pass their identity/config to :meth:`__init__`; the chat
    completion, embedding and retry machinery is shared. Providers that do not
    offer embeddings (e.g. Groq) pass ``embedding_model=None`` and a call to
    :meth:`embed` then fails with a clear, actionable error.
    """

    def __init__(
        self,
        *,
        provider_name: str,
        api_key: str,
        model: str,
        embedding_model: str | None,
        prices_per_mtok: dict[str, tuple[float, float]],
        max_retries: int,
        backoff_base_s: float,
        base_url: str | None = None,
    ) -> None:
        try:
            from openai import AsyncOpenAI
        except ImportError as exc:  # pragma: no cover - depends on env
            raise ImportError(
                "The 'openai' package is required for this provider. "
                "Install it with: pip install -e '.[ai]'"
            ) from exc

        # We manage retries ourselves (backoff + jitter honouring Retry-After),
        # so disable the SDK's own retry loop to avoid compounding both.
        self._client: AsyncOpenAI = AsyncOpenAI(
            api_key=api_key, base_url=base_url, max_retries=0
        )
        self._provider_name = provider_name
        self._model = model
        self._embedding_model = embedding_model
        self._prices_per_mtok = prices_per_mtok
        self._max_retries = max_retries
        self._backoff_base_s = backoff_base_s
        # Prefer deterministic output (temperature=0), but omit the parameter
        # for models that only accept the default (GPT-5 / o-series) — sending
        # it there is rejected with HTTP 400.
        self._temperature: float | None = (
            0 if supports_custom_temperature(model) else None
        )

    def _with_retries(self, func: Callable[[], Awaitable[T]]) -> Awaitable[T]:
        """Wrap an API call with exponential backoff + jitter on 429/5xx/timeouts.

        After the retries are exhausted the original error is re-raised so
        callers (e.g. the eval runner) can present a clear, typed message.
        """
        return retry_async(
            func,
            max_retries=self._max_retries,
            backoff_base_s=self._backoff_base_s,
            is_retryable=is_retryable,
            retry_after_s=retry_after_seconds,
        )

    def _estimate_cost(
        self, model: str, input_tokens: int, output_tokens: int
    ) -> float:
        return estimate_cost(
            self._prices_per_mtok, model, input_tokens, output_tokens
        )

    async def complete(
        self, prompt: str, *, schema: dict | None = None
    ) -> Completion:
        create_kwargs: dict = {
            "model": self._model,
            "messages": [
                {
                    "role": "system",
                    "content": (
                        "You output only valid JSON. No prose, no markdown."
                    ),
                },
                {"role": "user", "content": prompt},
            ],
            "response_format": {"type": "json_object"},
        }
        # Only send ``temperature`` when the model supports a custom value;
        # GPT-5 / o-series models reject anything other than the default (1).
        if self._temperature is not None:
            create_kwargs["temperature"] = self._temperature
        response = await self._with_retries(
            lambda: self._client.chat.completions.create(**create_kwargs)
        )
        text = response.choices[0].message.content or "{}"
        u = response.usage
        input_tokens = u.prompt_tokens if u else 0
        output_tokens = u.completion_tokens if u else 0
        usage = Usage(
            provider=self._provider_name,
            model=self._model,
            operation="complete",
            input_tokens=input_tokens,
            output_tokens=output_tokens,
            cost_usd=self._estimate_cost(self._model, input_tokens, output_tokens),
        )
        return Completion(text=text, usage=usage)

    async def embed(self, text: str) -> Embedding:
        embedding_model = self._embedding_model
        if embedding_model is None:
            raise NotImplementedError(
                f"the {self._provider_name!r} provider does not support "
                "embeddings; use another provider (e.g. 'openai') for embeddings."
            )
        response = await self._with_retries(
            lambda: self._client.embeddings.create(
                model=embedding_model, input=text
            )
        )
        vector = list(response.data[0].embedding)
        u = response.usage
        input_tokens = u.prompt_tokens if u else 0
        usage = Usage(
            provider=self._provider_name,
            model=embedding_model,
            operation="embed",
            input_tokens=input_tokens,
            output_tokens=0,
            cost_usd=self._estimate_cost(embedding_model, input_tokens, 0),
        )
        return Embedding(vector=vector, dim=len(vector), usage=usage)

    async def transcribe(self, audio_bytes: bytes, content_type: str) -> Completion:
        # Declared for contract completeness; the comprehension PoC never calls
        # this. Wire up speech-to-text here when voice transcription lands.
        raise NotImplementedError("transcribe is out of scope for the F2 PoC")
