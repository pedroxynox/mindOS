# mindOS — Technical Architecture Document (TAD)

> **Documento #02 de la cadena documental.**
> Deriva del [PRD (#01)](../01-product/prd.md) y del
> [Vision (#00)](../00-foundation/vision-and-problem-statement.md).
> Define **CÓMO se construye el sistema**. No define el esquema exacto de datos
> (eso es #03) ni los contratos de API detallados (eso es #04).

| Metadato | Valor |
|----------|-------|
| Versión | 0.1 (borrador para revisión) |
| Estado | 🟡 En revisión |
| Autor | CTO |
| Depende de | #00 Vision, #01 PRD |
| Última actualización | 2026-07-01 |

---

## 0. Propósito

Este documento define la arquitectura técnica de mindOS: los componentes del
sistema, cómo interactúan, qué tecnologías usamos y por qué, y cómo el diseño
soporta la visión a 10 años y millones de usuarios **sin caer en
sobre-ingeniería prematura.**

### Principio arquitectónico rector

> Diseñamos para no pintarnos en una esquina, no para escalar a millones el día
> uno. La sobre-ingeniería temprana mata la velocidad tanto como la deuda
> técnica mata el largo plazo. Buscamos el punto medio: **simplicidad
> operativa hoy, con puntos de extensión claros para mañana.**

---

## 1. Restricciones que moldean la arquitectura

Derivadas de #00 y #01:

1. **El núcleo es el producto** (Core-first). Toda la lógica vive en el
   backend; las superficies son clientes delgados.
2. **La IA es el diferenciador**, no un add-on. La arquitectura se organiza
   alrededor del pipeline de comprensión.
3. **Captura sin fricción (< 3s)** → la captura debe ser síncrona y rápida; la
   comprensión ocurre de forma **asíncrona** en segundo plano.
4. **Privacidad como requisito de entrada** → aislamiento estricto por usuario,
   cifrado en tránsito y reposo, exportabilidad y borrado total.
5. **El grafo crece durante años por usuario** → el almacenamiento y las
   consultas deben mantener rendimiento con grafos densos y longevos.
6. **Multi-superficie, multi-modalidad** → una sola fuente de verdad, expuesta
   vía API a cualquier cliente.

---

## 2. Vista de alto nivel

```
┌──────────────────────── SUPERFICIES (clientes delgados) ────────────────────────┐
│   Web App (desktop-primary, React)      PWA de captura móvil                     │
└───────────────────────────────────────┬──────────────────────────────────────────┘
                                         │  HTTPS / API (REST + streaming)
                                         ▼
┌──────────────────────────────── NÚCLEO (backend) ───────────────────────────────┐
│                                                                                   │
│   ┌───────────────┐   API Gateway / BFF (autenticación, rate limiting)           │
│   └───────┬───────┘                                                               │
│           │                                                                       │
│   ┌───────▼────────────────────────────────────────────────────────────────┐    │
│   │                    CONTEXTOS ACOTADOS (modular monolith)                 │    │
│   │                                                                          │    │
│   │  [Identity]  [Capture]  [Knowledge Graph]  [AI Understanding]            │    │
│   │              [Proactivity Engine]  [Query/Retrieval]                     │    │
│   └───────┬───────────────────────────────┬─────────────────────────────────┘    │
│           │ (síncrono: captura rápida)     │ (eventos)                            │
│           ▼                                ▼                                       │
│   ┌───────────────┐              ┌──────────────────┐                             │
│   │  Almacenes    │              │  Cola de trabajos │──► Workers de IA           │
│   │  de datos     │◄─────────────│  (async pipeline) │    (extracción, embeddings,│
│   └───────────────┘              └──────────────────┘     linking)                │
│           │                                                                       │
│           ▼                                                                       │
│   PostgreSQL (+pgvector) · Redis · Object Storage      Proveedor LLM (API)        │
└───────────────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Estilo arquitectónico

### ADR-01 — Modular monolith sobre microservicios (para empezar)

- **Decisión:** El backend se construye como un **monolito modular** con
  contextos acotados bien definidos y fronteras internas explícitas.
- **Estado:** 🟠 Decisión de CTO, sujeta a veto.
- **Por qué:** Los microservicios prematuros son la causa más común de muerte
  por complejidad en startups. Añaden sobrecarga operativa (despliegue,
  observabilidad distribuida, consistencia entre servicios) que no se justifica
  sin escala ni equipo grande. Un monolito modular con fronteras limpias nos da
  velocidad hoy y permite **extraer servicios** (empezando por los workers de
  IA) cuando los datos de carga lo justifiquen.
- **Alternativa considerada:** microservicios desde el día uno. Rechazada por
  costo operativo y velocidad.
- **Punto de extensión:** los contextos acotados se comunican por interfaces
  internas, de modo que extraer uno a un servicio independiente sea mecánico,
  no una reescritura.

### ADR-02 — Procesamiento asíncrono del pipeline de comprensión

- **Decisión:** La captura es síncrona y devuelve en < 3s. La comprensión
  (extracción de entidades, embeddings, linking) ocurre en **workers
  asíncronos** vía cola de trabajos.
- **Estado:** 🟢 Firme (deriva de FR-1.1 + FR-2.x).
- **Por qué:** Cumple el requisito de captura instantánea sin bloquear al
  usuario esperando a la IA. Además desacopla el costo/latencia del LLM de la
  experiencia de captura, y permite reintentos y escalado independiente.

---

## 4. Contextos acotados (bounded contexts)

Cada contexto tiene responsabilidad única y fronteras claras:

| Contexto | Responsabilidad | Depende de |
|----------|-----------------|-----------|
| **Identity** | Registro, login, sesión, gestión de cuenta, borrado de datos. | — |
| **Capture** | Recibir capturas (texto/voz) con mínima fricción y persistirlas como nodos crudos. Emitir evento "captura creada". | Identity |
| **Knowledge Graph** | Sistema de verdad del grafo: nodos, tipos, relaciones. Lectura/escritura del grafo. | Identity |
| **AI Understanding** | Consumir eventos de captura; extraer entidades, generar embeddings, proponer conexiones, tipar nodos. | Knowledge Graph, LLM |
| **Proactivity Engine** | Generar el Daily Briefing y (V2) disparadores contextuales. | Knowledge Graph, Query |
| **Query/Retrieval** | Responder consultas en lenguaje natural sobre el contexto del usuario (RAG). | Knowledge Graph, LLM |

> Estas fronteras son también las fronteras naturales de extracción a servicios
> futuros. El primer candidato a extracción es **AI Understanding** (cargas de
> CPU/IO y escalado distintos al resto).

---

## 5. Decisiones de tecnología (stack)

> Cada decisión incluye alternativas consideradas. Las marcadas 🟠 son las de
> mayor impacto y las que más quiero que cuestiones.

### ADR-03 — Backend: Python + FastAPI para el núcleo de IA

- **Decisión:** El backend principal se escribe en **Python** con **FastAPI**.
- **Estado:** 🟠 Decisión de CTO, sujeta a veto.
- **Por qué:** El diferenciador de mindOS *es* la IA. El ecosistema de Python
  para orquestación de LLMs, embeddings, procesamiento de lenguaje y
  herramientas de ML no tiene rival. FastAPI aporta rendimiento async, tipado
  vía type hints + Pydantic, y validación de contratos sólida. Poner el núcleo
  donde vive el ecosistema de IA reduce fricción en el componente más crítico.
- **Alternativas consideradas:**
  - *TypeScript/Node (full-stack unificado):* tentador por compartir lenguaje
    con el frontend, pero el ecosistema de IA es más pobre y acabaríamos
    llamando a servicios Python de todas formas.
  - *Go:* excelente rendimiento y concurrencia, pero ecosistema de IA inmaduro
    y mayor verbosidad para iterar rápido en la capa de comprensión.
- **Trade-off aceptado:** Python es menos performante que Go en CPU puro. Lo
  mitigamos con procesamiento async y extrayendo trabajo pesado a workers. Para
  nuestras cargas (I/O hacia LLMs y BD), no es el cuello de botella.

### ADR-04 — PostgreSQL como sistema de verdad (incluido el grafo)

- **Decisión:** **PostgreSQL** es el almacén principal. El grafo de
  conocimiento se modela con tablas de **nodos** y **aristas** explícitas
  (más JSONB para atributos flexibles).
- **Estado:** 🟠 Decisión de CTO, sujeta a veto.
- **Por qué:** Postgres es robusto, operacionalmente simple, escala vertical y
  horizontalmente (réplicas de lectura, particionado), y soporta aislamiento
  por usuario vía Row-Level Security. Introducir una base de grafos nativa
  (Neo4j) desde el día uno añade un sistema entero que operar, respaldar y
  monitorear, sin que la complejidad de las travesías del MVP lo justifique.
- **Alternativa considerada:** *Neo4j / base de grafos nativa.* Superior para
  travesías profundas y multi-salto. **Punto de reevaluación:** si las
  consultas de grafo (recomendaciones multi-salto, análisis de relaciones
  complejas en V2+) degradan el rendimiento en Postgres, migramos ese subdominio
  a una base de grafos. El diseño de nodos/aristas mantiene esa puerta abierta.
- **Trade-off aceptado:** travesías complejas en SQL son más verbosas. Aceptable
  para el alcance del MVP (conexiones de 1-2 saltos).

### ADR-05 — Búsqueda semántica con pgvector (no una vector DB dedicada, aún)

- **Decisión:** Los embeddings y la búsqueda semántica (RAG) usan la extensión
  **pgvector** sobre el mismo Postgres.
- **Estado:** 🟠 Decisión de CTO, sujeta a veto.
- **Por qué:** Mantiene un solo almacén operativo en el MVP. Evita sincronizar
  datos entre Postgres y una vector DB externa. pgvector es suficiente hasta
  escalas considerables.
- **Punto de reevaluación:** ante millones de vectores por consulta con
  latencia crítica, migrar a una vector DB dedicada (Qdrant / Weaviate /
  Pinecone). La capa de recuperación se abstrae para permitir el cambio.

### ADR-06 — Cola de trabajos y caché: Redis

- **Decisión:** **Redis** para caché y como backend de la cola de trabajos
  asíncronos (con un framework de workers sobre él).
- **Estado:** 🟢 Firme.
- **Por qué:** Estándar probado, simple, cubre caché y colas con un solo
  componente en la fase inicial.

### ADR-07 — Capa de IA con abstracción agnóstica de proveedor

- **Decisión:** Todo acceso a LLMs pasa por una **capa de abstracción interna**
  (interfaz `AIProvider`) que oculta al proveedor concreto. El MVP usa un LLM de
  terceros vía API (decisión D6 del PRD).
- **Estado:** 🟢 Firme (principio anti-lock-in).
- **Por qué:** El mercado de modelos cambia cada trimestre. No podemos acoplar
  la lógica de negocio a un proveedor. La abstracción permite: cambiar de
  proveedor, hacer A/B entre modelos, enrutar por costo/calidad, y migrar a
  modelos propios post-MVP sin tocar la lógica de dominio.
- **Nota:** La elección del proveedor concreto (costo, latencia, privacidad,
  residencia de datos) es una decisión con implicaciones de negocio y
  privacidad; se cierra junto con #07 (Security & Privacy Framework).

### ADR-08 — Frontend: TypeScript + React (web responsive) + PWA

- **Decisión:** Superficie web en **React + TypeScript**, responsive
  (desktop-primary), con capacidades **PWA** para la captura móvil.
- **Estado:** 🟠 Decisión de CTO, sujeta a veto.
- **Por qué:** Ecosistema maduro, contratación sencilla, PWA cubre la captura
  móvil del MVP sin el costo de apps nativas (alineado con non-goals del PRD).
  El framework concreto (Next.js vs. SPA con Vite) se decide en la fase de
  frontend; recomendación inicial: Next.js por routing, SSR opcional y madurez.
- **Trade-off aceptado:** una PWA tiene limitaciones frente a nativo (captura en
  background, notificaciones en iOS). Aceptable para MVP; app nativa es un
  candidato de V2 si los datos de uso lo justifican.

### Resumen del stack (MVP)

| Capa | Tecnología | Firmeza |
|------|-----------|---------|
| Frontend | React + TypeScript (PWA) | 🟠 |
| API / Backend | Python + FastAPI | 🟠 |
| Datos (verdad + grafo) | PostgreSQL (+ RLS, JSONB) | 🟠 |
| Búsqueda semántica | pgvector | 🟠 |
| Caché + colas | Redis | 🟢 |
| Workers de IA | Python (async) | 🟢 |
| LLM | Proveedor externo vía capa `AIProvider` | 🟢 |
| Object storage (V2) | S3-compatible | 🟢 |

---

## 6. Flujos clave

### Flujo 1 — Captura (síncrono, < 3s)
1. El cliente envía la captura al API Gateway (autenticada).
2. `Capture` valida y persiste un **nodo crudo** en Postgres.
3. `Capture` emite el evento `CaptureCreated` a la cola.
4. Respuesta inmediata al usuario ("capturado"). **Fin del camino síncrono.**

### Flujo 2 — Comprensión (asíncrono, segundo plano)
1. Un worker consume `CaptureCreated`.
2. `AI Understanding` llama al LLM (vía `AIProvider`) para extraer entidades y
   tipar el nodo.
3. Genera embeddings y los guarda (pgvector).
4. Propone y persiste conexiones con nodos existentes (`Knowledge Graph`).
5. Actualiza el estado del nodo a "comprendido"; el cliente lo refleja
   (polling o streaming).

### Flujo 3 — Daily Briefing (proactivo)
1. `Proactivity Engine` se dispara (programado o al abrir la app).
2. Recupera del grafo el contexto relevante (eventos próximos, tareas,
   compromisos, proyectos activos) vía `Query/Retrieval`.
3. Compone el briefing (priorización + generación con LLM, grounded en el
   contexto del usuario).
4. Lo entrega a la superficie. El usuario marca útil/no útil (FR-3.5) → señal.

### Flujo 4 — Consulta contextual (RAG)
1. El usuario pregunta en lenguaje natural.
2. `Query/Retrieval` recupera nodos candidatos (búsqueda vectorial + travesía
   de grafo de 1-2 saltos).
3. Construye un prompt **grounded** solo en el contexto del usuario.
4. El LLM responde; se citan/enlazan los nodos fuente (evita alucinación,
   FR-3.3).

---

## 7. Atributos de calidad (cómo cumplimos los "-ilities")

| Atributo | Enfoque |
|----------|---------|
| **Escalabilidad** | Stateless en la capa API (escala horizontal). Workers de IA escalan independientemente. Postgres con réplicas de lectura y particionado por usuario cuando aplique. |
| **Rendimiento** | Camino de captura síncrono mínimo; todo lo caro es async. Caché en Redis para briefings y consultas frecuentes. |
| **Aislamiento / multi-tenancy** | Row-Level Security en Postgres + `user_id` en toda entidad. Ningún dato cruza fronteras de usuario. |
| **Privacidad / seguridad** | TLS en tránsito; cifrado en reposo; exportación y borrado total; minimización de datos enviados al LLM. Detalle en #07. |
| **Fiabilidad** | Reintentos idempotentes en workers; el fallo del pipeline de IA nunca pierde la captura cruda (ya persistida). |
| **Observabilidad** | Logs estructurados, métricas y tracing desde el día uno. Detalle en #06. |
| **Mantenibilidad** | Contextos acotados con interfaces explícitas; capa `AIProvider` desacopla el modelo. |
| **Costo** | El costo dominante es el LLM. La abstracción permite enrutar por costo y cachear resultados. Se monitorea costo por usuario como métrica de primera clase. |

---

## 8. Cómo esta arquitectura soporta la visión a 10 años

- **Núcleo agnóstico** → añadir superficies nuevas (nativo, wearables, API
  pública, automóvil) es agregar clientes, no reescribir el cerebro.
- **Contextos acotados** → extraer servicios cuando la escala lo exija, sin
  reescritura.
- **Capa `AIProvider`** → adoptar modelos nuevos o propios sin tocar el dominio.
- **Grafo en Postgres con puerta a grafo nativo** → evolución del almacén sin
  bloqueo.
- **Módulos de dominio de vida** (finanzas, salud — V4 del PRD) → se añaden como
  contextos acotados nuevos sobre el mismo núcleo y el mismo grafo.

---

## 9. Riesgos técnicos y mitigaciones

| Riesgo | Impacto | Mitigación |
|--------|---------|-----------|
| Costo/latencia del LLM crece con el uso | Alto | Caché, enrutamiento por costo, procesamiento async, monitoreo de costo/usuario. |
| Calidad de extracción/linking insuficiente | Alto | Feedback loop del usuario (FR-2.4) como dato de mejora; umbral de calidad medido antes de lanzar. |
| Privacidad: datos sensibles enviados a un LLM externo | Alto | Minimización de datos, anonimización cuando sea posible, evaluación de residencia de datos; camino a modelos propios/on-prem post-MVP. |
| Postgres insuficiente para travesías de grafo en V2+ | Medio | Diseño nodos/aristas que permite migrar ese subdominio a grafo nativo. |
| Monolito se vuelve difícil de escalar | Medio | Fronteras de contexto listas para extracción a servicios. |

---

## 10. Preguntas abiertas (para #03, #04, #06, #07)

1. Esquema concreto de nodos y aristas del grafo → **#03 Data Architecture**.
2. Contratos de API detallados (captura, consulta, briefing) → **#04 API Design**.
3. Proveedor LLM concreto y su postura de privacidad → **#07 Security & Privacy**.
4. Estrategia de despliegue, entornos, CI/CD, cloud concreto → **#06 Infra**.
5. Framework de frontend definitivo (Next.js vs. Vite SPA) → fase de frontend.
6. Push vs. pull del Daily Briefing (pregunta abierta del PRD) → afecta #04 y #06.

---

## Historial de versiones

| Versión | Fecha | Autor | Cambios |
|---------|-------|-------|---------|
| 0.1 | 2026-07-01 | CTO | Borrador inicial. Estilo arquitectónico (modular monolith + async), contextos acotados, stack tecnológico con ADRs y alternativas, flujos clave, atributos de calidad, soporte a la visión a 10 años y riesgos. |
