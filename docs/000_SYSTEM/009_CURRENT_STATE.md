# 009 — Current State (estado vivo del proyecto)

> 🔴 DOCUMENTO OBLIGATORIO. Se actualiza al CIERRE de CADA sesión (ritual en [008](./008_AI_COLLABORATION_PROTOCOL.md)). Es una FOTO que se sobreescribe. La historia de riesgos/deuda vive en [012](./012_RISK_AND_DEBT_REGISTER.md).

| Metadato | Valor |
|----------|-------|
| Última actualización | 2026-07-02 |
| Fase actual | F0 (cimientos) — cerrando; F1 (captura) iniciada parcialmente |
| Avance estimado del MVP (F0–F5) | ~8–10 % |

## 1. Resumen ejecutivo
Fundación documental sólida y aprobada (#00–#08). El esqueleto ejecutable existe (3 apps + Docker + CI verde). La autenticación JWT (F1a) está implementada a nivel funcional pero sin endurecer. F0 NO cumple aún su propia Definición de Hecho (falta CD a staging + IaC). Existe deriva documental en el roadmap (#08).

## 2. Qué existe hoy (verificado en repo)
- **apps/api (NestJS):** health `/v1/health`; auth `register/login/refresh` con bcrypt(cost 12) + JWT access/refresh; `JwtAuthGuard`; Prisma con SOLO el modelo `User`. Sin nodes/edges, sin RLS.
- **apps/ai (FastAPI):** solo `/health`; contrato abstracto `AIProvider` (complete/embed) sin implementación.
- **apps/mobile (Flutter):** pantalla de health que verifica móvil→API.
- **infra:** docker-compose (postgres+pgvector, redis, api, ai). Sin IaC/CD.
- **CI:** 3 jobs (api/ai/mobile) con lint+tipos+test+build. Sin CD.

## 3. Última decisión
ADR-010 (2026-07-01): mobile-first + dos backends (NestJS negocio / Python IA) + auth JWT propia. Reemplaza parcialmente ADR-01/03/08, D1 (#01), ADR-A1 (#04), P3 (#07).

## 4. Próximo objetivo
Cerrar F0 honestamente (CD a staging + IaC mínima) O tomar la decisión explícita de posponerlo (ADR). En paralelo, preparar F1: `POST /v1/captures` + nodo `Capture` + tabla nodes/edges + RLS.

## 5. Bloqueadores
Ninguno técnico duro. En resolución: la deriva del #08 (R-004) se está corrigiendo en el PR de coherencia.

## 6. Riesgos vivos (detalle e historia en [012](./012_RISK_AND_DEBT_REGISTER.md))
- R-001 (Alto): calidad de comprensión de F2 aún no de-riesgada (PoC pendiente).
- R-002 (Medio): auth propia sin endurecer (rate limiting, rotación de refresh, enumeración por timing) — deuda de seguridad abierta.
- R-003 (Medio): F0 declarado "hecho" sin cumplir su DoD → falsa señal de avance.

## 7. Deuda técnica top (detalle en [012](./012_RISK_AND_DEBT_REGISTER.md))
- D-001: sin lockfiles commiteados (CI usa `npm install`, no `npm ci`) → builds no reproducibles.
- D-002: nodes/edges + RLS del #03 no implementados (esperado, pero es el core).
- D-003: TODO de "dummy compare" en login (side-channel de enumeración).

## 8. Salud de la arquitectura
Alta coherencia doc→código. La frontera de dos backends está bien definida. Riesgo de complejidad distribuida asumido conscientemente (ADR-010).

## 9. Cambios recientes
- Fundación del sistema de gobernanza (docs/000_SYSTEM/) — esta sesión.
- Corrección de deriva documental del roadmap #08 (R-004) y creación del ADR-011 (propuesto) sobre la Definición de Hecho de F0 — esta sesión.

## 10. Preguntas abiertas
- ¿PoC de comprensión (F2) en paralelo a F1? (recomendación CTO: sí, #08 §7).
- ¿Se aprueba el ADR-011 (CD mínimo + diferir infra pesada) para cerrar la DoD de F0? — pendiente del founder.
- Proveedor LLM y dimensión de embeddings (dependencia de #07).

## 11. Acciones recomendadas (priorizadas)
1. Cerrar deriva documental del roadmap #08 (coherencia con ADR-010).
2. ADR sobre el estado real de F0 (cerrar CD/IaC o posponer con criterio).
3. Diseñar F1 (Capture Engine) como primer spec de implementación.

## Historial de versiones
| Versión | Fecha | Cambios |
|---------|-------|---------|
| 1.0 | 2026-07-02 | Estado inicial tras fundar el sistema de gobernanza. |
| 1.1 | 2026-07-02 | Coherencia del #08 en curso; ADR-011 propuesto. |
