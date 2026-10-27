---
inclusion: always
---

# mindOS: contexto del proyecto

Mapa para retomar el trabajo sin releer todo el repo. Si algo de aquí contradice al código, manda el código: verifícalo y actualiza este fichero.

## Qué es
mindOS es una capa de inteligencia personal, no una app de notas ni de tareas. El usuario captura texto (la voz aún no funciona). La IA extrae personas, tareas, proyectos, eventos, decisiones y temas, los guarda en un grafo por usuario y devuelve valor con el dashboard "Hoy", "Conversar" (preguntas con citas, RAG), Memoria, Tasks, Growth y Finanzas. El Daily Briefing existe en la API, pero aún no se muestra.

## Cómo trabajar con el founder
- Es CEO, no programador. Háblale en español, sin tecnicismos y **súper resumido**: pocas líneas, primero la respuesta, sin tablas largas salvo que las pida. Actúa como CPTO crítico (`docs/000_SYSTEM/001` y `008`): nada de halagos y marca la firmeza de cada recomendación (🟢 firme / 🟠 opinión fuerte / ⚪ tentativa).
- Al iniciar, lee `docs/000_SYSTEM/009_CURRENT_STATE.md` (al día a 2026-10-27; §5 tiene la lista priorizada de qué sigue) y, si aplica, `012_RISK_AND_DEBT_REGISTER.md`. Revisa `git log` por si entró algo después.
- **Todo cambio por PR, con CI verde.** Tras cada push, comprueba el CI (`gh api repos/pedroxynox/mindOS/actions/runs?branch=<rama>`). En julio el CI estuvo 7 commits en rojo sin que nadie lo viera (R-008).
- Al cerrar, actualiza 009 (se sobrescribe), añade riesgos y deuda a 012 (solo se añade, nunca se borra), crea un ADR si hubo una decisión estructural y entrega el Informe Ejecutivo con el formato de `008` §3.
- No relajes umbrales ni el gold del eval para que "apruebe".
- El founder a veces mergea antes de que llegue un ajuste de seguimiento. Comprueba siempre el estado real de `main` y de los PRs.
- Si falta una herramienta (Flutter SDK, Postgres…), instálala en el sandbox antes de degradar el plan a "solo en CI".

## Monorepo (sin `packages/`, cada app con su propio gestor)
| App | Stack | Rol |
|---|---|---|
| `apps/api` | NestJS 10, Prisma 5, Postgres + pgvector, BullMQ, JWT propio, Node 22, Jest + fast-check | API pública `/v1`, lógica de negocio |
| `apps/ai` | Python 3.11, FastAPI, pydantic v2, SDK `openai`, asyncpg, bullmq; ruff + mypy estricto + pytest/hypothesis | Worker de comprensión + RAG interno |
| `apps/mobile` | Flutter (móvil + web), Riverpod 2, go_router, Drift (WASM en web), fuente Inter | Superficie principal, offline-first |
| `infra/` | docker-compose (pgvector pg16, redis 7), compose de test (+MinIO), nginx, rol `mindos_app` | Local y tests |
| `render.yaml` | Render: `mindos-api`, `mindos-ai` (worker), `mindos-web` (estático), `mindos-redis`; BD en Neon | Producción |

## Flujo principal
1. **Flutter** guarda la captura en Drift. `SyncService` hace `POST /v1/captures` con `Idempotency-Key` y recibe 202.
2. **API** (`capture.service.ts`): registro de idempotencia → nodo `type=capture,status=raw` bajo RLS → job `understanding.process` en la cola `understanding` (`jobId=capture_id`, 5 intentos). `ReconciliationService` reencola capturas atascadas en `raw` y `BlobJanitorService` limpia blobs huérfanos.
3. **IA worker** (`apps/ai/app/understanding/`, se activa con `WORKER_ENABLED=true`): `pipeline.run_understanding` → extracción LLM en JSON (prompt **v8** en `extract.py`) → `embed` → `enrichment.py` (puro) → `graph_writer.PgGraphStore` hace en una sola transacción RLS: nodos, aristas, embedding, `llm_usage` y `status=processed`.
4. **Lectura**: `/v1/graph/*`, `/v1/briefing`, `/v1/tasks`, `/v1/growth/*`, `/v1/finance/*` leen y escriben `nodes` directamente.
5. **RAG**: `POST /v1/query` (API) → `POST {AI_SERVICE_URL}/internal/query` con `x-internal-token: QUERY_INTERNAL_SECRET` (fail-closed). Hace búsqueda vectorial sobre capturas procesadas y responde citando `[n]`.

## Datos (`apps/api/prisma/schema.prisma`)
- Tablas: `users`, `refresh_tokens` (sin RLS a propósito), `nodes` (grafo de una sola tabla, enum `NodeType`: capture/note/task/person/project/event/decision/topic, `attributes` JSONB, `embedding vector(1536)` escrito desde Python), `edges`, `idempotency_keys`, `llm_usage`.
- **RLS fail-closed**: la política usa `current_setting('app.current_user_id')`. La app se conecta como `mindos_app` (no-owner) y las migraciones usan `MIGRATION_DATABASE_URL` (owner). Toda query de usuario pasa por `PrismaRlsService.withUser` (TS) o `rls_tx` (Python).
- Growth (goals/habits/reflections) y Finance (expenses) son nodos `type='note'` diferenciados por `attributes.kind`, sin tablas propias (ADR-020, con criterios de salida). Las tareas son nodos `task` con `attributes` `done`/`priority`/`due_at`/`area`; las de la IA y las manuales comparten contrato. Detalle en `docs/03-data` §5.1 y contratos reales en `docs/04-api` §5.0/§5.7.
- Cualquier cambio de esquema es una migración nueva en `apps/api/prisma/migrations/`.

## IA: providers y eval
- `AIProvider` (`complete`, `embed`, `transcribe`), con implementaciones fake, openai, groq y gemini sobre `openai_compatible.py` y `retry.py`. **Solo OpenAI tiene embeddings**: producción necesita `LLM_PROVIDER=openai` (`gpt-5.4-mini` + `text-embedding-3-small`).
- Eval (ADR-018): 45 casos gold ES/EN en `app/eval/dataset/`. Gate: F1 de entidades ≥0.80, precisión de tareas ≥0.85, alucinación ≤0.10, coste ≤$0.01 por captura. v8 da 0.890 / 1.000 / 0.074 / $0.0023 (PASS).
- Cambiar el prompt implica nueva versión en `extract.py`, ejecutar el eval y documentarlo. El workflow `f2-eval.yml` es manual.

## Comandos
- API: `cd apps/api && npm ci && npx prisma generate && npm run lint && npm test && npm run build`. Integración: `infra/docker-compose.test.yml` + `npm run migrate:test` + `npm run test:integration` (ver `apps/api/TESTING.md`).
- IA: `cd apps/ai && pip install -r requirements.lock && pip install -e . --no-deps && ruff check . && mypy app && pytest`. Eval: `python -m app.eval.run_eval [--provider openai --gate]`.
- Mobile: `cd apps/mobile && flutter create . --project-name mindos --platforms=android && flutter pub get && dart run build_runner build --delete-conflicting-outputs && flutter analyze --no-fatal-infos && flutter test` (`web/` está en git; los `.g.dart` no).
- CI (`.github/workflows/ci.yml`) repite estos pasos en cada push o PR a `main`.

## Convenciones
- Ramas `feat/ fix/ refactor/ docs/ chore/ test/`. Conventional Commits `tipo(alcance): descripción`. PRs pequeños con qué, por qué, cómo se probó y riesgos; merge squash. No hay CONTRIBUTING.md (`docs/05-engineering/engineering-standards-and-conventions.md`).
- JSON en `snake_case`. Cada archivo empieza con un comentario de propósito. Código y comentarios en inglés, docs de producto en español.
- Puertos y adaptadores (`AIProvider`, `GraphStore`, `UnderstandingQueuePort`): los tests offline usan fakes y PBT.

## App (`apps/mobile/lib/src/router.dart`)
- Rutas planas sobre Hoy (`context.push`): `/` Hoy, `/capture`, `/capture/:id/insights` ("Lo que entendí"), `/ask` (Conversar), `/memory`, `/graph/:type`, `/tasks`, `/growth`, más `/login` y `/register`.
- Finanzas solo existe como tarjeta en Hoy.
- El tema oscuro está forzado.
- Hay dos clientes HTTP: `GraphApiClient` (grafo, briefing, query) y `MindosApi` (tasks, growth, finance).

## Pendiente conocido (prioridad en 009 §5)
- **Producto:** voz (`transcribe` y `audio_loader` sin cablear; el botón está deshabilitado y falta S3 en Render), briefing visible en Hoy (la API existe y no se usa, D-016), `POST /v1/feedback`, RAG con grafo y SSE, Finanzas con IA, F4 (exportar y borrar cuenta, consentimiento, Sentry).
- **Deuda:**
  - D-012: tests de lo nuevo.
  - D-013: "hoy" en UTC.
  - D-014: moneda.
  - D-015: defectos menores (saludo, "Proyectos" que son metas, focus score, racha semanal, paginación, `camelCase` en las entradas).
  - D-016: código muerto y clientes duplicados.
  - D-005, D-006.
- **Proceso:** branch protection pendiente (R-008). Logging INFO en `mindos-ai`. F1 de conexiones 0.187 (fuera del gate).

## Skills instaladas (`.kiro/skills/`, restaurables con `skills-lock.json`)
- **superpowers** (obra): disciplina de proceso. `brainstorming` antes de construir algo nuevo, `writing-plans` → `executing-plans`, `systematic-debugging` para bugs, `test-driven-development`, `verification-before-completion` antes de decir "listo", `requesting-code-review` / `receiving-code-review`, `finishing-a-development-branch`.
- **UI** (`apps/mobile`): `impeccable` (crítica, auditoría y pulido, incluye pantallas nativas), `emil-design-eng` y la familia de Emil Kowalski (`animate`, `review-animations`, `improve-animations`, `apple-design`, `mobile-native`…), `design-taste-frontend` (Taste). Sus ejemplos son web (CSS/React): aplica los principios (curvas, duraciones, jerarquía, espaciado) traducidos a Flutter y no metas dependencias web.
- **Escritura**: `humanizer` para docs, PRs y textos para el founder.
- **caveman** (`caveman`, `ultracave`, `megacave`, `caveman-commit`, `caveman-review`, `caveman-compress`, `caveman-help`): solo cuando el usuario lo pida (`/caveman`, "modo caveman"). Por defecto, español claro para el founder.
