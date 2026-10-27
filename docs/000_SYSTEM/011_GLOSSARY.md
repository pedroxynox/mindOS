# 011 — Glossary (Lenguaje Ubicuo)

| Metadato | Valor |
|----------|-------|
| Versión | 1.1 |
| Estado | 🟢 Vigente |
| Ámbito | Definiciones canónicas de los términos de mindOS |
| Depende de | Cadena #00–#08 |
| Última actualización | 2026-10-27 |

Definiciones canónicas de 1–2 líneas. La columna **Fuente** indica el documento autoridad sobre el término. Ordenado alfabéticamente.

| Término | Definición | Fuente |
|---------|------------|--------|
| **ADR** | Architecture Decision Record: registro de una decisión estructural (contexto, decisión, consecuencias, alternativas). | [003](./003_DECISION_FRAMEWORK.md) |
| **AIProvider** | Capa de abstracción interna que oculta el LLM concreto (`complete`/`embed`); todo acceso a LLM pasa por ella (anti lock-in). | [#02](../02-architecture/technical-architecture.md) ADR-07 |
| **Arista / Edge** | Relación tipada y dirigida entre dos nodos del grafo de conocimiento. | [#03](../03-data/data-architecture-and-domain-model.md) |
| **`attributes.kind`** | Discriminador dentro de `attributes` de un nodo `note` que marca elementos de los módulos de vida: `goal`, `habit`, `reflection` o `expense`. | [ADR-020](../02-architecture/adr/ADR-020-life-modules-as-note-nodes.md), [#03 §5.1](../03-data/data-architecture-and-domain-model.md) |
| **Bounded context** | Frontera de responsabilidad única del dominio. Contextos: Identity, Capture, Knowledge Graph, AI Understanding, Proactivity Engine, Query/Retrieval. | [#02](../02-architecture/technical-architecture.md) §4 |
| **Bucle de valor** | El ciclo central de mindOS: **capturar → comprender → recuperar valor**. Estrella polar de la priorización. | [#01](../01-product/prd.md) |
| **Captura / Capture** | Entrada cruda del usuario (texto/voz) persistida sin fricción; es sagrada y nunca se pierde. | [#02](../02-architecture/technical-architecture.md), [#03](../03-data/data-architecture-and-domain-model.md) |
| **Comprensión** | Proceso asíncrono por el que una captura cruda se convierte en entidades tipadas, embeddings y conexiones. | [#02](../02-architecture/technical-architecture.md) §6 |
| **Conversar (Ask)** | Pantalla donde el usuario pregunta en lenguaje natural. mindOS responde con RAG citando sus capturas, sin inventar. | [#04 §5.7](../04-api/api-design-specification.md) |
| **created_at** | Momento en que el sistema registró el dato (tiempo de sistema), distinto de cuándo ocurrió el hecho. | [#03](../03-data/data-architecture-and-domain-model.md) |
| **Crecimiento (Growth)** | Módulo de metas (con % de avance), hábitos (con racha) y reflexiones del usuario. | [ADR-020](../02-architecture/adr/ADR-020-life-modules-as-note-nodes.md) |
| **Daily Briefing** | Resumen proactivo diario que prioriza el contexto relevante del usuario (eventos, tareas, compromisos). | [#01](../01-product/prd.md), [#02](../02-architecture/technical-architecture.md) |
| **DERIVED_FROM / Provenance** | Trazabilidad de procedencia: toda entidad derivada enlaza a la captura de la que proviene. | [#03](../03-data/data-architecture-and-domain-model.md) |
| **El Optimizador** | Perfil de usuario objetivo del MVP: persona que busca reducir carga mental y decidir mejor. | [#01](../01-product/prd.md) |
| **Focus score** | Indicador de 40 a 99 en "Hoy", calculado en la app a partir de las tareas abiertas vencidas y las hechas. Es una heurística, no un modelo. | `apps/mobile/lib/src/features/home/focus_score.dart` |
| **Gate de comprensión** | Umbrales mínimos que la IA debe superar en el examen de 45 casos: F1 de entidades ≥0.80, precisión de tareas ≥0.85, alucinación ≤0.10 y coste ≤$0.01 por captura. No se relajan. | [ADR-018](../02-architecture/adr/ADR-018-f2-comprehension-eval-gate.md) |
| **Grafo de conocimiento** | Red de nodos y aristas que modela el contexto vivo del usuario; el activo central de mindOS. | [#03](../03-data/data-architecture-and-domain-model.md) |
| **Hoy** | Pantalla principal de la app: el dashboard del día (enfoque, finanzas, hábito, meta, recordatorios, recomendación). | [009](./009_CURRENT_STATE.md) |
| **Lo que entendí (Insights)** | Vista de las entidades y conexiones que la IA extrajo de una captura concreta. | [#04 §5.7](../04-api/api-design-specification.md) |
| **Memoria** | Pantalla con lo que mindOS sabe del usuario, por tipo de nodo, y la línea de tiempo de sus capturas. | [009](./009_CURRENT_STATE.md) |
| **mindOS** | Capa de inteligencia personal que evoluciona hasta ser un sistema operativo personal con IA. | [#00](../00-foundation/vision-and-problem-statement.md) |
| **Niveles de firmeza** | Escala para marcar convicción: 🟢 firme · 🟠 opinión fuerte · ⚪️ tentativa. | [003](./003_DECISION_FRAMEWORK.md) |
| **Nodo / Node** | Unidad de información del grafo (captura, entidad, evento, persona, proyecto…), con tipo y atributos. | [#03](../03-data/data-architecture-and-domain-model.md) |
| **North Star Metric (IVU/sem)** | Interacciones de Valor del Usuario por semana: métrica estrella de valor entregado. | [#01](../01-product/prd.md) §8 |
| **occurred_at** | Momento en que ocurrió el hecho descrito por la captura (tiempo del mundo), distinto de `created_at`. | [#03](../03-data/data-architecture-and-domain-model.md) |
| **pgvector** | Extensión de PostgreSQL para almacenar embeddings y hacer búsqueda semántica sin una vector DB dedicada. | [#02](../02-architecture/technical-architecture.md) ADR-05 |
| **Property graph** | Modelo de grafo donde nodos y aristas llevan propiedades (atributos), implementado sobre tablas + JSONB. | [#03](../03-data/data-architecture-and-domain-model.md) |
| **RAG** | Retrieval-Augmented Generation: respuestas del LLM ancladas (grounded) en el contexto recuperado del usuario. | [#02](../02-architecture/technical-architecture.md) §6 |
| **Resolución de entidades** | Proceso de identificar que menciones distintas refieren a la misma entidad y unificarlas. | [#03](../03-data/data-architecture-and-domain-model.md) §8 |
| **RLS (Row-Level Security)** | Aislamiento a nivel de fila en Postgres que garantiza que ningún dato cruce fronteras de usuario. | [#02](../02-architecture/technical-architecture.md), [#07](../07-security/security-and-privacy-framework.md) |
| **Segundo cerebro** | Metáfora del propósito: un sistema externo que recuerda y conecta por el usuario. | [#00](../00-foundation/vision-and-problem-statement.md) |
| **Worker de comprensión** | Proceso Python que consume la cola `understanding` (BullMQ), llama al LLM y escribe el grafo bajo RLS. | [ADR-019](../02-architecture/adr/ADR-019-queue-python-consumer-bridge.md) |

## Historial de versiones
| Versión | Fecha | Cambios |
|---------|-------|---------|
| 1.0 | 2026-07-02 | Glosario inicial del lenguaje ubicuo. |
| 1.1 | 2026-10-27 | Añadidos `attributes.kind`, Conversar, Crecimiento, Focus score, Gate de comprensión, Hoy, Lo que entendí, Memoria y Worker de comprensión. |
