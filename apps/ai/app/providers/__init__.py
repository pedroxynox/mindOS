"""Provider-agnostic AI layer (ADR-09 / ADR-012 D4).

All access to language models goes through the AIProvider interface so the
concrete provider (OpenAI, a deterministic fake, or a future in-house model)
can be swapped without touching domain logic.
"""

from app.providers.base import AIProvider, Completion, Embedding, Usage
from app.providers.factory import build_provider
from app.providers.fake_provider import FakeProvider

__all__ = [
    "AIProvider",
    "Completion",
    "Embedding",
    "Usage",
    "FakeProvider",
    "build_provider",
]
