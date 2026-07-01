"""Abstract AIProvider interface (ADR-09).

Concrete implementations (OpenAI, Anthropic, ...) are added in F2. Defining the
contract now keeps the domain decoupled from any single vendor from day one.
"""

from abc import ABC, abstractmethod


class AIProvider(ABC):
    """Contract every language-model provider must implement."""

    @abstractmethod
    async def complete(self, prompt: str) -> str:
        """Return a text completion for the given prompt."""

    @abstractmethod
    async def embed(self, text: str) -> list[float]:
        """Return an embedding vector for the given text."""
