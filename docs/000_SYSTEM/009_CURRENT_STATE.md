# 009 — Current State (estado vivo del proyecto)

> 🔴 DOCUMENTO OBLIGATORIO. Se actualiza al CIERRE de CADA sesión (ritual en [008](./008_AI_COLLABORATION_PROTOCOL.md)). Es una FOTO que se sobreescribe. La historia de riesgos/deuda vive en [012](./012_RISK_AND_DEBT_REGISTER.md).

| Metadato | Valor |
|----------|-------|
| Última actualización | 2026-07-02 |
| Fase actual | F0 (cimientos) — cerrando; F1 (captura) iniciada parcialmente |
| Avance estimado del MVP (F0–F5) | ~8–10 % |

## 1. Resumen ejecutivo
Fundación documental sólida y aprobada (#00–#08). El esqueleto ejecutable existe (3 apps + Docker + CI verde). La autenticación JWT (F1a) está implementada a nivel funcional pero sin endurecer. F0 NO cumple aún su propia Definición de Hecho (falta CD a staging + IaC). La deriva documental del roadmap #08 (R-004) ya fue corregida y la DoD de F0 redefinida (ADR-011). El spec de F1 (Capture Engine) está completo y listo para implementación.

## 2. Qué existe hoy (verificado en repo)
- **apps/api (NestJS):** health `/v1/health`; auth `register/login/refresh` con bcrypt(cost 12) + JWT access/refresh; `JwtAuthGuard`; Prisma con SOLO el modelo `User`. Sin nodes/edges, sin RLS.
- **apps/ai (FastAPI):** solo `/health`; contrato abstracto `AIProvider` (complete/embed) sin implementación.
- **apps/mobile (Flutter):** pantalla de health que verifica móvil→API.
- **infra:** docker-compose (postgres+pgvector, redis, api, ai). Sin IaC/CD.
- **CI:** 3 jobs (api/ai/mobile) con lint+tipos+test+build. Sin CD.

## 3. Última decisión
ADR-012 (2026-07-02, ACEPTADO): stack canónico confirmado — Drift local, pgvector, Cloudflare (edge), MinIO/R2 (blobs S3-compatible), BullMQ (colas).
ADR-011 (2026-07-02, ACEPTADO): DoD de F0 = CD mínimo a un staging (sin K8s) + IaC mínima; infra pesada diferida a pre-beta.

## 4. Próximo objetivo
Implementar F1 — Capture Engine siguiendo el plan de tareas del spec (empezando por la migración Prisma de nodes/edges + RLS fail-closed). El diseño, los requisitos (EARS) y el plan de 15 tareas ya están aprobados.

## 5. Bloqueadores
Ninguno. La deriva del #08 (R-004) quedó corregida y mergeada. F1 está listo para entrar en implementación.

## 6. Riesgos vivos (detalle e historia en [012](./012_RISK_AND_DEBT_REGISTER.md))
- R-001 (Alto): calidad de comprensión de F2 aún no de-riesgada (PoC pendiente).
- R-002 (Medio): auth propia sin endurecer (rate limiting, rotación de refresh, enumeración por timing) — deuda de seguridad abierta.
- R-003 (Mitigado): DoD de F0 redefinida por ADR-011 (aceptado).
- R-005 (Abordado en diseño): estrategia offline-first (outbox Drift + idempotencia por client_id) definida en el spec de F1; pendiente de validar en implementación.

## 7. Deuda técnica top (detalle en [012](./012_RISK_AND_DEBT_REGISTER.md))
- D-001: sin lockfiles commiteados (CI usa `npm install`, no `npm ci`) → builds no reproducibles.
- D-002 (Diseñado): nodes/edges + RLS especificados en el spec de F1; se implementan en sus tareas.
- D-003: TODO de "dummy compare" en login (side-channel de enumeración).

## 8. Salud de la arquitectura
Alta coherencia doc→código. La frontera de dos backends está bien definida. Riesgo de complejidad distribuida asumido conscientemente (ADR-010).

## 9. Cambios recientes
- Spec completo de F1 — Capture Engine: diseño técnico, requisitos EARS (9, trazables a P1–P9) y plan de tareas (15, ordenadas por dependencias) — esta sesión.
- Fundación del sistema de gobernanza (docs/000_SYSTEM/) — esta sesión.
- Corrección de deriva documental del roadmap #08 (R-004) y creación del ADR-011 (propuesto) sobre la Definición de Hecho de F0 — esta sesión.
- ADR-012 aceptado: confirmación del stack canónico y cierre de huecos (blobs, colas, edge) — esta sesión.

## 10. Preguntas abiertas
- ¿PoC de comprensión (F2) en paralelo a F1? (recomendación CTO: sí, #08 §7).
- Proveedor LLM y dimensión de embeddings (dependencia de #07).

## 11. Acciones recomendadas (priorizadas)
1. Implementar F1 — Capture Engine según el plan de tareas, empezando por la migración Prisma de `nodes`/`edges` + RLS fail-closed (tareas 1–3).
2. Endurecer la autenticación propia (R-002) antes de pre-beta; no dejarlo sin fecha.
3. Considerar la PoC aislada de comprensión (F2) en paralelo a F1 para de-riesgar R-001 (nuestro mayor riesgo).

## Historial de versiones
| Versión | Fecha | Cambios |
|---------|-------|---------|
| 1.0 | 2026-07-02 | Estado inicial tras fundar el sistema de gobernanza. |
| 1.1 | 2026-07-02 | Coherencia del #08 en curso; ADR-011 propuesto. |
| 1.2 | 2026-07-02 | ADR-011 aceptado; F0 DoD y próximo objetivo actualizados. |
| 1.3 | 2026-07-02 | ADR-012 aceptado; alta de R-005 y pregunta de sync offline. |
| 1.4 | 2026-07-02 | Spec de F1 completo (diseño+requisitos+tareas); próximo objetivo = implementación de F1. |
| 1.5 | 2026-07-02 | Saneado de secciones desactualizadas (resumen, bloqueadores, acciones, preguntas) tras completar el spec de F1. |
