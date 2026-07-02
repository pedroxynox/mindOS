-- mindOS auth hardening (R-002) — rotating refresh-token ledger.
--
-- Backs single-use refresh-token rotation with theft detection: every refresh
-- token belongs to a `family` (one login session), only its HASH is stored
-- (never the token itself), and presenting an already-revoked token revokes the
-- entire family. See apps/api/src/auth/auth.service.ts and design notes in
-- prisma/schema.prisma (model RefreshToken).
--
-- Generated to mirror `prisma migrate diff` output for the RefreshToken model.
-- NOT APPLIED in this change: no live Postgres is available in the environment,
-- so this file is authored for review and later `prisma migrate deploy`.
--
-- SECURITY BOUNDARY — intentionally NO Row Level Security on this table.
--   RLS on the graph tables filters by `app.current_user_id`, a value derived
--   from a validated ACCESS token. Authentication (login / refresh / logout) is
--   the identity frontier: it runs BEFORE any user context exists and exists
--   precisely to establish it, so it cannot depend on `app.current_user_id`.
--   Isolation here comes from the opaque, high-entropy token + its stored hash
--   and explicit `user_id` scoping in every query, not from row-level security.
--   Consequently this table is reached by the migration/owner role and by the
--   app role without an RLS policy; the app role is granted minimal DML below.

-- CreateTable
CREATE TABLE "refresh_tokens" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "token_hash" TEXT NOT NULL,
    "family" UUID NOT NULL,
    "expires_at" TIMESTAMPTZ(6) NOT NULL,
    "revoked" BOOLEAN NOT NULL DEFAULT false,
    "replaced_by_id" UUID,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "refresh_tokens_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "refresh_tokens_token_hash_key" ON "refresh_tokens"("token_hash");

-- CreateIndex
CREATE INDEX "idx_refresh_tokens_user" ON "refresh_tokens"("user_id");

-- CreateIndex
CREATE INDEX "idx_refresh_tokens_family" ON "refresh_tokens"("family");

-- AddForeignKey
ALTER TABLE "refresh_tokens" ADD CONSTRAINT "refresh_tokens_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- ---------------------------------------------------------------------------
-- App-role grants. Consistent with the RLS migration (20260702010100), the
-- application connects as the non-owner, non-superuser role `mindos_app`. That
-- role needs DML on this table to persist, rotate and revoke refresh tokens.
-- No RLS policy is created here (see the security-boundary note above).
-- ---------------------------------------------------------------------------
GRANT SELECT, INSERT, UPDATE, DELETE ON "refresh_tokens" TO "mindos_app";
