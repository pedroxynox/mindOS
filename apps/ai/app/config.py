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

    # LLM provider selection (provider-agnostic layer, ADR-09).
    # Concrete keys are added in F2; F0 keeps this abstract.
    llm_provider: str = "none"


settings = Settings()
