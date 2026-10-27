-- mindOS mejoras-v2 PR B — per-user timezone and currency (D-013 / D-014).
--
-- `timezone` is an IANA zone ("America/Mexico_City"); every "today" the API
-- computes (briefing, finance buckets, habit check-ins/streaks) uses it, so
-- LatAm users no longer see their day roll over at 18:00-21:00 local (UTC).
-- `currency` is an ISO-4217 code; NULL means "not chosen yet" (the effective
-- currency is then USD and the app proposes one from the device locale).
--
-- `users` has no RLS (identity frontier, see the F1 RLS migration); the app
-- role already holds SELECT/INSERT/UPDATE on it, which covers these columns.
ALTER TABLE "users" ADD COLUMN IF NOT EXISTS "timezone" TEXT NOT NULL DEFAULT 'UTC';
ALTER TABLE "users" ADD COLUMN IF NOT EXISTS "currency" TEXT;
