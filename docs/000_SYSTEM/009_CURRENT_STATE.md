# 009 — Current State (estado vivo del proyecto)

> 🔴 DOCUMENTO OBLIGATORIO. Se actualiza al CIERRE de CADA sesión (ritual en [008](./008_AI_COLLABORATION_PROTOCOL.md)). Es una FOTO que se sobreescribe. La historia de riesgos/deuda vive en [012](./012_RISK_AND_DEBT_REGISTER.md).

| Metadato | Valor |
|----------|-------|
| Última actualización | 2026-07-02 |
| Fase actual | F1 (Capture Engine) IMPLEMENTADA y mergeada en main; validación de integración pendiente de infraestructura. |
| Avance estimado del MVP (F0–F5) | ~22 % |

## 1. Resumen ejecutivo
Fundación documental sólida y aprobada (#00–#08). F1 (Capture Engine) está IMPLEMENTADA y mergeada en main con CI verde (unit + PBT): grafo `nodes`/`edges` + RLS fail-closed, API de captura (texto/voz), cola BullMQ, reconciliación, janitor de blobs y captura offline-first en Flutter (outbox Drift + SyncService). Falta la validación de integración (P1/P8 aislamiento, P2 no-pérdida, P7 dedup de cola) y `flutter test` contra infraestructura real (docker-compose). La autenticación JWT está implementada a nivel funcional pero sin endurecer. La deriva documental del #08 (R-004) fue corregida y la DoD de F0 redefinida (ADR-011).

## 2. Qué existe hoy (verificado en repo)
- **apps/api (NestJS):** health `/v1/health`; auth `register/login/refresh` con bcrypt(cost 12) + JWT access/refresh; `JwtAuthGuard`; Prisma con `nodes`/`edges` + RLS fail-closed; `POST /v1/captures` (texto/voz) con idempotencia (por `client_id`), cola BullMQ de comprensión, barrido de reconciliación y janitor de blobs.
- **apps/ai (FastAPI):** solo `/health`; contrato abstracto `AIProvider` (complete/embed) sin implementación.
- **apps/mobile (Flutter):** pantalla de health que verifica móvil→API; captura offline-first con outbox Drift + `SyncService` (reintento con backoff, tiempo en UTC).
- **infra:** docker-compose (postgres+pgvector, redis, api, ai). Sin IaC/CD.
- **CI:** 3 jobs (api/ai/mobile) con lint+tipos+test+build. La API usa instalación reproducible (`npm ci` + lockfile + caché). Sin CD.

## 3. Última decisión
ADR-012 (2026-07-02, ACEPTADO): stack canónico confirmado — Drift local, pgvector, Cloudflare (edge), MinIO/R2 (blobs S3-compatible), BullMQ (colas).
ADR-011 (2026-07-02, ACEPTADO): DoD de F0 = CD mínimo a un staging (sin K8s) + IaC mínima; infra pesada diferida a pre-beta.

## 4. Próximo objetivo
Validar F1 contra infraestructura real (docker-compose: Postgres+RLS, Redis, MinIO) ejecutando los tests de integración skippeados y `flutter test`; completar hardening de plataforma (reproducibilidad). Después, F2 (comprensión) — de-riesgar R-001 con una PoC.

## 5. Bloqueadores
Ninguno. F1 está implementada y mergeada. Pendiente NO bloqueante: validar F1 contra infraestructura real (R-006) antes de darla por 'demostrada' (los tests de aislamiento P1/P8, no-pérdida P2 y dedup P7 están escritos pero skippeados sin infra).

## 6. Riesgos vivos (detalle e historia en [012](./012_RISK_AND_DEBT_REGISTER.md))
- R-001 (Alto): calidad de comprensión de F2 aún no de-riesgada (PoC pendiente).
- R-002 (Medio): auth propia sin endurecer (rate limiting, rotación de refresh, enumeración por timing) — deuda de seguridad abierta.
- R-003 (Mitigado): DoD de F0 redefinida por ADR-011 (aceptado).
- R-005 (Abordado en diseño): estrategia offline-first (outbox Drift + idempotencia por client_id) definida en el spec de F1; pendiente de validar en implementación.
- R-006 (Medio): integración de F1 sin ejecutar contra infra real.

## 7. Deuda técnica top (detalle en [012](./012_RISK_AND_DEBT_REGISTER.md))
- D-001: en progreso (API hecha — lockfile commiteado + CI en `npm ci` + caché); pendiente móvil (pubspec.lock) y ai (deps Python).
- D-002 (Diseñado): nodes/edges + RLS especificados en el spec de F1; se implementan en sus tareas.
- D-003: TODO de "dummy compare" en login (side-channel de enumeración).
- D-006: barrido de reconciliación y janitor iteran sobre TODOS los usuarios (coste O(usuarios)).
- D-007: código móvil solo validable en CI (no hay SDK de Flutter en el entorno de desarrollo).

## 8. Salud de la arquitectura
Alta coherencia doc→código. La frontera de dos backends está bien definida. Riesgo de complejidad distribuida asumido conscientemente (ADR-010).

## 9. Cambios recientes
- F1 completa mergeada en main (datos+backend+móvil), CI verde.
- Corrección de CI: build_runner de Drift, PBT determinista (semilla fija), tiempo del outbox en UTC.
- PR de plataforma: reproducibilidad de la API (npm ci + lockfile + caché).
- Spec completo de F1 — Capture Engine: diseño técnico, requisitos EARS (9, trazables a P1–P9) y plan de tareas (15, ordenadas por dependencias).
- Fundación del sistema de gobernanza (docs/000_SYSTEM/).
- Corrección de deriva documental del roadmap #08 (R-004) y creación del ADR-011 (propuesto) sobre la Definición de Hecho de F0.
- ADR-012 aceptado: confirmación del stack canónico y cierre de huecos (blobs, colas, edge).

## 10. Preguntas abiertas
- ¿PoC de comprensión (F2) en paralelo a F1? (recomendación CTO: sí, #08 §7).
- Proveedor LLM y dimensión de embeddings (dependencia de #07).

## 11. Acciones recomendadas (priorizadas)
1. Validar F1 contra infraestructura real: levantar docker-compose (Postgres+RLS rol no-owner, Redis, MinIO), ejecutar los `*.integration.spec.ts` y `flutter test` → cerrar R-006.
2. Completar la reproducibilidad (D-001) en móvil (`pubspec.lock`) y ai (deps Python), y endurecer la autenticación propia (R-002).
3. Arrancar F2 (comprensión) con una PoC aislada para de-riesgar R-001 (nuestro mayor riesgo).

## Historial de versiones
| Versión | Fecha | Cambios |
|---------|-------|---------|
| 1.0 | 2026-07-02 | Estado inicial tras fundar el sistema de gobernanza. |
| 1.1 | 2026-07-02 | Coherencia del #08 en curso; ADR-011 propuesto. |
| 1.2 | 2026-07-02 | ADR-011 aceptado; F0 DoD y próximo objetivo actualizados. |
| 1.3 | 2026-07-02 | ADR-012 aceptado; alta de R-005 y pregunta de sync offline. |
| 1.4 | 2026-07-02 | Spec de F1 completo (diseño+requisitos+tareas); próximo objetivo = implementación de F1. |
| 1.5 | 2026-07-02 | Saneado de secciones desactualizadas (resumen, bloqueadores, acciones, preguntas) tras completar el spec de F1. |
| 1.6 | 2026-07-02 | F1 mergeada; hardening de reproducibilidad; alta de R-006/D-006/D-007. |
| 1.7 | 2026-07-02 | Saneado de §5 (bloqueadores) y §11 (acciones) tras el merge de F1. |
