# 009 — Current State (estado vivo del proyecto)

> 🔴 DOCUMENTO OBLIGATORIO. Se actualiza al CIERRE de CADA sesión (ritual en [008](./008_AI_COLLABORATION_PROTOCOL.md)). Es una FOTO que se sobreescribe. La historia cronológica y el detalle de riesgos/deuda viven en [012](./012_RISK_AND_DEBT_REGISTER.md).

| Metadato | Valor |
|----------|-------|
| Última actualización | 2026-07-09 |
| Fase actual | F1 (Capture Engine) **COMPLETA y validada** (R-006 cerrado). F2 (Comprensión): **gate de calidad RATIFICADO** ([ADR-018](../02-architecture/adr/ADR-018-f2-comprehension-eval-gate.md), camino B), **motor de comprensión CONSTRUIDO** (PR #45 **mergeado**) y **VALIDADO contra infra real** (Postgres+pgvector y Redis/BullMQ; **R-007 cerrado**). **NUEVO (2026-07-09): el gate se SUPERA por primera vez en corrida REAL COMPLETA con OpenAI de pago (`gpt-5.4-mini`): F1 0.819 / taskP 1.000 / hall 0.059 / $0.0019 = GATE PASSED → R-001 MITIGADO.** Pendiente (no bloqueante): subir el recall (0.726) sin subir la alucinación; cablear el arranque del worker y la transcripción de voz. |
| Avance estimado del MVP (F0–F5) | ~40 % |

## 1. Resumen ejecutivo
F1 (Capture Engine) está **cerrada y verificada contra infraestructura real** (R-006 cerrado): captura offline-first, grafo `nodes`/`edges` con RLS fail-closed, `POST /v1/captures` idempotente, cola BullMQ, reconciliación y janitor; auth endurecida; builds reproducibles en las 3 apps.

El trabajo de HOY: llegó la **corrida estable del examen de F2** (45 casos, Groq): F1 entities **0.782**, task precision **0.930**, hallucination **0.091**, coste **$0**. El founder eligió el **camino B**: **ratificar umbrales realistas** ([ADR-018](../02-architecture/adr/ADR-018-f2-comprehension-eval-gate.md): hallucination ≤0.10 realista con 0.05 como aspiración; F1 ≥0.80 y taskP ≥0.85 sin cambio; **sin relajar el gold**) y **arrancar el motor de F2 en paralelo**, asumiendo el riesgo explícito del F1 marginal (0.782, por recall de *topics*). Fundamento: la plomería de escritura del motor es **ortogonal** a la calidad de extracción.

Se **construyó el motor de comprensión (F2)** completo (PR #45, **mergeado**), siguiendo el diseño (`.kiro/specs/comprehension/design.md`): worker BullMQ (ADR-019), pipeline, escritura idempotente al grafo bajo RLS con provenance obligatoria, coste por usuario y embeddings (pgvector). Luego se **VALIDÓ contra infraestructura REAL** (PostgreSQL 18 + pgvector compilado + Redis 6, aprovisionados nativamente sin Docker; migraciones F1+F2 aplicadas; **5/5 tests de integración en verde** como rol no-owner con FORCE RLS): idempotencia, provenance, aislamiento por usuario, coste y consumo end-to-end por la cola. Esa validación **halló y corrigió un bug de producto** (el SQL crudo no fijaba `nodes.updated_at`, `NOT NULL`). **R-007 cerrado.** Suite total: 97 offline + 5 integración, `ruff`/`mypy` limpios. Pendiente: **iteración de prompt** para subir el recall de *topics* por encima de 0.80 (R-001), cablear el arranque del worker y la transcripción de voz.

## 2. Qué existe hoy (verificado, ya en main)
- **F1 end-to-end** (captura offline-first, grafo + RLS fail-closed, `POST /v1/captures` idempotente, cola BullMQ, reconciliación, janitor), **auth endurecida**, **builds reproducibles**, validación de integración **8/8** contra infra real (R-006), **ADRs consolidados** 001..017.
- **Arnés de evaluación de F2** (`apps/ai/app/eval/`), **extractor** (`app/understanding/extract.py`, prompt v3 en main) y capa **`AIProvider`** intercambiable (`fake`/`openai`/`groq`).

## 3. Qué se construyó y validó (PR #45 mergeado + validación de infra real)
- **Gate ratificado por ADR** — [ADR-018](../02-architecture/adr/ADR-018-f2-comprehension-eval-gate.md) (umbrales realistas del examen) y [ADR-019](../02-architecture/adr/ADR-019-queue-python-consumer-bridge.md) (puente cola↔Python = consumidor BullMQ nativo; el "ADR-013 pendiente" del borrador se renumeró porque 013 ya estaba ocupado).
- **Motor de comprensión (F2)** en `apps/ai/app/understanding/`:
  - `contract.py` (espejo del job de F1), `enrichment.py` (mapeo **puro** extracción→plan de nodos/aristas con `dedup_key` determinista y provenance), `store.py` (**puerto** `GraphStore` + `InMemoryGraphStore` para tests), `rls.py` (contexto RLS fail-closed), `cost_meter.py` (coste por usuario), `graph_writer.py` (`PgGraphStore`: SQL crudo idempotente bajo RLS), `pipeline.py` (orquestación con idempotencia y estados), `worker.py` (consumidor BullMQ + `on_failed`).
  - **Migración F2** (`apps/api/prisma/migrations/20260709010000_f2_pgvector_enrichment`): extensión `vector`, `nodes.embedding vector(1536)` + `embedding_model`, índice HNSW parcial, índices únicos parciales de idempotencia en `nodes`/`edges`, tabla `llm_usage` con RLS fail-closed y grants a `mindos_app`. Reflejada en `schema.prisma` (`Unsupported("vector(1536)")` + modelo `LlmUsage`), `prisma validate` OK.
  - **Pruebas nuevas**: `test_contract`, `test_enrichment` (PBT: idempotencia/provenance/no-invención), `test_pipeline` (end-to-end con `FakeProvider`+`InMemory`), `test_worker`. Total **84 tests** verdes; `ruff`/`mypy` limpios.
- **`asyncpg` y `bullmq`** añadidos como dependencias **opcionales** (`extra [ai]`), con **import perezoso**, de modo que la suite offline y el CI no los requieren.
- **Validación contra infra REAL (R-007 cerrado, rama `test/f2-engine-real-infra-validation`):** PostgreSQL 18 + **pgvector compilado desde fuente** + pgcrypto + Redis 6 aprovisionados nativamente; migraciones F1+F2 aplicadas con el rol OWNER; **5/5 tests de integración en verde** como rol no-owner `mindos_app` (FORCE RLS real) — `test_graph_writer_integration` (idempotencia P-COMP-1/2, provenance P-COMP-3, aislamiento P-COMP-4, coste, embedding) y `test_worker_integration` (dedup por `jobId` + consumo end-to-end contra Redis/BullMQ). Esta validación **halló y corrigió un bug de producto**: el SQL crudo del `PgGraphStore` no fijaba `nodes.updated_at` (`NOT NULL`, gestionado por Prisma `@updatedAt`) → arreglado con `updated_at = now()`.

## 4. Última decisión
- **(2026-07-09) Proveedor de comprensión = OpenAI `gpt-5.4-mini`.** El founder pagó $5 en OpenAI (giro respecto a v1.21) para de-riesgar el recall. Se probaron dos modelos en corrida REAL de 45 casos: `gpt-5.4-mini` (F1 0.819 / taskP 1.000 / hall 0.059 / $0.0019 = **GATE PASSED**) y el flagship `gpt-5.5` (F1 0.866 / taskP 0.976 / hall 0.072 / $0.0236 = FAIL solo por coste). **Se elige la mini**: la 5.5 atrapa más recall pero **inventa más** (0.072 vs 0.059) y cuesta **~12x**. Cambios habilitadores: PR #47 (cableado GPT-5.x + default mini + Variable `OPENAI_MODEL`), PR #50 (fix `temperature` para GPT-5/o-series), PR #49 (Variable `EVAL_COST_PER_CAPTURE_MAX_USD`).
- **Camino B (founder):** ratificar umbrales realistas (ADR-018) y **construir el motor de F2 ya**, asumiendo el riesgo del F1 marginal (0.782). **No** se relaja el gold ni el piso de F1 (0.80).
- **ADR-019:** consumidor BullMQ **nativo en Python** (contingencia documentada a worker Node+HTTP).
- Vigentes: **ADR-012** (stack canónico), **ADR-011** (DoD de F0), norma "aprovisionar antes de degradar" ([008](./008_AI_COLLABORATION_PROTOCOL.md)).

## 5. Próxima acción inmediata (para la nueva sesión)
1. **VALIDAR el prompt v8 (PR #51) con una corrida de `gpt-5.4-mini` (~$0.09):** v7 ya demostró que el recall SUBE (0.726→0.857) pero cruzó la alucinación (0.118>0.10); v8 re-aprieta las tres exclusiones (objeto/dispositivo físico, lugar, grupo genérico) conservando la subida de recall. Objetivo: F1 ~0.87 / recall ~0.85 / hallucination ≤0.10. Es un *fast-follow* de R-001 (YA NO bloqueante: v6 ya supera el gate). Si v8 no baja la alucinación bajo 0.10 sin perder el recall, revertir a v6.
2. **Cablear el arranque del worker** en el servicio de IA (hoy `main.py` solo expone `/health`) y decidir la **transcripción de voz** (hoy el pipeline deja un *seam* que exige `body`).
3. Refrescar 009 y 012 al cierre.

## 6. Bloqueadores
Ninguno bloquea el motor: construido, mergeado y **validado contra infra real** (R-007 cerrado). La única deuda de calidad viva es el **recall de *topics*** (R-001), que se cierra con iteración de prompt (depende de completar corridas del examen; cupos de free-tier).

## 7. Riesgos vivos (detalle e historia en [012](./012_RISK_AND_DEBT_REGISTER.md))
- **R-001 (Alto, MITIGADO 2026-07-09):** calidad de comprensión. **Gate SUPERADO por primera vez en corrida REAL COMPLETA** con OpenAI `gpt-5.4-mini`: entities F1 **0.819** (P 0.941 / R 0.726), taskP **1.000**, hallucination **0.059**, coste **$0.0019** = **GATE PASSED**. (Antes con Groq/prompt v5: F1 0.782.) Deuda residual viva (no bloqueante): subir el **recall (0.726)** sin subir la alucinación = *fast-follow* de iteración de prompt.
- **R-007 (cerrado):** motor de F2 validado contra Postgres+pgvector y Redis/BullMQ reales (5/5 integración); bug de `updated_at` hallado y corregido.
- **R-005 (validado en F1), R-002 (mitigado), R-003 (mitigado), R-006 (cerrado), R-004 (en corrección).**

## 8. Deuda técnica top (detalle en [012](./012_RISK_AND_DEBT_REGISTER.md))
- **D-008 (en progreso):** dimensión de embedding fijada en **1536** para construir el motor; elección definitiva de proveedor de embeddings pendiente del gate.
- **D-010 (en progreso, vive en PR #40):** prompt de extracción consolidado en v5 (~28% menos tokens), pendiente de re-medir.
- **D-005, D-006 (abiertos).** Mitigados/cerrados: D-001..D-004, D-007, D-009.

## 9. Salud de la arquitectura
Alta coherencia doc→código. El motor de F2 respeta el diseño y el estilo de puertos del repo (`AIProvider`, `UnderstandingQueuePort` → nuevo `GraphStore`), lo que permite probar toda la lógica sin infraestructura. La frontera de dos backends sigue bien definida (ADR-010).

## 10. Cambios recientes
- **(2026-07-09) Prompt v7 MEDIDO + v8 corrige (PR #51).** v7 subió el recall **0.726→0.857** y F1 **0.819→0.870** (taskP 1.000), PERO la alucinación subió **0.059→0.118** (>0.10) → GATE FAILED solo por alucinación (v7 ensanchó `topic` a objetos/dispositivos físicos, lugares y grupos genéricos que el gold excluye). **v8** conserva la subida de recall y re-aprieta esas tres exclusiones; **PENDIENTE de una corrida de la mini (~$0.09)** para confirmar F1 ~0.87 / recall ~0.85 / alucinación ≤0.10.
- **(2026-07-09) Gate SUPERADO con OpenAI `gpt-5.4-mini` → R-001 mitigado.** Cableado OpenAI GPT-5.x (PR #47), fix de `temperature` para GPT-5/o-series (PR #50) y Variable de coste (PR #49). Corridas reales: mini = GATE PASSED (0.819 / 1.000 / 0.059 / $0.0019); 5.5 = FAIL solo por coste (0.866 / 0.976 / 0.072 / $0.0236). Decisión: usar la mini.
- **Gate de F2 ratificado** (ADR-018, camino B) con la corrida estable de Groq (0.782 / 0.930 / 0.091).
- **Motor de comprensión F2 construido y mergeado** (PR #45): migración pgvector + `llm_usage`, ADR-018/019.
- **Motor VALIDADO contra infra real** (Postgres 18 + pgvector + Redis 6 nativos): 5/5 tests de integración verdes; **R-007 cerrado**; corregido un bug de producto (`nodes.updated_at`).
- **PR #40 mergeado** (prompt v5 + proveedor Gemini): palanca para cerrar R-001 (recall de *topics*).
- D-008 a "en progreso" (dim 1536).

## 11. Preguntas abiertas
- **¿La iteración de prompt (v5/PR #40) sube F1 entities por encima de 0.80** sin dañar la alucinación? → pendiente de una corrida que complete.
- **Proveedor de embeddings definitivo** (D-008) → se fija tras cerrar el gate.
- **Transcripción de voz**: ¿cliente o F2? El pipeline soporta el *seam*; decisión pendiente con datos.

## 12. Acciones recomendadas (priorizadas)
1. **Validar el motor de F2 contra infra real** (cerrar R-007) con el patrón de R-006.
2. **Iterar el prompt** para cerrar el recall de *topics* (R-001) — coordinar con PR #40.
3. **Cablear el worker** en el arranque del servicio de IA y resolver la transcripción de voz.
4. Refrescar 009 y 012 al cierre (ritual [008](./008_AI_COLLABORATION_PROTOCOL.md)).

## 13. PRs
- **PR #45** (`feat/f2-comprehension-engine`): gate ratificado (ADR-018/019) + **motor de comprensión F2** + migración pgvector/`llm_usage`. **MERGEADO.**
- **PR #40** (`fix/f2-eval-prompt-v4`): prompt **v5** + proveedor **Gemini** + resiliencia del examen. **MERGEADO.**
- **`test/f2-engine-real-infra-validation`** (esta sesión): tests de integración contra infra real + fix del bug `updated_at` (R-007). **Abierto**, listo para revisión/merge.

## 14. Nota para la nueva sesión (importante)
- **Hablar en español y en lenguaje no técnico** con el founder (CEO no programador); actuar como **CPTO con pensamiento crítico**.
- **NO relajar umbrales ni gold** para "aprobar": el rigor es el producto. El gate ratificado (ADR-018) es honesto, no un maquillaje.
- **Mantener el ritual:** actualizar 009 y 012 al cierre.
- El motor de F2 está construido, mergeado y **validado contra infra real** (R-007 cerrado). Lo que queda de F2 antes de "terminado de verdad": cerrar el recall de *topics* (R-001), cablear el arranque del worker y la transcripción de voz.

## Historial de versiones
| Versión | Fecha | Cambios |
|---------|-------|---------|
| 1.0–1.8 | 2026-07-02/03 | Fundación del sistema de gobernanza → F1 completada, validada (R-006) y ADRs consolidados (ver 012 para el detalle cronológico). |
| 1.9 | 2026-07-03 | Foco en F2/R-001: medición estable de 45 casos (Groq, prompt v3/v5), decisión de iterar hacia hallucination ≤0.10, proveedor Gemini añadido; bloqueo por cupos de free-tier; trabajo en PR #40. |
| 1.10 | 2026-07-09 | **Gate de F2 ratificado (ADR-018, camino B) y motor de comprensión CONSTRUIDO** (rama `feat/f2-comprehension-engine`): corrida estable de Groq (0.782/0.930/0.091); ADR-018 (umbrales realistas, sin relajar gold) + ADR-019 (puente cola BullMQ nativo); motor F2 (contrato, `enrichment` puro, puerto `GraphStore`+`InMemory`+`PgGraphStore`, `rls`, `cost_meter`, `pipeline`, `worker`) + migración pgvector/`llm_usage`, verificado **offline** (84 tests, ruff/mypy limpios). Alta de **R-007** (motor no validado aún contra infra real); D-008 a "en progreso" (dim 1536). R-001 sigue abierto por recall de *topics*. |
| 1.11 | 2026-07-09 | **PR #45 mergeado y motor de F2 VALIDADO contra infra real → R-007 cerrado.** Aprovisionado nativamente (sin Docker) PostgreSQL 18 + **pgvector compilado** + pgcrypto + Redis 6; migraciones F1+F2 aplicadas con el OWNER; **5/5 tests de integración en verde** como rol no-owner `mindos_app` (FORCE RLS real): `PgGraphStore` (idempotencia P-COMP-1/2, provenance P-COMP-3, aislamiento P-COMP-4, coste, embedding) y worker BullMQ (dedup por `jobId` + consumo end-to-end). **Bug de producto corregido** gracias a la validación: el SQL crudo no fijaba `nodes.updated_at` (`NOT NULL`) → `updated_at = now()`. Rama `test/f2-engine-real-infra-validation`. PR #40 también mergeado. Suite: 97 offline + 5 integración; ruff/mypy limpios. |
| 1.12 | 2026-07-09 | **Gate de F2 SUPERADO por primera vez en corrida REAL COMPLETA → R-001 MITIGADO.** El founder pagó $5 en OpenAI (giro respecto a v1.21) para de-riesgar el recall. Cableada la capa `AIProvider` a OpenAI GPT-5.x (PR #47: precios + default `gpt-5.4-mini` + Variable `OPENAI_MODEL`); corregido un bug que bloqueaba la línea GPT-5/o-series (PR #50: rechazan `temperature` custom con HTTP 400; ahora se omite salvo en modelos que lo soportan); añadida la Variable `EVAL_COST_PER_CAPTURE_MAX_USD` (PR #49). Dos corridas de 45 casos sin tocar gold/umbrales: `gpt-5.4-mini` → F1 **0.819** / taskP **1.000** / hall **0.059** / **$0.0019** = **GATE PASSED**; `gpt-5.5` → F1 0.866 / taskP 0.976 / hall 0.072 / $0.0236 = FAIL solo por coste. **Decisión: usar `gpt-5.4-mini`** (la 5.5 atrapa más recall pero inventa más y cuesta ~12x). Fast-follow vivo: subir el recall (0.726) sin subir la alucinación. Detalle en 012 (R-001, v1.29). |
