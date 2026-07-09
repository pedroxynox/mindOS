# 009 — Current State (estado vivo del proyecto)

> 🔴 DOCUMENTO OBLIGATORIO. Se actualiza al CIERRE de CADA sesión (ritual en [008](./008_AI_COLLABORATION_PROTOCOL.md)). Es una FOTO que se sobreescribe. La historia cronológica y el detalle de riesgos/deuda viven en [012](./012_RISK_AND_DEBT_REGISTER.md).

| Metadato | Valor |
|----------|-------|
| Última actualización | 2026-07-09 |
| Fase actual | F1 (Capture Engine) **COMPLETA y validada** (R-006 cerrado). F2 (Comprensión): motor **construido y validado contra infra real** (R-007 cerrado), **gate de calidad SUPERADO con margen → R-001 RESUELTA** (v8: F1 0.890 / taskP 1.000 / hall 0.074 / $0.0023, OpenAI `gpt-5.4-mini`), **arranque del worker CABLEADO** (interruptor `WORKER_ENABLED`, apagado por defecto), **voz DECIDIDA** (text-first, voz diferida) y **plan de despliegue en Render PREPARADO** (`render.yaml` + guía). **Falta:** aplicar el despliegue en Render (arrancar el motor "de verdad" en la nube). |
| Avance estimado del MVP (F0–F5) | ~45 % |

## 1. Resumen ejecutivo
**F1 (Capture Engine)** está cerrada y verificada contra infra real (R-006): captura offline-first, grafo `nodes`/`edges` con RLS fail-closed, `POST /v1/captures` idempotente, cola BullMQ, reconciliación y janitor; auth endurecida; builds reproducibles.

**F2 (Comprensión)** — el foco de esta sesión — quedó **de-riesgada y lista para encender**:
1. El motor ya estaba construido (PR #45) y validado contra Postgres+pgvector y Redis/BullMQ reales (R-007 cerrado).
2. **Calidad RESUELTA (R-001):** el founder pagó OpenAI y elegimos `gpt-5.4-mini`. Iteración honesta de prompt **v6→v7→v8** (sin tocar gold/umbrales): v6 0.819/hall 0.059 (PASS) → v7 0.870/**0.118** (FAIL solo por alucinación) → **v8 F1 0.890 (P 0.926 / R 0.857) / taskP 1.000 / hall 0.074 / $0.0023 = GATE PASSED con margen**. El recall subió de 0.726 a 0.857 sin disparar la alucinación.
3. **Motor cableado para encenderse:** `main.py` ahora arranca/cierra el worker BullMQ vía *lifespan*, con interruptor `WORKER_ENABLED` (apagado por defecto para no romper health-only ni tests). Un fallo de arranque se loguea pero no tumba `/health`.
4. **Voz DECIDIDA:** text-first ahora; la transcripción de voz se difiere (el pipeline ya preserva la captura de voz con un *seam* seguro).
5. **Finanzas ANOTADA** como función futura (V4) en el roadmap §3.1 — ampliación sobre F2, no ahora.
6. **Despliegue PREPARADO:** `render.yaml` (Blueprint "todo en Render": Postgres+pgvector, Key Value/Redis, API, IA+worker) + `docs/06-infrastructure/DEPLOY_RENDER.md`. Arreglados dos huecos de imagen (worker deps `.[worker]`; Prisma CLI en la imagen de la API para migraciones).

Suite: **100 offline + 5 integración**, `ruff`/`mypy` limpios (Python 3.11).

## 2. Qué existe hoy (verificado, ya en main)
- **F1 end-to-end** (captura offline-first, grafo + RLS fail-closed, `POST /v1/captures` idempotente, cola BullMQ, reconciliación, janitor), **auth endurecida**, **builds reproducibles**, integración **8/8** contra infra real (R-006), **ADRs** 001..019.
- **Motor de comprensión F2** (`apps/ai/app/understanding/`): contrato, `enrichment` puro, puerto `GraphStore`+`InMemory`+`PgGraphStore`, `rls`, `cost_meter`, `pipeline`, `worker` BullMQ. Migración pgvector/`llm_usage`. Validado contra infra real (R-007).
- **Extractor `extract.py` en prompt v8** (R-001 superado); capa **`AIProvider`** intercambiable (`fake`/`openai`/`groq`/`gemini`) con **temperatura adaptativa** (envía `temperature=0`; si el modelo lo rechaza —p.ej. gpt-5.5— lo omite en runtime).
- **Arranque del worker cableado** (`main.py` lifespan + `WORKER_ENABLED`, apagado por defecto).
- **Config de despliegue en Render** (`render.yaml` + `DEPLOY_RENDER.md`) — ver §5 y §6.

## 3. Cómo funciona el sistema (mapa mental para retomar)
`Móvil (Flutter, offline-first)` → guarda la captura y la sincroniza → **API NestJS** `POST /v1/captures` (idempotente) → **encola** un job en Redis (BullMQ) → **Servicio IA (Python)**: el **worker** consume el job → **pipeline** llama al **`AIProvider` (OpenAI `gpt-5.4-mini`)** para extraer entidades/tareas/temas → **escribe en el grafo** Postgres bajo RLS (aislado por usuario) con provenance + embedding (pgvector) + coste. Todo con idempotencia (una captura se procesa una vez). La calidad de la extracción se mide con el **examen F2** (45 casos gold, `apps/ai/app/eval/`) contra un **gate ratificado** (ADR-018: F1≥0.80, taskP≥0.85, hallucination≤0.10, coste≤$0.01).

## 4. Últimas decisiones (esta sesión)
- **Proveedor de comprensión = OpenAI `gpt-5.4-mini`** (no la 5.5: la 5.5 atrapa más recall pero **inventa más** y cuesta ~12x; la mini supera el gate barato). PRs #47/#49/#50.
- **Prompt v8** como versión de producción (R-001 resuelta). PRs #51 (v7) → #52 (v8) → #53 (registro).
- **Worker: cableado pero apagado por defecto** (`WORKER_ENABLED`); se enciende en el despliegue. PR #54.
- **Voz: text-first, transcripción diferida** (sub-proyecto propio: `AIProvider.transcribe` + acceso al blob). PR #54 / design §19.
- **Finanzas: función futura reservada (V4)**, ampliación sobre F2, se construye DESPUÉS de encender el bucle central. Roadmap §3.1 (PR #54).
- **Despliegue = "todo en Render"** (el founder ya usa Render). Empezar **GRATIS para verlo vivo**, luego pasar a pago (~$15–25/mes) para 24/7. PR #55 (+ fix a plan gratis en curso).
- Vigentes: **ADR-012** (stack), **ADR-018/019** (gate + puente cola), norma "aprovisionar antes de degradar".

## 5. Próxima acción inmediata (para la nueva sesión) — DESPLEGAR EN RENDER
1. **Aplicar el Blueprint en Render** (guía completa: `docs/06-infrastructure/DEPLOY_RENDER.md`): New → Blueprint → repo `pedroxynox/mindOS` (rama `main`) → Apply. Crea las 4 piezas (Postgres+pgvector, Key Value, API, IA+worker) en **plan gratis** (para probar).
2. **Rellenar 3 valores** (sync:false): `OPENAI_API_KEY`, `DATABASE_URL` (rol no-owner `mindos_app:mindos_app@…`), `REDIS_PASSWORD`.
3. **Migraciones**: corren solas (preDeploy `prisma migrate deploy` como owner) — crean tablas, RLS, rol `mindos_app` y extensión pgvector. Si falla por permiso de CREATE ROLE/EXTENSION en la BD gestionada, ejecutarlo a mano una vez desde el shell de la BD (SQL en `infra/postgres-init/01-app-role.sql` + `CREATE EXTENSION vector;`).
4. **Verificar end-to-end**: `/v1/health` (API) y `/health` (IA) OK; en logs de IA "understanding worker started"; crear una captura y ver que se procesa.
5. **Cuando sea "de verdad" (24/7):** subir `mindos-api` y `mindos-ai` a plan **starter** (~$7 c/u) y la **base de datos a un plan de pago** (~$6–7, para que NO se borre a los ~30 días) — ver §6.

**Después del despliegue (siguientes trabajos de producto):** transcripción de voz (decidir cliente vs F2 con datos) y, más adelante, el **módulo Finanzas (V4)**.

## 6. Bloqueadores y avisos importantes
- **El despliegue es la única parte NO verificable desde el entorno de desarrollo** (sin acceso a Render/Docker). La config (`render.yaml`, Dockerfiles) es un scaffold correcto de mejor esfuerzo; se valida y afina en el **primer deploy** (ver deuda **D-011**).
- **Modo gratis (para probar):** los servicios se **duermen** a los ~15 min (despiertan lentos) y la **BD gratis se borra a los ~30 días**. Sirve para confirmar el circuito, NO para datos reales. El worker dormido no drena la cola 24/7 (despierta al recibir tráfico).
- **⚠ render.yaml en main quedó con los servicios en plan `starter` (PAGO)** porque el PR #55 se mergeó ANTES del ajuste a gratis. El fix a `plan: free` va en el PR de esta sesión (§13); **mergearlo antes de aplicar el Blueprint** para no incurrir en cobros.
- No hay bloqueadores de calidad ni de motor: R-001 resuelta, R-007 cerrado.

## 7. Riesgos vivos (detalle e historia en [012](./012_RISK_AND_DEBT_REGISTER.md))
- **R-001 (RESUELTA para el gate, 2026-07-09):** calidad de comprensión. v8: F1 0.890 / taskP 1.000 / hall 0.074 / $0.0023 = GATE PASSED con margen (OpenAI `gpt-5.4-mini`). Residual NO gated: connections F1 0.187 (graph-linking).
- **R-007 (cerrado):** motor F2 validado contra infra real.
- **R-005 (validado en F1), R-002 (mitigado), R-003 (mitigado), R-006 (cerrado), R-004 (en corrección).**

## 8. Deuda técnica top (detalle en [012](./012_RISK_AND_DEBT_REGISTER.md))
- **D-011 (nueva, abierta):** config de despliegue de Render (`render.yaml` + Dockerfiles) **no verificada** contra Render/Docker desde el entorno; validar en el primer deploy (permiso CREATE ROLE/EXTENSION en la BD gestionada, mapeo de Redis host/port/password).
- **D-008 (en progreso):** dimensión de embedding fijada en 1536; proveedor de embeddings definitivo pendiente.
- **D-010 (en progreso):** prompt consolidado (ahora en **v8**); ~28% menos tokens que el apilado v2+v3+v4; se puede cerrar tras confirmar estabilidad en producción.
- **D-005, D-006 (abiertos).** Cerrados/mitigados: D-001..D-004, D-007, D-009.

## 9. Salud de la arquitectura
Alta coherencia doc→código. El motor de F2 respeta el estilo de puertos (`AIProvider`, `GraphStore`), probable sin infra. La temperatura adaptativa del proveedor evita casarse con un nombre de modelo. La frontera de dos backends sigue bien definida (ADR-010). El despliegue es portable (Docker, ADR-015): si se quiere abaratar, la BD puede moverse a Neon (gratis) sin rediseño.

## 10. Cambios recientes (esta sesión, 2026-07-09)
- **R-001 RESUELTA:** OpenAI `gpt-5.4-mini` + prompt v6→v7→v8 → v8 GATE PASSED con margen (PRs #47/#49/#50/#51/#52/#53).
- **Temperatura adaptativa** en el proveedor OpenAI-compatible (desbloquea gpt-5.x/o-series sin perder determinismo en la mini).
- **Arranque del worker cableado** (`WORKER_ENABLED`, lifespan) — PR #54.
- **Voz decidida** (text-first/diferida) y **Finanzas anotada** (V4) — PR #54 / roadmap §3.1 / design §19.
- **Despliegue en Render preparado** (`render.yaml` + `DEPLOY_RENDER.md`; fixes de Dockerfiles) — PR #55 (+ fix a plan gratis en el PR de handoff).

## 11. Preguntas abiertas
- **¿Cuándo pasar a 24/7 de pago?** (hoy: gratis para probar). Decisión del founder según cuándo quiera uso real.
- **Transcripción de voz:** ¿cliente o F2? Decidido *diferir*; se elegirá con datos de calidad/latencia cuando toque.
- **Proveedor de embeddings definitivo** (D-008) → se fija con el motor en producción.

## 12. Acciones recomendadas (priorizadas)
1. **Mergear el PR de handoff** (este) para dejar `render.yaml` en gratis y el estado documentado.
2. **Aplicar el Blueprint en Render** (§5) y verificar el circuito end-to-end en gratis.
3. **Pasar a 24/7** (servicios starter + BD de pago) cuando el founder lo decida.
4. **Voz** y luego **Finanzas (V4)**.
5. Refrescar 009 y 012 al cierre (ritual [008](./008_AI_COLLABORATION_PROTOCOL.md)).

## 13. PRs de esta sesión (todos MERGEADOS salvo el de handoff)
- **#47** cableado OpenAI GPT-5.x (precios, default `gpt-5.4-mini`, Variable `OPENAI_MODEL`). **Mergeado.**
- **#49** Variable `EVAL_COST_PER_CAPTURE_MAX_USD` en el workflow del examen. **Mergeado.**
- **#50** fix `temperature` para GPT-5/o-series (luego reemplazado por adaptación en runtime en #51). **Mergeado.**
- **#51** prompt **v7** (recall) + temperatura adaptativa + registro decisión mini-vs-5.5. **Mergeado.**
- **#52** prompt **v8** (baja alucinación conservando recall). **Mergeado.**
- **#53** registro de R-001 v8 GATE PASSED en 009/012. **Mergeado.**
- **#54** arranque del worker (`WORKER_ENABLED`) + ficha Finanzas (V4) + decisión de voz. **Mergeado.**
- **#55** Blueprint de Render + guía + fixes de Dockerfiles. **Mergeado** (⚠ con servicios en `starter`; ver §6).
- **PR de handoff (este):** este 009 + 012 + **fix `render.yaml` a plan gratis**. Pendiente de merge.

## 14. Nota para la nueva sesión (importante)
- **Hablar en español y en lenguaje no técnico** con el founder (CEO no programador); actuar como **CPTO con pensamiento crítico**.
- **NO relajar umbrales ni gold** para "aprobar": el rigor es el producto.
- **Patrón observado:** el founder a veces **mergea los PRs ANTES** de que yo suba un ajuste de seguimiento a la misma rama → SIEMPRE verificar el estado REAL de `main` (`list_pull_requests` + pull) antes de asumir qué está desplegado. Ya pasó con #51 (v7 en vez de v8) y #55 (starter en vez de free).
- **Siguiente hito:** DESPLEGAR EN RENDER siguiendo `docs/06-infrastructure/DEPLOY_RENDER.md` (empezar gratis). El motor está listo para encenderse; falta el "enchufe" del servidor.
- **Mantener el ritual:** actualizar 009 y 012 al cierre.

## Historial de versiones
| Versión | Fecha | Cambios |
|---------|-------|---------|
| 1.0–1.8 | 2026-07-02/03 | Fundación de la gobernanza → F1 completada, validada (R-006) y ADRs consolidados (ver 012 para el detalle cronológico). |
| 1.9 | 2026-07-03 | Foco en F2/R-001: medición estable (Groq, prompt v3/v5), decisión de iterar hacia hallucination ≤0.10, proveedor Gemini; bloqueo por cupos free-tier; PR #40. |
| 1.10 | 2026-07-09 | Gate de F2 ratificado (ADR-018) y motor CONSTRUIDO (PR #45): Groq 0.782/0.930/0.091; motor F2 + migración pgvector/`llm_usage`, 84 tests offline. Alta de R-007; D-008 en progreso. |
| 1.11 | 2026-07-09 | PR #45 mergeado y motor VALIDADO contra infra real → R-007 cerrado (Postgres 18 + pgvector + Redis 6; 5/5 integración; fix `nodes.updated_at`). PR #40 mergeado. 97 offline + 5 integración. |
| 1.12 | 2026-07-09 | Gate SUPERADO por primera vez (OpenAI `gpt-5.4-mini`, F1 0.819/1.000/0.059) → R-001 mitigado; decisión mini vs 5.5. PRs #47/#49/#50. |
| 1.13 | 2026-07-09 | R-001 RESUELTA para el gate: prompt v6→v7→v8; v8 F1 0.890/1.000/0.074 = PASS con margen. PRs #51/#52/#53. |
| 1.14 | 2026-07-09 | **Cierre de sesión (handoff):** arranque del worker cableado (`WORKER_ENABLED`, PR #54); voz decidida (text-first/diferida) y Finanzas anotada V4 (PR #54); despliegue en Render preparado (`render.yaml` + `DEPLOY_RENDER.md`, PR #55) con fixes de Dockerfiles; alta de deuda **D-011** (config de deploy no verificada). Documentación completa del estado y lo que falta (desplegar en Render, empezar gratis). Nota: `render.yaml` en main quedó en `starter`; este PR lo pasa a gratis. Suite 100 offline + 5 integración; ruff/mypy limpios. |
