"""Provider selection by configuration (design §7).

The domain never imports a concrete provider directly; it asks the factory for
one based on ``settings.llm_provider``. An unknown value fails loudly.
"""

from app.config import Settings
from app.providers.base import AIProvider
from app.providers.fake_provider import FakeProvider


def build_provider(settings: Settings) -> AIProvider:
    """Return the configured :class:`AIProvider`.

    - ``"fake"`` (default): deterministic, offline, zero-cost — tests/eval.
    - ``"openai"``: real OpenAI-backed provider (needs ``OPENAI_API_KEY``).
    - ``"groq"``: free OpenAI-compatible provider (needs ``GROQ_API_KEY``).
    - ``"gemini"``: free OpenAI-compatible provider (needs ``GEMINI_API_KEY``).
    - anything else: :class:`ValueError` with a clear message.
    """
    match settings.llm_provider:
        case "fake":
            return FakeProvider()
        case "openai":
            # Imported lazily so offline runs don't require the 'openai' dep.
            from app.providers.openai_provider import OpenAIProvider

            return OpenAIProvider(settings)
        case "groq":
            # Imported lazily so offline runs don't require the 'openai' dep.
            from app.providers.groq_provider import GroqProvider

            return GroqProvider(settings)
        case "gemini":
            # Imported lazily so offline runs don't require the 'openai' dep.
            from app.providers.gemini_provider import GeminiProvider

            return GeminiProvider(settings)
        case other:
            raise ValueError(
                f"unknown LLM provider: {other!r} "
                "(expected 'fake', 'openai', 'groq' or 'gemini')"
            )
