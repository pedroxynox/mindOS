# mindOS — AI Service (Python + FastAPI)

Comprehension worker, embeddings and RAG. It owns the language-model
integration behind the provider-agnostic `AIProvider` layer (ADR-007). See
[ADR-010](../../docs/02-architecture/adr/ADR-010-final-stack-and-two-backends.md)
for the responsibility boundary with the NestJS API.

## What runs here
- **`GET /health`**: liveness.
- **`POST /internal/query`**: RAG. It embeds the question, retrieves the top-N
  processed captures by vector similarity under RLS, and answers only from them,
  citing `[n]`. It is called by the API only and guarded by
  `x-internal-token: QUERY_INTERNAL_SECRET`. The guard is fail-closed: a missing
  secret returns 503 and a bad token returns 401.
- **Comprehension worker** (BullMQ consumer of the `understanding` queue,
  ADR-019). It starts with the app when `WORKER_ENABLED=true`. The pipeline is
  `app/understanding/`: load capture → extract (prompt **v8**) → embed →
  enrichment plan → one RLS transaction writing nodes, edges, embedding and
  `llm_usage`.
- **Providers** (`LLM_PROVIDER`): `fake` (offline, default), `openai`
  (production: `gpt-5.4-mini` + `text-embedding-3-small`), `groq` and `gemini`.
  **Only OpenAI implements embeddings**, so the worker and RAG need `openai`.

## Requirements
- Python 3.11+

## Setup
```bash
cp .env.example .env
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.lock && pip install -e . --no-deps   # same as CI
uvicorn app.main:app --reload --port 8000
```
To run the worker locally, set `WORKER_ENABLED=true`, a `DATABASE_URL` using the
non-owner app role and a `REDIS_URL`.

## Quality
- `ruff check .`: lint (line length 88)
- `mypy app`: strict type check
- `pytest`: tests. Integration tests skip without infra.

## Evaluation (comprehension gate, ADR-018)
- `python -m app.eval.run_eval`: offline baseline with `fake`.
- `python -m app.eval.run_eval --provider openai --gate`: real run.
- Gate thresholds: entities F1 ≥ 0.80, task precision ≥ 0.85, hallucination
  ≤ 0.10, cost ≤ $0.01 per capture.
- Details: [EVAL.md](./EVAL.md) and
  [HOW_TO_RUN_THE_AI_EXAM](../../docs/HOW_TO_RUN_THE_AI_EXAM.md). It also runs
  from GitHub Actions (`f2-eval.yml`, manual).
