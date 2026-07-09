# mindOS AI service (Python + FastAPI)
FROM python:3.11-slim AS runner
WORKDIR /app

ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

COPY pyproject.toml ./
# Install the base service PLUS the 'worker' extra (asyncpg + bullmq) so the
# same image can also run the comprehension worker (WORKER_ENABLED=true) and
# drain the 'understanding' queue. The worker extra is lean on purpose (no
# langgraph/llama-index), keeping the image small.
RUN pip install --upgrade pip && pip install ".[worker]"

COPY app ./app

EXPOSE 8000
# Render provides $PORT; default to 8000 locally. uvicorn binds all interfaces.
CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}"]
