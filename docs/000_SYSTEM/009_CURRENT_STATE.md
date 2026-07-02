# 009 — Current State (estado vivo del proyecto)

> 🔴 DOCUMENTO OBLIGATORIO. Se actualiza al CIERRE de CADA sesión (ritual en [008](./008_AI_COLLABORATION_PROTOCOL.md)). Es una FOTO que se sobreescribe. La historia de riesgos/deuda vive en [012](./012_RISK_AND_DEBT_REGISTER.md).

| Metadato | Valor |
|----------|-------|
| Última actualización | 2026-07-03 |
| Fase actual | F1 (Capture Engine) COMPLETA y usable de punta a punta en main (incl. pantalla de captura + login endurecido). F2 (comprensión) diseñada con PoC/arnés listo. Pendiente: validar F1 contra infra real y ejecutar el examen de F2 con LLM real. |
| Avance estimado del MVP (F0–F5) | ~28-30 % |

## 1. Resumen ejecutivo
F1 (Capture Engine) es usable de punta a punta en main: captura offline-first (outbox Drift + `SyncService`) con **pantalla de captura** operativa, sincronización idempotente y grafo `nodes`/`edges` + RLS fail-closed en la API. La **autenticación está endurecida** (rate limiting, rotación de refresh tokens con detección de reuso, anti-enumeración). Flutter está operativo localmente y las 3 apps tienen builds reproducibles. Falta la **validación de integración de F1** contra infraestructura real (R-006) y el **veredicto de calidad de F2** ejecutando el examen/arnés con un LLM real (R-001).

## 2. Qué existe hoy (verificado en repo)
- **apps/api (NestJS):** health `/v1/health`; auth `register/login/refresh/logout` con bcrypt(cost 12) + JWT access/refresh **endurecida** (`@nestjs/throttler` con baseline global + límite estricto en `/auth/*`; tabla `refresh_tokens` con rotación de un solo uso y detección de reuso que revoca la familia/sesión; anti-enumeración por timing en login); `JwtAuthGuard`; Prisma con `nodes`/`edges` + `idempotency_keys` + RLS fail-closed; `POST /v1/captures` (texto/voz) con idempotencia (por `client_id`), cola BullMQ de comprensión, barrido de reconciliación y janitor de blobs.
- **apps/ai (FastAPI):** `/health`; contrato abstracto `AIProvider` (complete/embed); PoC/arnés de comprensión de F2 listo para ejecutar contra un LLM real.
- **apps/mobile (Flutter):** pantalla de health (móvil→API) y **PANTALLA de captura** (escribir/guardar offline + lista con estado de sync); captura offline-first con outbox Drift + `SyncService` (reintento con backoff, tiempo en UTC). Instalable/operativo localmente.
- **infra:** docker-compose (postgres+pgvector, redis, api, ai). Sin IaC/CD.
- **CI:** 3 jobs (api/ai/mobile) con lint+tipos+test+build. Las 3 apps con **builds reproducibles** (`npm ci` + lockfile para api; `pubspec.lock` con `--enforce-lockfile` para móvil; `requirements.lock` para ai). Sin CD.

## 3. Última decisión
ADR-012 (2026-07-02, ACEPTADO): stack canónico confirmado — Drift local, pgvector, Cloudflare (edge), MinIO/R2 (blobs S3-compatible), BullMQ (colas).
ADR-011 (2026-07-02, ACEPTADO): DoD de F0 = CD mínimo a un staging (sin K8s) + IaC mínima; infra pesada diferida a pre-beta.
Norma de gobernanza [008](./008_AI_COLLABORATION_PROTOCOL.md): **"aprovisionar antes de degradar"** (lección del episodio Flutter/D-007): provisionar la herramienta antes de degradar el alcance o el rigor.

## 4. Próximo objetivo
Validar F1 contra infra real (docker-compose + tests de integración + `flutter test`) → cerrar R-006. Ejecutar el examen de F2 con clave LLM real → veredicto R-001. Según resultado, construir el motor completo de F2 o iterar prompts.

## 5. Bloqueadores
Ninguno técnico. La ruta crítica (validación F1 con Docker + examen F2 con clave LLM) depende del entorno/credenciales del founder.

## 6. Riesgos vivos (detalle e historia en [012](./012_RISK_AND_DEBT_REGISTER.md))
- R-001 (Alto, abierto): calidad de comprensión de F2 aún no de-riesgada; pendiente ejecutar el examen/arnés con LLM real.
- R-006 (Medio, abierto): integración de F1 sin ejecutar contra infra real (aislamiento P1/P8, no-pérdida P2, dedup de cola P7, blobs).
- R-005 (Abordado en diseño): estrategia offline-first (outbox Drift + idempotencia por client_id) definida e implementada en F1; pendiente de validar en integración.
- R-002 (Mitigado): auth propia endurecida (rate limiting, rotación de refresh con detección de reuso, anti-enumeración).
- R-003 (Mitigado): DoD de F0 redefinida por ADR-011 (aceptado).

## 7. Deuda técnica top (detalle en [012](./012_RISK_AND_DEBT_REGISTER.md))
- D-001 (Cerrado): builds reproducibles en las 3 apps (npm ci + lockfile; pubspec.lock; requirements.lock).
- D-002 (Cerrado-implementación, pendiente validación): grafo `nodes`/`edges` + `idempotency_keys` y RLS fail-closed implementados en F1; falta validar contra Postgres real (R-006).
- D-003 (Cerrado): dummy compare + respuesta uniforme en login, con test.
- D-004 (abierto): ADRs inconsistentes (embebidos vs archivo suelto, sin cero-padding uniforme).
- D-005 (abierto): sin rastreo de errores (Sentry) ni gestión formal de secretos.
- D-006 (abierto): reconciliación y janitor iteran sobre TODOS los usuarios (coste O(usuarios)).
- D-007 (Mitigado): SDK de Flutter instalado y operativo localmente; el móvil ya se valida fuera de CI.
- D-008 (abierto): dimensión del vector de embedding y elección de proveedor LLM sin fijar (depende de la PoC de F2).
- D-009 (Cerrado): widget tests de la pantalla de captura estabilizados y reactivados (fix del timer de cierre del stream de Drift).

## 8. Salud de la arquitectura
Alta coherencia doc→código. La frontera de dos backends está bien definida. Riesgo de complejidad distribuida asumido conscientemente (ADR-010).

## 9. Cambios recientes
- F1: **pantalla de captura mergeada** (escribir/guardar offline + lista con estado de sync).
- **Login endurecido** (R-002 mitigado / D-003 cerrado): rate limiting, rotación de refresh con detección de reuso, anti-enumeración.
- **Flutter operativo localmente** (D-007 mitigado / D-009 cerrado): widget tests estabilizados y reactivados.
- **Builds reproducibles** en las 3 apps (D-001 cerrado): npm ci + lockfile, pubspec.lock, requirements.lock.
- Norma de gobernanza 008 **"aprovisionar antes de degradar"**.
- **PoC/arnés de F2** (comprensión) listo para el examen con LLM real.

## 10. Preguntas abiertas
- ¿PoC de comprensión (F2) en paralelo a F1? → **sí** (en marcha; PoC/arnés listo).
- Proveedor LLM y dimensión de embeddings (dependencia de #07; ver D-008).

## 11. Acciones recomendadas (priorizadas)
1. Validar F1 con Docker: levantar docker-compose (Postgres+RLS rol no-owner, Redis, MinIO), ejecutar los `*.integration.spec.ts` y `flutter test` → cerrar R-006.
2. Ejecutar el examen de F2 con un LLM real (clave) → veredicto de R-001.
3. Según el veredicto: construir el motor completo de F2 o iterar prompts.

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
| 1.8 | 2026-07-03 | Refresco del estado vivo: F1 usable de punta a punta (pantalla de captura), login endurecido, Flutter local y builds reproducibles en las 3 apps; D-002 cerrado (implementación); próximos hitos = validar F1 con Docker (R-006) y examen de F2 con LLM real (R-001). |
