# 009 — Current State (estado vivo del proyecto)

> 🔴 DOCUMENTO OBLIGATORIO. Se actualiza al CIERRE de CADA sesión (ritual en [008](./008_AI_COLLABORATION_PROTOCOL.md)). Es una FOTO que se sobreescribe. La historia cronológica y el detalle de riesgos/deuda viven en [012](./012_RISK_AND_DEBT_REGISTER.md).

| Metadato | Valor |
|----------|-------|
| Última actualización | 2026-07-09 |
| Fase actual | F1 (Capture Engine) **COMPLETA y validada** (R-006 cerrado). F2 (Comprensión): **gate de calidad RATIFICADO** ([ADR-018](../02-architecture/adr/ADR-018-f2-comprehension-eval-gate.md), camino B) y **motor de comprensión CONSTRUIDO y verificado offline** (rama `feat/f2-comprehension-engine`); falta validarlo contra infra real (R-007) y cerrar la brecha de recall de *topics* (R-001). |
| Avance estimado del MVP (F0–F5) | ~38 % |

## 1. Resumen ejecutivo
F1 (Capture Engine) está **cerrada y verificada contra infraestructura real** (R-006 cerrado): captura offline-first, grafo `nodes`/`edges` con RLS fail-closed, `POST /v1/captures` idempotente, cola BullMQ, reconciliación y janitor; auth endurecida; builds reproducibles en las 3 apps.

El trabajo de HOY: llegó la **corrida estable del examen de F2** (45 casos, Groq): F1 entities **0.782**, task precision **0.930**, hallucination **0.091**, coste **$0**. El founder eligió el **camino B**: **ratificar umbrales realistas** ([ADR-018](../02-architecture/adr/ADR-018-f2-comprehension-eval-gate.md): hallucination ≤0.10 realista con 0.05 como aspiración; F1 ≥0.80 y taskP ≥0.85 sin cambio; **sin relajar el gold**) y **arrancar el motor de F2 en paralelo**, asumiendo el riesgo explícito del F1 marginal (0.782, por recall de *topics*). Fundamento: la plomería de escritura del motor es **ortogonal** a la calidad de extracción.

Se **construyó el motor de comprensión (F2)** completo a nivel de lógica, siguiendo el diseño (`.kiro/specs/comprehension/design.md`): worker BullMQ (ADR-019), pipeline, escritura idempotente al grafo bajo RLS con provenance obligatoria, coste por usuario y embeddings (pgvector). Todo el núcleo puro está cubierto con unit + property tests **offline** (84 tests verdes, `ruff`/`mypy` limpios). Falta **validar los adaptadores reales contra Postgres/Redis** (R-007) y una **iteración de prompt** para subir el recall de *topics* por encima de 0.80 (R-001).

## 2. Qué existe hoy (verificado, ya en main)
- **F1 end-to-end** (captura offline-first, grafo + RLS fail-closed, `POST /v1/captures` idempotente, cola BullMQ, reconciliación, janitor), **auth endurecida**, **builds reproducibles**, validación de integración **8/8** contra infra real (R-006), **ADRs consolidados** 001..017.
- **Arnés de evaluación de F2** (`apps/ai/app/eval/`), **extractor** (`app/understanding/extract.py`, prompt v3 en main) y capa **`AIProvider`** intercambiable (`fake`/`openai`/`groq`).

## 3. Qué se construyó HOY (rama `feat/f2-comprehension-engine`, en PR, NO en main)
- **Gate ratificado por ADR** — [ADR-018](../02-architecture/adr/ADR-018-f2-comprehension-eval-gate.md) (umbrales realistas del examen) y [ADR-019](../02-architecture/adr/ADR-019-queue-python-consumer-bridge.md) (puente cola↔Python = consumidor BullMQ nativo; el "ADR-013 pendiente" del borrador se renumeró porque 013 ya estaba ocupado).
- **Motor de comprensión (F2)** en `apps/ai/app/understanding/`:
  - `contract.py` (espejo del job de F1), `enrichment.py` (mapeo **puro** extracción→plan de nodos/aristas con `dedup_key` determinista y provenance), `store.py` (**puerto** `GraphStore` + `InMemoryGraphStore` para tests), `rls.py` (contexto RLS fail-closed), `cost_meter.py` (coste por usuario), `graph_writer.py` (`PgGraphStore`: SQL crudo idempotente bajo RLS), `pipeline.py` (orquestación con idempotencia y estados), `worker.py` (consumidor BullMQ + `on_failed`).
  - **Migración F2** (`apps/api/prisma/migrations/20260709010000_f2_pgvector_enrichment`): extensión `vector`, `nodes.embedding vector(1536)` + `embedding_model`, índice HNSW parcial, índices únicos parciales de idempotencia en `nodes`/`edges`, tabla `llm_usage` con RLS fail-closed y grants a `mindos_app`. Reflejada en `schema.prisma` (`Unsupported("vector(1536)")` + modelo `LlmUsage`), `prisma validate` OK.
  - **Pruebas nuevas**: `test_contract`, `test_enrichment` (PBT: idempotencia/provenance/no-invención), `test_pipeline` (end-to-end con `FakeProvider`+`InMemory`), `test_worker`. Total **84 tests** verdes; `ruff`/`mypy` limpios.
- **`asyncpg` y `bullmq`** añadidos como dependencias **opcionales** (`extra [ai]`), con **import perezoso**, de modo que la suite offline y el CI no los requieren.

## 4. Última decisión
- **Camino B (founder):** ratificar umbrales realistas (ADR-018) y **construir el motor de F2 ya**, asumiendo el riesgo del F1 marginal (0.782). **No** se relaja el gold ni el piso de F1 (0.80).
- **ADR-019:** consumidor BullMQ **nativo en Python** (contingencia documentada a worker Node+HTTP).
- Vigentes: **ADR-012** (stack canónico), **ADR-011** (DoD de F0), norma "aprovisionar antes de degradar" ([008](./008_AI_COLLABORATION_PROTOCOL.md)).

## 5. Próxima acción inmediata (para la nueva sesión)
1. **Validar el motor contra infra real (R-007):** aplicar la migración F2 sobre Postgres con `pgvector`, y tests de integración del `worker` (consumo, reintentos/backoff, dedup por `jobId`, `removeOnFail:false`) y del `GraphWriter` (idempotencia P-COMP-1/2/3, aislamiento RLS P-COMP-4, coste) contra Postgres+Redis reales — el mismo patrón que cerró R-006.
2. **Cerrar la brecha de recall de *topics* (R-001):** iteración honesta de prompt para subir F1 entities por encima de 0.80 sin subir la alucilación (aprovechar el trabajo de prompt v5 del **PR #40**, aún abierto).
3. **Cablear el arranque del worker** en el servicio de IA (hoy `main.py` solo expone `/health`) y decidir la **transcripción de voz** (hoy el pipeline deja un *seam* que exige `body`).
4. Refrescar 009 y 012 al cierre.

## 6. Bloqueadores
Ninguno bloquea la construcción del motor (ya hecha y verificada offline). La **validación contra infra real (R-007)** requiere aprovisionar Postgres+`pgvector`+Redis (no hay Docker en el entorno, pero se aprovisionó nativamente para R-006; se puede repetir). La **medición de calidad** de F2 sigue dependiendo de completar corridas del examen (cupos de free-tier), pero **ya no bloquea** el arranque del motor.

## 7. Riesgos vivos (detalle e historia en [012](./012_RISK_AND_DEBT_REGISTER.md))
- **R-001 (Alto, abierto):** calidad de comprensión. Medición estable (Groq): entities F1 **0.782** (por debajo de 0.80 por recall de *topics*), taskP 0.930, hallucination 0.091. Gate ratificado (ADR-018); pendiente iteración de prompt para el recall.
- **R-007 (Medio, abierto — NUEVO):** el motor de F2 solo está validado offline (puerto en memoria + `FakeProvider`); falta integración real Postgres/Redis.
- **R-005 (validado en F1), R-002 (mitigado), R-003 (mitigado), R-006 (cerrado), R-004 (en corrección).**

## 8. Deuda técnica top (detalle en [012](./012_RISK_AND_DEBT_REGISTER.md))
- **D-008 (en progreso):** dimensión de embedding fijada en **1536** para construir el motor; elección definitiva de proveedor de embeddings pendiente del gate.
- **D-010 (en progreso, vive en PR #40):** prompt de extracción consolidado en v5 (~28% menos tokens), pendiente de re-medir.
- **D-005, D-006 (abiertos).** Mitigados/cerrados: D-001..D-004, D-007, D-009.

## 9. Salud de la arquitectura
Alta coherencia doc→código. El motor de F2 respeta el diseño y el estilo de puertos del repo (`AIProvider`, `UnderstandingQueuePort` → nuevo `GraphStore`), lo que permite probar toda la lógica sin infraestructura. La frontera de dos backends sigue bien definida (ADR-010).

## 10. Cambios recientes
- **Gate de F2 ratificado** (ADR-018, camino B) con la corrida estable de Groq (0.782 / 0.930 / 0.091).
- **Motor de comprensión F2 construido** y verificado offline (84 tests, ruff/mypy limpios); migración pgvector + `llm_usage`; ADR-019 (puente cola).
- Alta de **R-007**; D-008 a "en progreso" (dim 1536).
- **PR #40** (prompt v5 + proveedor Gemini) sigue **abierto** y **es la palanca para cerrar R-001** (recall de *topics*); es un esfuerzo **paralelo** a la rama del motor.

## 11. Preguntas abiertas
- **¿La iteración de prompt (v5/PR #40) sube F1 entities por encima de 0.80** sin dañar la alucinación? → pendiente de una corrida que complete.
- **Proveedor de embeddings definitivo** (D-008) → se fija tras cerrar el gate.
- **Transcripción de voz**: ¿cliente o F2? El pipeline soporta el *seam*; decisión pendiente con datos.

## 12. Acciones recomendadas (priorizadas)
1. **Validar el motor de F2 contra infra real** (cerrar R-007) con el patrón de R-006.
2. **Iterar el prompt** para cerrar el recall de *topics* (R-001) — coordinar con PR #40.
3. **Cablear el worker** en el arranque del servicio de IA y resolver la transcripción de voz.
4. Refrescar 009 y 012 al cierre (ritual [008](./008_AI_COLLABORATION_PROTOCOL.md)).

## 13. PRs abiertos
- **`feat/f2-comprehension-engine`** (esta sesión): gate ratificado (ADR-018/019) + **motor de comprensión F2** + migración pgvector/`llm_usage`, verificado offline (84 tests). Falta validación de infra real (R-007) antes de considerarlo "hecho".
- **PR #40** (`fix/f2-eval-prompt-v4`): prompt **v5** + proveedor **Gemini** + resiliencia del examen. Palanca para cerrar R-001; **no mergear** hasta validar v5 con una corrida que COMPLETE.

## 14. Nota para la nueva sesión (importante)
- **Hablar en español y en lenguaje no técnico** con el founder (CEO no programador); actuar como **CPTO con pensamiento crítico**.
- **NO relajar umbrales ni gold** para "aprobar": el rigor es el producto. El gate ratificado (ADR-018) es honesto, no un maquillaje.
- **Mantener el ritual:** actualizar 009 y 012 al cierre.
- El motor de F2 está construido pero **NO validado contra infra real** (R-007): no declararlo "terminado" hasta cerrar esa validación.

## Historial de versiones
| Versión | Fecha | Cambios |
|---------|-------|---------|
| 1.0–1.8 | 2026-07-02/03 | Fundación del sistema de gobernanza → F1 completada, validada (R-006) y ADRs consolidados (ver 012 para el detalle cronológico). |
| 1.9 | 2026-07-03 | Foco en F2/R-001: medición estable de 45 casos (Groq, prompt v3/v5), decisión de iterar hacia hallucination ≤0.10, proveedor Gemini añadido; bloqueo por cupos de free-tier; trabajo en PR #40. |
| 1.10 | 2026-07-09 | **Gate de F2 ratificado (ADR-018, camino B) y motor de comprensión CONSTRUIDO** (rama `feat/f2-comprehension-engine`): corrida estable de Groq (0.782/0.930/0.091); ADR-018 (umbrales realistas, sin relajar gold) + ADR-019 (puente cola BullMQ nativo); motor F2 (contrato, `enrichment` puro, puerto `GraphStore`+`InMemory`+`PgGraphStore`, `rls`, `cost_meter`, `pipeline`, `worker`) + migración pgvector/`llm_usage`, verificado **offline** (84 tests, ruff/mypy limpios). Alta de **R-007** (motor no validado aún contra infra real); D-008 a "en progreso" (dim 1536). R-001 sigue abierto por recall de *topics*. |
