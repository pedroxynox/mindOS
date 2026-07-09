-- mindOS F2 (comprehension-engine) — pgvector, per-user LLM cost, and the
-- idempotency indexes that back the GraphWriter.
--
-- Runs AFTER the F1 baseline + RLS migrations and must be executed by the table
-- OWNER / migration role (it creates an extension, alters `nodes`, and creates a
-- new table with its own RLS policy). The application connects as the non-owner
-- `mindos_app` role, so FORCE ROW LEVEL SECURITY keeps applying (F1 §6).
--
-- Prisma does not natively type pgvector, so the embedding column and its HNSW
-- index are added here as raw SQL (design comprehension §5). The Python worker
-- reads/writes this column with raw SQL; the Prisma schema stays the contract of
-- record for every other column.

-- ---------------------------------------------------------------------------
-- 1) pgvector extension (idempotent). Requires the `vector` extension to be
--    available in the PostgreSQL image (pgvector). Provisioning must install it.
-- ---------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS "vector";

-- ---------------------------------------------------------------------------
-- 2) Embedding column on `nodes`. The DIMENSION must match
--    Settings.embedding_dim (app/config.py, default 1536 = OpenAI
--    text-embedding-3-small). Changing it later requires a re-embed + reindex,
--    so it is fixed deliberately (D-008). `embedding_model` records which model
--    produced the vector, for traceability and future model migrations.
-- ---------------------------------------------------------------------------
ALTER TABLE "nodes" ADD COLUMN IF NOT EXISTS "embedding" vector(1536);
ALTER TABLE "nodes" ADD COLUMN IF NOT EXISTS "embedding_model" TEXT;

-- ---------------------------------------------------------------------------
-- 3) ANN index (HNSW, cosine distance). Partial: only rows that have an
--    embedding. Isolation is still enforced by the `nodes` RLS policy at query
--    time (F1 §6); this index only accelerates the nearest-neighbour search that
--    F3 (retrieval) will run inside withUser(user_id).
-- ---------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS "idx_nodes_embedding_hnsw"
    ON "nodes" USING hnsw ("embedding" vector_cosine_ops)
    WITH (m = 16, ef_construction = 64)
    WHERE "embedding" IS NOT NULL;

-- ---------------------------------------------------------------------------
-- 4) Idempotency indexes backing the GraphWriter (design comprehension §8.3).
--    - nodes: one AI-derived node per (user, dedup_key). dedup_key is a
--      deterministic hash of (user_id, capture_id, type, normalized_label)
--      stored in attributes->>'dedup_key'. Partial to origin='ai' so it never
--      constrains user/integration nodes.
--    - edges: one AI-derived edge per (user, source, target, type). Partial to
--      origin='ai' for the same reason.
--    Reprocessing the same capture hits ON CONFLICT DO NOTHING -> no duplicates
--    (P-COMP-2 / P-COMP-3).
-- ---------------------------------------------------------------------------
CREATE UNIQUE INDEX IF NOT EXISTS "uq_nodes_ai_dedup_key"
    ON "nodes" ("user_id", (("attributes" ->> 'dedup_key')))
    WHERE "origin" = 'ai';

CREATE UNIQUE INDEX IF NOT EXISTS "uq_edges_ai_src_tgt_type"
    ON "edges" ("user_id", "source_node_id", "target_node_id", "type")
    WHERE "origin" = 'ai';

-- ---------------------------------------------------------------------------
-- 5) Per-user LLM cost (first-class metric, #02). Every model call is recorded
--    here, attributed to the job's user, under the same fail-closed RLS pattern
--    as the graph tables.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS "llm_usage" (
    "id"            UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id"       UUID NOT NULL,
    "capture_id"    UUID,
    "provider"      TEXT NOT NULL,          -- 'openai' | 'groq' | 'gemini' | ...
    "model"         TEXT NOT NULL,
    "operation"     TEXT NOT NULL,          -- 'complete' | 'embed' | 'transcribe'
    "input_tokens"  INTEGER NOT NULL DEFAULT 0,
    "output_tokens" INTEGER NOT NULL DEFAULT 0,
    "cost_usd"      NUMERIC(12,6) NOT NULL DEFAULT 0,
    "created_at"    TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "llm_usage_pkey" PRIMARY KEY ("id")
);

-- capture_id points at the source capture node; keep the row if the node is
-- deleted (cost history is audit data), matching the design (ON DELETE SET NULL).
ALTER TABLE "llm_usage" ADD CONSTRAINT "llm_usage_user_id_fkey"
    FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "llm_usage" ADD CONSTRAINT "llm_usage_capture_id_fkey"
    FOREIGN KEY ("capture_id") REFERENCES "nodes"("id") ON DELETE SET NULL ON UPDATE CASCADE;

CREATE INDEX IF NOT EXISTS "idx_llm_usage_user" ON "llm_usage" ("user_id", "created_at");

-- RLS fail-closed on llm_usage (same pattern as the graph tables, F1 §6).
ALTER TABLE "llm_usage" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "llm_usage" FORCE  ROW LEVEL SECURITY;

CREATE POLICY "llm_usage_isolation" ON "llm_usage"
    USING      ("user_id" = current_setting('app.current_user_id', true)::uuid)
    WITH CHECK ("user_id" = current_setting('app.current_user_id', true)::uuid);

-- ---------------------------------------------------------------------------
-- 6) Grant the app role minimal DML on the new table (no DDL, no ownership),
--    matching the F1 grants. The worker inserts cost rows as `mindos_app`.
-- ---------------------------------------------------------------------------
GRANT SELECT, INSERT ON "llm_usage" TO "mindos_app";
