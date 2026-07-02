-- mindOS F1 (capture-engine) — Row Level Security (fail-closed) + app role.
--
-- Second line of defense (#03 §6 / design.md §6): even though the application
-- layer always filters by user_id, PostgreSQL guarantees per-user isolation
-- even if an application bug forgets to. This migration runs AFTER the baseline
-- structural migration and must be executed by the table OWNER / migration role.

-- ---------------------------------------------------------------------------
-- 1) Enable + FORCE Row Level Security on the graph tables.
--    FORCE makes RLS apply even to the table owner (strong defense). It does NOT
--    apply to superusers or to BYPASSRLS roles, which is exactly why the app
--    must connect as a non-owner, non-superuser role (see section 3 below).
-- ---------------------------------------------------------------------------
ALTER TABLE "nodes"            ENABLE ROW LEVEL SECURITY;
ALTER TABLE "edges"            ENABLE ROW LEVEL SECURITY;
ALTER TABLE "idempotency_keys" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "nodes"            FORCE ROW LEVEL SECURITY;
ALTER TABLE "edges"            FORCE ROW LEVEL SECURITY;
ALTER TABLE "idempotency_keys" FORCE ROW LEVEL SECURITY;

-- ---------------------------------------------------------------------------
-- 2) Isolation policies: only rows of the session's current user are visible
--    or writable.
--      USING      -> filters reads / the pre-image of UPDATE and DELETE.
--      WITH CHECK -> rejects INSERT/UPDATE that would write a row for another user.
--
--    current_setting('app.current_user_id', true) returns NULL (instead of
--    raising) when the setting is not set. `user_id = NULL` is never true, so a
--    request without a user context can neither read nor write ANY row.
--    => fail-closed (design.md §6, requirement R4.5, properties P1 / P8).
-- ---------------------------------------------------------------------------
CREATE POLICY "nodes_isolation" ON "nodes"
    USING      ("user_id" = current_setting('app.current_user_id', true)::uuid)
    WITH CHECK ("user_id" = current_setting('app.current_user_id', true)::uuid);

CREATE POLICY "edges_isolation" ON "edges"
    USING      ("user_id" = current_setting('app.current_user_id', true)::uuid)
    WITH CHECK ("user_id" = current_setting('app.current_user_id', true)::uuid);

CREATE POLICY "idem_isolation" ON "idempotency_keys"
    USING      ("user_id" = current_setting('app.current_user_id', true)::uuid)
    WITH CHECK ("user_id" = current_setting('app.current_user_id', true)::uuid);

-- ---------------------------------------------------------------------------
-- 3) Application role: NON-superuser and NON-owner of the tables, so FORCE RLS
--    always applies to it. It receives only the minimal DML grants on the graph
--    tables. The migration/owner role keeps DDL ownership.
--
--    This block is idempotent and safe to run in provisioning. Adjust the
--    password out-of-band (do not commit real secrets). The app connects with
--    this role via DATABASE_URL (see .env.example); migrations use the owner via
--    MIGRATION_DATABASE_URL.
-- ---------------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'mindos_app') THEN
        -- NOSUPERUSER + NOBYPASSRLS are the defaults but stated explicitly for intent.
        CREATE ROLE "mindos_app" LOGIN PASSWORD 'mindos_app' NOSUPERUSER NOBYPASSRLS;
    END IF;
END
$$;

-- Allow the app role to reach the schema and the (owner-created) sequences/types.
GRANT USAGE ON SCHEMA "public" TO "mindos_app";

-- Minimal DML on the graph tables (no DDL, no ownership).
GRANT SELECT, INSERT, UPDATE, DELETE ON "nodes"            TO "mindos_app";
GRANT SELECT, INSERT, UPDATE, DELETE ON "edges"            TO "mindos_app";
GRANT SELECT, INSERT, UPDATE, DELETE ON "idempotency_keys" TO "mindos_app";
-- The app also authenticates against users (read) and creates accounts (insert).
GRANT SELECT, INSERT, UPDATE ON "users" TO "mindos_app";
