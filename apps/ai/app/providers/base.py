"""Abstract AIProvider interface (ADR-09 / ADR-012 D4).

Every access to a language model — completion, embedding, speech-to-text —
goes through this contract so the concrete vendor (OpenAI, Anthropic, a future
in-house model, or a deterministic ``FakeProvider``) can be swapped by
configuration without touching domain logic.

This evolves the F0 scaffold (``complete``/``embed`` returning bare values) so
that every call also returns its attributable ``Usage`` (tokens + cost). That
is the foundation for per-user cost accounting (``CostMeter``, design §7.1)
without coupling the domain to any single vendor.
"""

from abc import ABC, abstractmethod
from dataclasses import dataclass


@dataclass(frozen=True)
class Usage:
    """Attributable usage of a single model call (basis of per-user cost)."""

    provider: str
    model: str
    operation: str  # 'complete' | 'embed' | 'transcribe'
    input_tokens: int
    output_tokens: int
    cost_usd: float


@dataclass(frozen=True)
class Completion:
    """A text/structured completion plus its usage."""

    text: str
    usage: Usage


@dataclass(frozen=True)
class Embedding:
    """An embedding vector, its dimension, and its usage."""

    vector: list[float]
    dim: int
    usage: Usage


class AIProvider(ABC):
    """Contract every language-model provider must implement (ADR-012 D4)."""

    @abstractmethod
    async def complete(self, prompt: str, *, schema: dict | None = None) -> Completion:
        """Complete/structure text. ``schema`` requests typed JSON output."""

    async def complete_text(self, prompt: str) -> Completion:
        """Free-form (plain text) completion, e.g. a grounded RAG answer.

        ``complete`` is JSON-mode by contract (structured extraction); answers
        meant for a human must NOT go through it, or the user sees raw JSON.
        Providers override this; the default refuses loudly rather than
        silently returning JSON.
        """
        raise NotImplementedError(
            f"{type(self).__name__} does not implement complete_text"
        )

    @abstractmethod
    async def embed(self, text: str) -> Embedding:
        """Return an embedding for the text. ``dim`` is provider-specific (D-008)."""

    @abstractmethod
    async def transcribe(
        self,
        audio_bytes: bytes,
        content_type: str,
        *,
        duration_s: float | None = None,
    ) -> Completion:
        """Transcribe speech to text (voice notes, ADR-021).

        ``duration_s`` (when the client knows it) lets per-minute-billed models
        attribute an accurate cost. The returned ``Completion.text`` is the
        transcript (may be empty when nothing intelligible was said).
        """
