"""mindOS AI service — FastAPI entrypoint (F0).

Exposes only a health check in F0. The understanding pipeline (LangGraph),
embeddings and RAG (LlamaIndex) are added in F2, behind the provider-agnostic
AIProvider layer (ADR-09).
"""

from datetime import datetime, timezone
from typing import Literal

from fastapi import FastAPI
from pydantic import BaseModel

from app import __version__

app = FastAPI(title="mindOS AI Service", version=__version__)


class HealthStatus(BaseModel):
    """Response model for the liveness endpoint."""

    status: Literal["ok"]
    service: Literal["ai"]
    version: str
    timestamp: str


@app.get("/health", response_model=HealthStatus)
def health() -> HealthStatus:
    """Liveness endpoint. Confirms the AI service process is up."""
    return HealthStatus(
        status="ok",
        service="ai",
        version=__version__,
        timestamp=datetime.now(timezone.utc).isoformat(),
    )
