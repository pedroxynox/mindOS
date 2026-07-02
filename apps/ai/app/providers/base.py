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

    @abstractmethod
    async def embed(self, text: str) -> Embedding:
        """Return an embedding for the text. ``dim`` is provider-specific (D-008)."""

    @abstractmethod
    async def transcribe(self, audio_bytes: bytes, content_type: str) -> Completion:
        """Transcribe speech to text.

        Declared for contract completeness (used when a voice capture has no
        ``body``). The comprehension PoC does not exercise this path.
        """
