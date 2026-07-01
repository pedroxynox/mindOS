# mindOS — AI Service (Python + FastAPI)

Understanding pipeline, embeddings and RAG. Owns the language-model integration
behind the provider-agnostic `AIProvider` layer (ADR-09). See
[ADR-010](../../docs/02-architecture/adr/ADR-010-final-stack-and-two-backends.md)
for the responsibility boundary with the NestJS API.

## Requirements
- Python 3.11+

## Setup
```bash
cp .env.example .env
python -m venv .venv && source .venv/bin/activate
pip install -e ".[dev]"
uvicorn app.main:app --reload --port 8000
```

## Health check
```
GET http://localhost:8000/health
→ { "status": "ok", "service": "ai", "version": "...", "timestamp": "..." }
```

## Quality
- `ruff check .` — lint
- `mypy app` — type check
- `pytest` — tests
