-- mindOS integration TEST stack — Postgres init (runs once on an empty volume).
--
-- Mounted at /docker-entrypoint-initdb.d/ by infra/docker-compose.test.yml, so
-- it executes as the superuser `mindos` right after the cluster is created and
-- BEFORE any migration runs.
--
-- Purpose: guarantee the non-owner application role `mindos_app` exists early,
-- independently of migration order. The F1 RLS migration
-- (prisma/migrations/20260702010100_rls_fail_closed/migration.sql) also creates
-- this role with `IF NOT EXISTS`, so running both is safe and idempotent — this
-- script just removes the "role must exist first" ordering assumption for the
-- RLS integration tests, which connect as `mindos_app` (see .env.example
-- DATABASE_URL) to observe FORCE ROW LEVEL SECURITY for real.
--
-- NOTE: the actual table GRANTs for `mindos_app` (SELECT/INSERT/UPDATE/DELETE on
-- nodes/edges/idempotency_keys/users) are applied by the RLS migration AFTER the
-- tables exist. This file only provisions the role + password + schema usage.

-- pgcrypto backs gen_random_uuid() (also created by the first migration).
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'mindos_app') THEN
        -- NOSUPERUSER + NOBYPASSRLS are defaults, stated explicitly for intent:
        -- FORCE RLS only applies to roles that are neither owner nor superuser.
        CREATE ROLE "mindos_app" LOGIN PASSWORD 'mindos_app' NOSUPERUSER NOBYPASSRLS;
    END IF;
END
$$;

-- Let the app role reach the schema; table-level DML grants come from the
-- RLS migration once the tables have been created by the owner.
GRANT USAGE ON SCHEMA "public" TO "mindos_app";
