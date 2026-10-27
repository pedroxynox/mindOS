# mindOS

**La capa de inteligencia personal que evoluciona hasta convertirse en tu sistema operativo personal con IA.**

mindOS no es una app de tareas, ni de notas, ni una agenda. Es un motor de
contexto e inteligencia personal: comprende, recuerda, organiza, conecta y actúa
por el usuario para ayudarle a tomar mejores decisiones con menos carga mental.

## Estado del proyecto

🟢 **En producción:** `https://mindos-web.onrender.com` (Render + Neon + OpenAI, plan gratis).
- **F1 Captura** ✅: offline-first, idempotente, grafo con RLS fail-closed.
- **F2 Comprensión** ✅: gate superado (F1 0.890, alucinación 0.074, $0.0023 por captura).
- **F3 Recuperación de valor** ~70 %: "Lo que entendí", Memoria, Daily Briefing
  (API) y "Conversar" (RAG con citas).
- **Adelantados** ([ADR-020](./docs/02-architecture/adr/ADR-020-life-modules-as-note-nodes.md)):
  Tareas, Crecimiento (metas, hábitos, reflexión) y Finanzas básico.
- **Pendiente:** voz, feedback, RAG con grafo y streaming, F4 (privacidad y
  observabilidad) y F5 (beta).

> 🏛️ Gobernanza: [`docs/000_SYSTEM/`](./docs/000_SYSTEM/000_README.md). El estado
> vivo está en [009 Current State](./docs/000_SYSTEM/009_CURRENT_STATE.md) y los
> riesgos y la deuda en [012](./docs/000_SYSTEM/012_RISK_AND_DEBT_REGISTER.md).
> Resumen para el founder: [ESTADO_DEL_PROYECTO](./docs/ESTADO_DEL_PROYECTO.md).

## Arquitectura (resumen)

Dos backends ([ADR-010](./docs/02-architecture/adr/ADR-010-final-stack-and-two-backends.md))
con una sola app Flutter para móvil y web:

| App | Rol | Stack |
|-----|-----|-------|
| [`apps/mobile`](./apps/mobile) | Superficie principal (web + móvil) | Flutter · Riverpod · GoRouter · Drift (SQLite / WASM) |
| [`apps/api`](./apps/api) | Negocio: auth, captura, grafo, briefing, consulta, tareas, crecimiento, finanzas | NestJS · Prisma · PostgreSQL + pgvector · BullMQ (Redis) |
| [`apps/ai`](./apps/ai) | IA: worker de comprensión, embeddings, RAG | Python · FastAPI · OpenAI (`AIProvider` intercambiable) |

Flujo: la app captura → `POST /v1/captures` → cola → worker Python (LLM) → grafo
bajo RLS. La app lee el grafo desde la API, y "Conversar" pasa de la API a la IA
(`/internal/query`).

## Estructura del repositorio

```
mindOS/
├── docs/          # Gobernanza (000_SYSTEM) + cadena #00–#08 + ADRs
├── apps/
│   ├── mobile/    # Flutter (web + móvil)
│   ├── api/       # NestJS
│   └── ai/        # Python (FastAPI + worker + eval)
├── infra/         # docker-compose (dev y test), Nginx, rol de BD
├── render.yaml    # Blueprint de producción (Render)
├── .kiro/         # Specs, steering y skills del agente
└── .github/       # CI (ci.yml) + examen de la IA (f2-eval.yml)
```

## Arrancar en local

Requisitos: Docker, Node 22+, Python 3.11+, Flutter (stable).

```bash
# 1) Datos + backends
docker compose -f infra/docker-compose.yml up --build
curl http://localhost:3000/v1/health   # API
curl http://localhost:8000/health      # IA

# 2) App (web o móvil) apuntando a la API
cd apps/mobile
flutter create . --project-name mindos --platforms=android,ios   # web/ ya está en git
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:3000/v1
```

> ⚠ El compose de desarrollo conecta la API con el rol **owner**, que se salta
> RLS, y deja el worker apagado (`WORKER_ENABLED=false`). Para probar la
> comprensión en local, usa `LLM_PROVIDER=fake` o una clave de OpenAI (ver
> [`apps/ai/README.md`](./apps/ai/README.md)). Producción: [DEPLOY_RENDER](./docs/06-infrastructure/DEPLOY_RENDER.md).

## Calidad

CI ([`ci.yml`](./.github/workflows/ci.yml)) en cada push o PR:
- **API:** lint + tests + build.
- **IA:** ruff + mypy + pytest.
- **Mobile:** analyze + test.

Todo cambio entra **por PR con CI verde**.

## Documentación

Toda la documentación oficial vive en [`/docs`](./docs/README.md), organizada
como una cadena donde cada documento depende del anterior.

> Principio de ingeniería: *nunca programar antes de diseñar; nunca diseñar antes
> de comprender el problema; nunca implementar sin documentación previa.*
