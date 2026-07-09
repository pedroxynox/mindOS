#!/bin/sh
# Container start for the mindOS API.
#
# Runs Prisma migrations as the Neon OWNER role (scoped to just the migrate
# command, so it does NOT leak into the app), then starts the API with its own
# env DATABASE_URL (the non-owner `mindos_app` role for RLS). The migration
# creates the tables, RLS policies, the `mindos_app` role and the pgvector
# extension. `prisma migrate deploy` is idempotent — safe to re-run on every
# start/wake. Kept as a script (not an inline render.yaml command) so there is
# no shell-quoting ambiguity across platforms.
set -e

if [ -n "$MIGRATION_DATABASE_URL" ]; then
  echo "[entrypoint] applying database migrations (prisma migrate deploy)..."
  DATABASE_URL="$MIGRATION_DATABASE_URL" npx prisma migrate deploy
else
  echo "[entrypoint] MIGRATION_DATABASE_URL not set; skipping migrations."
fi

echo "[entrypoint] starting API..."
exec node dist/main
