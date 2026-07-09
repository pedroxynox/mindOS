# ADR-019 — Puente cola↔Python: consumidor BullMQ nativo en Python

> **Architecture Decision Record.** Ratifica la decisión de diseño de F2 §9
> (allí anotada como "ADR-013 pendiente" **antes** de la renumeración de ADRs;
> el número 013 ya está ocupado por el estilo de API, así que esta decisión toma
> el siguiente número libre, **019**). Habilita el motor de comprensión (F2).

| Metadato | Valor |
|----------|-------|
| Estado | 🟢 Aceptado |
| Fecha | 2026-07-09 |
| Autor | CPTO |
| Origen | Diseño de comprensión (F2) §9 (decisión "(b) recomendada") |
| Relacionado | [ADR-006](./ADR-006-redis-queue-cache.md) (Redis/cola), [ADR-010](./ADR-010-final-stack-and-two-backends.md) (dos backends), [ADR-012](./ADR-012-canonical-stack.md) (BullMQ) |

---

## Contexto

BullMQ nace en el ecosistema Node/Redis, pero la lógica de comprensión de F2
(LangGraph, escritura al grafo) vive en Python. F1 ya **produce** el trabajo
`understanding.process` a la cola `understanding` con `jobId = capture_id`
(idempotencia de handoff). Hay que decidir cómo lo **consume** Python sin romper
ese contrato ya en producción.

## Decisión

Adoptar un **consumidor BullMQ nativo en Python** (paquete oficial `bullmq` de
taskforcesh): un proceso Python consume la cola `understanding` directamente y
ejecuta el pipeline de comprensión, respetando el contrato de F1 tal cual.

Mitigaciones a la menor madurez del port Python:

- **Fijar versión** del paquete `bullmq` en las dependencias.
- **Tests de integración contra Redis real** que cubran: consumo, reintentos con
  backoff, dedup por `jobId` (P-COMP-1) y `removeOnFail:false`.

## Estado

🟢 Aceptado.

## Consecuencias

- **Una sola pieza** por job: el ciclo de vida se co-loca con LangGraph y el
  `GraphWriter`; sin salto de red extra ni segundo proceso Node.
- Se honra el contrato y el productor de F1 sin cambios.
- Dependencia de un port menos maduro; se acota fijando versión y con integración
  real contra Redis.

## Alternativas consideradas

- **(a) Worker Node fino + HTTP a Python.** Dos procesos y un salto de red por
  job; llamadas LLM largas sobre HTTP. Queda como **contingencia** documentada: si
  el port Python resulta insuficiente en operación, se antepone un consumidor Node
  que invoca `run_understanding` por un endpoint interno — el pipeline y el
  `GraphWriter` no cambian.
- **(c) Cambiar la tecnología de cola** (Celery/arq/taskiq/Redis Streams).
  Rechazado: rompería el contrato y el productor de F1 ya mergeado y contradiría
  ADR-012.
