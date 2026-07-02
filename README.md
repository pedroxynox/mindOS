# mindOS

**La capa de inteligencia personal que evoluciona hasta convertirse en tu sistema operativo personal con IA.**

mindOS no es una app de tareas, ni de notas, ni una agenda. Es un motor de
contexto e inteligencia personal: comprende, recuerda, organiza, conecta y actúa
por el usuario para ayudarle a tomar mejores decisiones con menos carga mental.

## Estado del proyecto

🟢 **Fundación documental completa (#00–#08).**
🏗️ **Fase F0 — Cimientos técnicos: ~70 %.** El esqueleto del monorepo (3 apps +
Docker + CI verde) existe, pero **F0 aún no cumple su Definición de Hecho** del
[roadmap #08](./docs/08-roadmap/technical-roadmap.md): faltan **CD a staging** e
**IaC** para el entorno de staging.
🔐 **Autenticación (F1a):** implementada a nivel funcional (registro/login/refresh
con JWT), pero **sin endurecer** (pendiente rate limiting, rotación de refresh y
protección contra enumeración) — ver el registro de deuda.

> 🏛️ Gobernanza: el proyecto se rige por la capa
> [`docs/000_SYSTEM/`](./docs/000_SYSTEM/000_README.md), que gobierna toda la
> cadena documental y el código. El estado vivo y los riesgos/deuda se mantienen
> en [Current State](./docs/000_SYSTEM/009_CURRENT_STATE.md) y en el
> [Risk & Debt Register](./docs/000_SYSTEM/012_RISK_AND_DEBT_REGISTER.md).

## Arquitectura (resumen)

Sistema mobile-first con dos backends (ver
[ADR-010](./docs/02-architecture/adr/ADR-010-final-stack-and-two-backends.md)):

| App | Rol | Stack |
|-----|-----|-------|
| [`apps/mobile`](./apps/mobile) | Superficie principal (móvil) | Flutter · Riverpod · GoRouter · Drift · Material 3 |
| [`apps/api`](./apps/api) | Negocio: auth, grafo, tiempo real | NestJS · Prisma · PostgreSQL · Redis · WebSocket |
| [`apps/ai`](./apps/ai) | IA: comprensión, embeddings, RAG | Python · FastAPI · LangGraph · LlamaIndex |

## Estructura del repositorio

```
mindOS/
├── docs/     # Cadena documental (#00–#08) + ADRs
├── apps/
│   ├── mobile/   # Flutter
│   ├── api/      # NestJS
│   └── ai/       # Python (FastAPI)
├── infra/    # docker-compose, Nginx
└── .github/  # CI/CD
```

## Arrancar en local (F0)

Requisitos: Docker, Node 22+, Python 3.11+, Flutter 3.24+.

```bash
# 1) Levantar datos + backends
docker compose -f infra/docker-compose.yml up --build

# 2) Verificar que todo está vivo
curl http://localhost:3000/v1/health   # API (NestJS)
curl http://localhost:8000/health      # AI  (FastAPI)

# 3) App móvil (apunta a la API)
cd apps/mobile
flutter create . --project-name mindos --platforms=android,ios
flutter pub get
flutter run --dart-define=API_BASE_URL=http://localhost:3000/v1
```

En F0 la app móvil solo comprueba que mindOS está vivo de punta a punta
(móvil → API). La funcionalidad de producto llega desde F1 (captura).

## Documentación

Toda la documentación oficial vive en [`/docs`](./docs/README.md), organizada
como una cadena donde cada documento depende del anterior.

> Principio de ingeniería: *nunca programar antes de diseñar; nunca diseñar antes
> de comprender el problema; nunca implementar sin documentación previa.*
