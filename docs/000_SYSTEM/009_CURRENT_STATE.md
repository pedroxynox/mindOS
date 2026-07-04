# 009 — Current State (estado vivo del proyecto)

> 🔴 DOCUMENTO OBLIGATORIO. Se actualiza al CIERRE de CADA sesión (ritual en [008](./008_AI_COLLABORATION_PROTOCOL.md)). Es una FOTO que se sobreescribe. La historia cronológica y el detalle de riesgos/deuda viven en [012](./012_RISK_AND_DEBT_REGISTER.md).

| Metadato | Valor |
|----------|-------|
| Última actualización | 2026-07-03 |
| Fase actual | F1 (Capture Engine) **COMPLETA y validada contra infra real** (R-006 cerrado). F2 (Comprensión) en **fase de de-risking del arnés de evaluación** (R-001) — el motor de F2 **NO** está construido aún. |
| Avance estimado del MVP (F0–F5) | ~30 % |

## 1. Resumen ejecutivo
F1 (Capture Engine) está **cerrada y verificada contra infraestructura real**: captura offline-first (outbox Drift + `SyncService`), pantalla de captura, grafo `nodes`/`edges` con RLS fail-closed, `POST /v1/captures` idempotente, cola BullMQ, reconciliación y janitor de blobs; suite de integración **8/8 en verde** (R-006 cerrado). La autenticación está endurecida y las 3 apps tienen builds reproducibles.

El trabajo de HOY es **F2 / R-001**: de-riesgar la CALIDAD de la comprensión con el arnés de evaluación (`apps/ai/app/eval/`) **antes** de construir el motor. Ya hay una **medición estable de 45 casos con Groq/Llama** (prompt v3): entities F1 **0.826** (PASA), task precision **0.889** (PASA), pero **hallucination 0.160** (FALLA vs 0.05 provisional). El founder decidió **iterar honestamente hacia hallucination ≤0.10** (aspiración 0.05) protegiendo recall y calidad de tareas, **sin relajar umbrales ni gold**. Se consolidó el prompt en **v5** (mismas reglas, ~28% menos tokens). **BLOQUEO ACTUAL:** no se ha logrado COMPLETAR una corrida del examen con v5 por trabas de los proveedores gratuitos de LLM. Todo esto vive en el **PR #40 abierto** (rama `fix/f2-eval-prompt-v4`), **NO mergeado**.

## 2. Qué existe hoy (verificado, ya en main)
- **F1 end-to-end:** captura offline-first (outbox Drift + `SyncService` con backoff, tiempo en UTC), pantalla de captura (escribir/guardar offline + lista con estado de sync), grafo `nodes`/`edges` + `idempotency_keys` con **RLS fail-closed**, `POST /v1/captures` (texto/voz) con **idempotencia** por `client_id`, cola **BullMQ** de comprensión, barrido de **reconciliación** y **janitor de blobs**.
- **Auth endurecida:** rate limiting (`@nestjs/throttler`, baseline global + límite estricto en `/auth/*`), rotación de refresh tokens de un solo uso con **detección de reuso** que revoca la familia/sesión, y **anti-enumeración** por timing en login.
- **Builds reproducibles** en las 3 apps: API (`npm ci` + lockfile), móvil (`pubspec.lock` + `--enforce-lockfile`), IA (`requirements.lock`).
- **Validación de integración de F1 contra infra REAL:** Postgres 15 (rol no-owner `mindos_app`) + Redis 6 + MinIO aprovisionados nativamente → **8/8 tests, 5/5 suites verde** (P1/P8 aislamiento RLS, P2 no-pérdida, P7 dedup de cola, P6 blobs, janitor). **R-006 cerrado**, incl. el fix del bug de producto RLS de empty-context (GUC a `''` en pool de Prisma → migración `NULLIF(current_setting(...), '')::uuid`).
- **ADRs consolidados** en archivos individuales `ADR-001..017` con índice (**D-004 cerrado**).
- **Arnés de evaluación de F2** (`apps/ai/app/eval/`), **extractor** (`app/understanding/extract.py`) y capa **`AIProvider`** intercambiable con proveedores `fake`/`openai`/`groq`/`gemini`.

## 3. F2 / R-001 — estado detallado (lo que estamos haciendo AHORA)
- **Medición ESTABLE (45 casos, Groq/Llama, prompt v3):** entities F1 **0.826** (PASA ≥0.80, recall **0.811**), task precision **0.889** (PASA ≥0.85), **hallucination 0.160** (FALLA vs 0.05 provisional), connections F1 **0.34**, coste **$0**, p95 **~10.7 s**.
- **Decisión del founder:** iterar honestamente hacia **hallucination ≤0.10** (aspiración 0.05) **ANTES** de construir el motor de F2, **protegiendo** el recall de entidades (0.811) y la task precision (0.889). **NO** se tocan umbrales para "aprobar".
- **Prompt v4 → v5:** se diagnosticaron **3 patrones de sobre-extracción** (objetos/lugares→`topic`; roles/parentesco→`person`; `note`-relleno) y se **consolidó** el prompt en **v5** (mismas reglas semánticas, ~28% menos tokens: 9263→6633 chars, recall-safe verificado contra los 45 gold; deuda **D-010** en progreso). Todo esto vive en el **PR #40 abierto** (rama `fix/f2-eval-prompt-v4`), **NO mergeado**.
- **BLOQUEO ACTUAL:** no se ha logrado **COMPLETAR** una corrida del examen con v5 por trabas de proveedores gratuitos:
  - Groq gratis → cupo diario agotado hoy.
  - Groq pago → deshabilitado por Groq.
  - Gemini 1.5 → retirado por Google (falla en ~20-30 s).
  - Gemini 2.0-flash gratis → **FUNCIONA**, pero su cupo diario (~200/día) se agotó hoy.
  - Gemini 2.0 pago → error de Google `OR_BACR2_44` al activar billing.
  - OpenAI → mínimo $5, descartado por el founder.
  - El proveedor por defecto de gemini quedó fijado en **`gemini-2.0-flash`** (el que sí funciona en la clave).

## 4. Última decisión
- **Iterar honestamente hacia hallucination ≤0.10** (aspiración 0.05) antes de construir el motor de F2, sin relajar umbrales ni gold (protegiendo recall 0.811 y task precision 0.889).
- **Consolidar el prompt en v5** (misma semántica, ~28% menos tokens) para bajar la presión sobre los límites por minuto/token del proveedor y poder completar el examen.
- **Fijar el proveedor Gemini por defecto en `gemini-2.0-flash`** (confirmado funcional en la clave; el bloqueo es solo el cupo diario, que se reinicia).
- Vigentes de sesiones previas: **ADR-012** (stack canónico) y **ADR-011** (DoD de F0), y la norma de gobernanza [008](./008_AI_COLLABORATION_PROTOCOL.md) **"aprovisionar antes de degradar"**.

## 5. Próxima acción inmediata (para la nueva sesión)
1. **Lanzar el examen de F2** desde la rama `fix/f2-eval-prompt-v4` (workflow **"F2 comprehension eval"** en Actions, `provider=gemini`), preferiblemente **MAÑANA** con el cupo diario de Gemini 2.0-flash reiniciado (o si el founder logra activar el pago de Gemini). Tarda **~10 min** (pausa 12 s entre llamadas).
2. **Con los 3 números** (entities F1 / task precision / hallucination):
   - Si **hallucination ≤0.10** y entities/tasks se mantienen → **mergear PR #40**, cerrar/actualizar **D-010**, **ratificar umbrales realistas por ADR**, y proceder a **construir el motor de F2**.
   - Si **no** → otra iteración honesta o reevaluar modelo/enfoque (**NO** relajar umbrales ni gold).
3. Tras el veredicto, **volver a refrescar este 009**.

## 6. Bloqueadores
La medición de calidad de F2 depende de **completar una corrida del examen**, hoy **bloqueada por cupos de free-tier** de los proveedores de LLM. Se resuelve con **cupo fresco mañana** (Gemini 2.0-flash) o con **billing** funcionando. Sin este dato no hay veredicto de R-001 ni luz verde para el motor de F2.

## 7. Riesgos vivos (detalle e historia en [012](./012_RISK_AND_DEBT_REGISTER.md))
- **R-001 (Alto, abierto — en de-risking):** calidad de comprensión de F2; medición estable con v3 pasa entities/tasks pero falla hallucination (0.160); iterando hacia ≤0.10 con v5, pendiente de una corrida que complete.
- **R-005 (abordado en diseño):** offline-first (outbox Drift + idempotencia por `client_id`) definido, implementado y ahora **validado** en la integración de F1.
- **R-002 (mitigado):** auth endurecida (rate limiting, rotación de refresh con detección de reuso, anti-enumeración).
- **R-003 (mitigado):** DoD de F0 redefinida por ADR-011.
- **R-006 (cerrado):** integración de F1 validada 8/8 contra infra real (incl. fix del bug RLS empty-context).
- **R-004 (en corrección/mitigado):** deriva documental del roadmap #08 vs ADR-010.

## 8. Deuda técnica top (detalle en [012](./012_RISK_AND_DEBT_REGISTER.md))
- **D-005 (abierto):** sin rastreo de errores (Sentry) ni gestión formal de secretos.
- **D-006 (abierto):** reconciliación y janitor iteran sobre TODOS los usuarios (coste O(usuarios)).
- **D-008 (abierto):** dimensión de embeddings y elección de proveedor LLM sin fijar; **se fija tras superar el gate de calidad de F2**.
- **D-010 (en progreso):** prompt de extracción sobredimensionado; consolidado en v5 (~28% menos tokens), pendiente de re-medir calidad con una corrida que complete.
- **Mitigados/cerrados:** D-001 (builds reproducibles), D-002 (grafo + RLS, validado por R-006), D-003 (anti-enumeración login), D-004 (ADRs consolidados), D-007 (Flutter local), D-009 (widget tests reactivados).

## 9. Salud de la arquitectura
Alta coherencia doc→código. La frontera de dos backends (NestJS + FastAPI) está bien definida y la capa `AIProvider` intercambiable ya está demostrando su valor (permite cambiar de Groq a Gemini sin tocar la lógica de eval). Riesgo de complejidad distribuida asumido conscientemente (ADR-010).

## 10. Cambios recientes
- **R-006 cerrado:** integración de F1 validada 8/8 contra infra real; corregido el bug de producto RLS de empty-context.
- **D-004 cerrado:** ADRs consolidados en archivos individuales `ADR-001..017`.
- **F2 / R-001:** medición estable de 45 casos con Groq/Llama (prompt v3) → entities 0.826 / taskP 0.889 / hallucination 0.160.
- **Prompt consolidado en v5** (misma semántica, ~28% menos tokens; D-010 en progreso).
- **Proveedor Gemini añadido** (gratis, sin tarjeta) y fijado por defecto en `gemini-2.0-flash`; resiliencia del workflow del examen mejorada (espaciado por proveedor, reintentos, mensajes de error correctos).
- Todo lo de F2 anterior vive en el **PR #40 abierto** (rama `fix/f2-eval-prompt-v4`), aún **sin mergear**.

## 11. Preguntas abiertas
- **¿v5 baja la hallucination a ≤0.10 sin dañar recall/tareas?** → pendiente de una corrida de Gemini/Groq que **COMPLETE** (bloqueada hoy por cupos).
- **Proveedor LLM y dimensión de embeddings** (ver D-008) → se fija con datos **tras** superar el gate de calidad de F2.

## 12. Acciones recomendadas (priorizadas)
1. **Completar el examen de F2** con `provider=gemini` (mañana, cupo fresco) desde `fix/f2-eval-prompt-v4`.
2. Según el veredicto de los 3 números: **mergear PR #40 + ratificar umbrales por ADR + construir el motor de F2**, o iterar honestamente.
3. **Refrescar 009 y 012** al cierre (ritual [008](./008_AI_COLLABORATION_PROTOCOL.md)).

## 13. PRs abiertos
- **PR #40** (rama `fix/f2-eval-prompt-v4`): prompt **v5** + proveedor **Gemini** + arreglos de resiliencia del examen. **NO mergear** hasta validar v5 con una corrida que **COMPLETE**.

## 14. Nota para la nueva sesión (importante)
- El **detalle completo y cronológico** de la saga de F2 vive en [012](./012_RISK_AND_DEBT_REGISTER.md); su versión más reciente (**v1.26**) está **en el PR #40, NO en main** (en main, 012 va una versión por detrás).
- **Mantener el ritual:** actualizar **009 y 012 al cierre** de cada sesión.
- **Hablar en español y en lenguaje no técnico** con el founder (CEO no programador); actuar como **CPTO con pensamiento crítico**.
- **NO relajar umbrales ni gold** para "aprobar" el examen: el rigor es el producto.

## Historial de versiones
| Versión | Fecha | Cambios |
|---------|-------|---------|
| 1.0 | 2026-07-02 | Estado inicial tras fundar el sistema de gobernanza. |
| 1.1 | 2026-07-02 | Coherencia del #08 en curso; ADR-011 propuesto. |
| 1.2 | 2026-07-02 | ADR-011 aceptado; F0 DoD y próximo objetivo actualizados. |
| 1.3 | 2026-07-02 | ADR-012 aceptado; alta de R-005 y pregunta de sync offline. |
| 1.4 | 2026-07-02 | Spec de F1 completo (diseño+requisitos+tareas); próximo objetivo = implementación de F1. |
| 1.5 | 2026-07-02 | Saneado de secciones desactualizadas tras completar el spec de F1. |
| 1.6 | 2026-07-02 | F1 mergeada; hardening de reproducibilidad; alta de R-006/D-006/D-007. |
| 1.7 | 2026-07-02 | Saneado de §5 (bloqueadores) y §11 (acciones) tras el merge de F1. |
| 1.8 | 2026-07-03 | Refresco del estado vivo: F1 usable de punta a punta, login endurecido, Flutter local y builds reproducibles; D-002 cerrado (implementación); próximos hitos = validar F1 (R-006) y examen de F2 (R-001). |
| 1.9 | 2026-07-03 | Refresco de cierre de sesión: **R-006 cerrado** (F1 validada 8/8 contra infra real) y **D-004 cerrado** (ADRs consolidados). Fase actual re-enfocada en **F2 / R-001** (de-risking del arnés): medición estable de 45 casos con Groq/Llama (entities 0.826 / taskP 0.889 / hallucination 0.160), decisión de iterar hacia hallucination ≤0.10 sin relajar umbrales ni gold, prompt consolidado en **v5** (~28% menos tokens, D-010 en progreso) y proveedor **Gemini** añadido (por defecto `gemini-2.0-flash`). **Bloqueo actual:** completar una corrida del examen (cupos de free-tier). Trabajo de F2 vive en el **PR #40** (rama `fix/f2-eval-prompt-v4`), no mergeado; 012 v1.26 vive en ese PR, no en main. |
