"""Understanding bounded context (F2 — comprehension engine).

Contains the pure comprehension core (``extract``, ``text_utils``,
``enrichment``) plus the write path that turns a capture into an enriched graph:
the job ``contract`` (mirror of F1), the ``GraphStore`` port with an in-memory
and a Postgres (``graph_writer``) adapter, the RLS transaction helper (``rls``),
per-user ``cost_meter``, the ``pipeline`` orchestration, and the BullMQ
``worker`` (ADR-019).

The pure core + the in-memory store run with zero infrastructure; the Postgres
and BullMQ adapters (asyncpg / bullmq) are optional deps exercised only against
real Redis/Postgres.
"""
