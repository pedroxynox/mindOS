-- mindOS F1 (capture-engine) — RLS hardening: empty-string context guard.
--
-- FOUND BY REAL INTEGRATION RUN (R-006): the original fail-closed policies
-- (20260702010100_rls_fail_closed) compare user_id against
--   current_setting('app.current_user_id', true)::uuid
-- relying on the setting being NULL when no user context exists (so
-- `user_id = NULL` is never true => zero rows / rejected writes => fail-closed).
--
-- That holds on a FRESH connection. But the app sets the context transaction-
-- locally (`set_config('app.current_user_id', <uuid>, true)` inside
-- PrismaRlsService.withUser). PostgreSQL, after that transaction commits, does
-- NOT reset the placeholder GUC back to NULL — it resets it to the EMPTY STRING
-- ''. Prisma uses a connection POOL, so a connection that previously served an
-- RLS request and is later reused for a query OUTSIDE withUser sees
--   current_setting('app.current_user_id', true) = ''   (not NULL)
-- and the cast ''::uuid raises `22P02 invalid input syntax for type uuid: ""`
-- instead of cleanly returning zero rows. It still does not leak data, but it
-- turns a designed "no rows" into a hard error (observed by property P8).
--
-- FIX: wrap the setting in NULLIF(..., '') so BOTH the never-set case (NULL)
-- and the reset-after-local-set case ('') collapse to NULL => the comparison is
-- never true => genuine, clean fail-closed on every pooled connection.
--
-- Idempotent-ish: policies are dropped and recreated. Must run as the table
-- OWNER / migration role (same as 20260702010100).

-- nodes
DROP POLICY IF EXISTS "nodes_isolation" ON "nodes";
CREATE POLICY "nodes_isolation" ON "nodes"
    USING      ("user_id" = NULLIF(current_setting('app.current_user_id', true), '')::uuid)
    WITH CHECK ("user_id" = NULLIF(current_setting('app.current_user_id', true), '')::uuid);

-- edges
DROP POLICY IF EXISTS "edges_isolation" ON "edges";
CREATE POLICY "edges_isolation" ON "edges"
    USING      ("user_id" = NULLIF(current_setting('app.current_user_id', true), '')::uuid)
    WITH CHECK ("user_id" = NULLIF(current_setting('app.current_user_id', true), '')::uuid);

-- idempotency_keys
DROP POLICY IF EXISTS "idem_isolation" ON "idempotency_keys";
CREATE POLICY "idem_isolation" ON "idempotency_keys"
    USING      ("user_id" = NULLIF(current_setting('app.current_user_id', true), '')::uuid)
    WITH CHECK ("user_id" = NULLIF(current_setting('app.current_user_id', true), '')::uuid);
