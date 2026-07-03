"""Application configuration for the mindOS AI service."""

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Environment-driven settings.

    Values are loaded from environment variables (and a local .env file in
    development). See .env.example for the full list.
    """

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    port: int = 8000

    # Data stores (see infra/docker-compose.yml).
    database_url: str = "postgresql://mindos:mindos@localhost:5432/mindos"
    redis_url: str = "redis://localhost:6379"

    # LLM provider selection (provider-agnostic layer, ADR-09 / ADR-012 D4).
    # 'fake' is the default so the comprehension PoC and its evaluation harness
    # run fully offline with zero cost. Set to 'openai' for a real (paid) run,
    # or 'groq'/'gemini' for a free (no credit card) OpenAI-compatible run.
    llm_provider: str = "fake"

    # OpenAI provider (only required when llm_provider = 'openai').
    openai_api_key: str | None = None
    openai_model: str = "gpt-4o-mini"
    openai_embedding_model: str = "text-embedding-3-small"

    # Groq provider (only required when llm_provider = 'groq'). Groq exposes an
    # OpenAI-compatible API, so it reuses the same client and the resilience
    # settings below. Get a free key (no card) at https://console.groq.com.
    # If Groq deprecates the default model, override it with GROQ_MODEL without
    # any code change (see https://console.groq.com/docs/models).
    groq_api_key: str | None = None
    groq_model: str = "llama-3.3-70b-versatile"

    # Gemini provider (only required when llm_provider = 'gemini'). Google
    # exposes an OpenAI-compatible endpoint for its Gemini models, so it reuses
    # the same client and the resilience settings below. Get a free key (no
    # credit card) at https://aistudio.google.com/app/apikey. Gemini's free tier
    # is notably more generous than Groq's (~15 req/min, ~1M tokens/min). If the
    # default model is deprecated, override it with GEMINI_MODEL without any code
    # change (see https://ai.google.dev/gemini-api/docs/models).
    # Default is gemini-1.5-flash because it has a much more generous free DAILY
    # request quota (~1500 req/day) than gemini-2.0-flash (~200 req/day), so the
    # ~45-call F2 exam completes on the free tier without exhausting the daily
    # cap. Override without code via the GEMINI_MODEL repo Variable.
    gemini_api_key: str | None = None
    gemini_model: str = "gemini-1.5-flash"

    # Resilience against transient failures / rate limits (HTTP 429). Applied
    # by OpenAIProvider around every API call: exponential backoff + jitter,
    # honouring a server-provided ``Retry-After`` header. Defaults are sensible
    # for a fresh account with a low requests-per-minute allowance.
    openai_max_retries: int = 5
    openai_backoff_base_s: float = 2.0

    # --- Evaluation gate thresholds (design §13.2) ---------------------------
    # PROVISIONAL values, pending ratification by the product owner. They are
    # the acceptance gate that de-risks R-001 before building the full pipeline.
    eval_f1_entities_min: float = 0.80
    eval_task_precision_min: float = 0.85
    eval_hallucination_max: float = 0.05
    # Average cost budget per capture in USD (the "presupuesto acordado").
    eval_cost_per_capture_max_usd: float = 0.01

    # Delay (seconds) inserted between eval cases so a run stays under the
    # requests-per-minute limit of a fresh provider account. Keep at 0 for the
    # offline FakeProvider (no network); set a small value for real OpenAI runs.
    eval_request_delay_s: float = 0.0


settings = Settings()
