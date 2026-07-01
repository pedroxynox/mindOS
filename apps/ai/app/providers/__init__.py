"""Provider-agnostic AI layer (ADR-09).

All access to language models goes through the AIProvider interface so the
concrete provider (OpenAI, Anthropic, or a future in-house model) can be
swapped without touching domain logic.
"""

from app.providers.base import AIProvider

__all__ = ["AIProvider"]
