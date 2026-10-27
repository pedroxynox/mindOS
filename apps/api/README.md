# mindOS — API (NestJS)

Business backend: in-house JWT auth, capture (idempotent, offline-first
friendly), the knowledge graph (Prisma + PostgreSQL with fail-closed RLS),
briefing, the RAG query proxy, and the tasks, growth and finance modules. See
[ADR-010](../../docs/02-architecture/adr/ADR-010-final-stack-and-two-backends.md)
for the responsibility boundary with the Python AI service. Contracts are in
[#04 §5.0](../../docs/04-api/api-design-specification.md).

## Requirements
- Node.js 22+
- PostgreSQL 16 with pgvector, and Redis 7 (see `infra/docker-compose.yml`)

## Setup
```bash
cp .env.example .env
npm ci
npx prisma generate
DATABASE_URL=$MIGRATION_DATABASE_URL npx prisma migrate deploy   # owner role
npm run start:dev
```

The app must connect as the **non-owner** role `mindos_app` (`DATABASE_URL`) so
RLS applies. Migrations run with the owner role (`MIGRATION_DATABASE_URL`). In
production, `docker-entrypoint.sh` runs `prisma migrate deploy` on start.

## Modules (all under `/v1`, JWT unless noted)
| Module | Routes |
|--------|--------|
| health | `GET /health` (public) |
| auth | `POST /auth/register`, `/auth/login`, `/auth/refresh`, `/auth/logout` (public, 5 req/min) |
| capture | `POST /captures` (202, `Idempotency-Key`), `POST /captures/audio-upload`, `GET /captures`, `GET /captures/:id` |
| graph | `GET /graph/summary`, `GET /graph/nodes?type=`, `GET /graph/captures/:id/entities` |
| briefing | `GET /briefing` |
| query | `POST /query` (proxies to the AI service `/internal/query` with `QUERY_INTERNAL_SECRET`) |
| tasks | `GET /tasks`, `POST /tasks`, `PATCH /tasks/:id` |
| growth | `GET/POST /growth/goals`, `PATCH /growth/goals/:id`, `GET/POST /growth/habits`, `POST /growth/habits/:id/check`, `GET/POST /growth/reflections` |
| finance | `GET /finance/summary`, `POST /finance/expenses` |

Background jobs: `ReconciliationService` re-enqueues stuck `raw` captures and
`BlobJanitorService` purges orphan audio blobs.

## Scripts
- `npm run start:dev`: dev server with watch
- `npm run build`: production build
- `npm run lint`: ESLint
- `npm test`: unit tests (offline)
- `npm run test:integration`: integration tests against real Postgres, Redis
  and MinIO (see [TESTING.md](./TESTING.md))
