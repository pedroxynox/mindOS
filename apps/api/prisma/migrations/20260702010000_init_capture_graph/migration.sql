-- mindOS F1 (capture-engine) — baseline structural migration.
--
-- Introduces the property-graph tables (nodes / edges) and the idempotency
-- ledger, and (re)creates the identity table `users`. Per the CPTO decision,
-- ALL primary/foreign keys use native UUID columns (gen_random_uuid()) so that
-- graph FKs and the RLS policy `= current_setting('app.current_user_id')::uuid`
-- work without per-row text->uuid casts. See design.md §5.
--
-- Generated with: prisma migrate diff --from-empty
--   --to-schema-datamodel prisma/schema.prisma --script
--
-- NOTE: `gen_random_uuid()` requires the `pgcrypto` extension (bundled with
-- PostgreSQL 13+ core as of pgcrypto/pg_catalog). Ensure it is available.
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- CreateEnum
CREATE TYPE "node_type" AS ENUM ('capture', 'note', 'task', 'person', 'project', 'event', 'decision', 'topic');

-- CreateEnum
CREATE TYPE "capture_status" AS ENUM ('raw', 'processing', 'processed', 'failed');

-- CreateEnum
CREATE TYPE "capture_modality" AS ENUM ('text', 'voice');

-- CreateEnum
CREATE TYPE "node_origin" AS ENUM ('manual_text', 'voice', 'calendar_sync', 'ai');

-- CreateTable
CREATE TABLE "users" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "email" TEXT NOT NULL,
    "password_hash" TEXT NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "users_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "nodes" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "type" "node_type" NOT NULL,
    "title" TEXT,
    "body" TEXT,
    "attributes" JSONB NOT NULL DEFAULT '{}',
    "status" "capture_status" NOT NULL DEFAULT 'raw',
    "origin" "node_origin" NOT NULL,
    "confidence" DOUBLE PRECISION,
    "occurred_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL,
    "deleted_at" TIMESTAMPTZ(6),

    CONSTRAINT "nodes_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "edges" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "type" TEXT NOT NULL,
    "source_node_id" UUID NOT NULL,
    "target_node_id" UUID NOT NULL,
    "confidence" DOUBLE PRECISION,
    "origin" TEXT NOT NULL,
    "user_confirmed" BOOLEAN NOT NULL DEFAULT false,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "deleted_at" TIMESTAMPTZ(6),

    CONSTRAINT "edges_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "idempotency_keys" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "key" TEXT NOT NULL,
    "capture_id" UUID NOT NULL,
    "request_hash" TEXT NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "idempotency_keys_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "users_email_key" ON "users"("email");

-- CreateIndex
CREATE INDEX "idx_nodes_user_type" ON "nodes"("user_id", "type");

-- CreateIndex
CREATE INDEX "nodes_user_id_status_idx" ON "nodes"("user_id", "status");

-- CreateIndex
CREATE INDEX "idx_edges_source" ON "edges"("user_id", "source_node_id");

-- CreateIndex
CREATE INDEX "idx_edges_target" ON "edges"("user_id", "target_node_id");

-- CreateIndex
CREATE UNIQUE INDEX "idempotency_keys_user_id_key_key" ON "idempotency_keys"("user_id", "key");

-- AddForeignKey
ALTER TABLE "nodes" ADD CONSTRAINT "nodes_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "edges" ADD CONSTRAINT "edges_source_node_id_fkey" FOREIGN KEY ("source_node_id") REFERENCES "nodes"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "edges" ADD CONSTRAINT "edges_target_node_id_fkey" FOREIGN KEY ("target_node_id") REFERENCES "nodes"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "edges" ADD CONSTRAINT "edges_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "idempotency_keys" ADD CONSTRAINT "idempotency_keys_capture_id_fkey" FOREIGN KEY ("capture_id") REFERENCES "nodes"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "idempotency_keys" ADD CONSTRAINT "idempotency_keys_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

