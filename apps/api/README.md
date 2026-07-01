# mindOS — API (NestJS)

Business backend: authentication (JWT, built in-house), knowledge graph
(Prisma + PostgreSQL), and realtime (WebSocket). See
[ADR-010](../../docs/02-architecture/adr/ADR-010-final-stack-and-two-backends.md)
for the responsibility boundary with the Python AI service.

## Requirements
- Node.js 22+
- PostgreSQL and Redis (see `infra/docker-compose.yml`)

## Setup
```bash
cp .env.example .env
npm install
npm run prisma:generate
npm run start:dev
```

## Health check
```
GET http://localhost:3000/v1/health
→ { "status": "ok", "service": "api", "timestamp": "..." }
```

## Scripts
- `npm run start:dev` — dev server with watch
- `npm run build` — production build
- `npm run lint` — ESLint
- `npm test` — unit tests
