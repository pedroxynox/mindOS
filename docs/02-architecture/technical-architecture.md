# mindOS — Technical Architecture Document (TAD)

> **Documento #02 de la cadena documental.**
> Deriva del [PRD (#01)](../01-product/prd.md) y del
> [Vision (#00)](../00-foundation/vision-and-problem-statement.md).
> Define **CÓMO se construye el sistema**. No define el esquema exacto de datos
> (eso es #03) ni los contratos de API detallados (eso es #04).
>
> ⚠️ **REVISADO por [ADR-010](./adr/ADR-010-final-stack-and-two-backends.md)
> (2026-07-01):** el stack y el estilo cambiaron a mobile-first (Flutter) con
> **dos backends** (NestJS para negocio + Python/FastAPI para IA). ADR-001,
> ADR-003 y ADR-008 de este documento quedan superados por el ADR-010. El resto
> del documento (principios, contextos, flujos, atributos de calidad) sigue
> vigente.
>
> 📁 **NOTA DE CONSOLIDACIÓN (2026-07-03):** los ADR que estaban embebidos en
> este documento (antes "ADR-01".."ADR-09") se extrajeron a archivos individuales
> en [`./adr/`](./adr/README.md) con numeración de 3 dígitos (`ADR-001`..`ADR-009`),
> unificando el esquema con `ADR-010`/`011`/`012`. Aquí queda solo el índice con
> enlaces (ver §3 y §5). Consolidación registrada como deuda
> [D-004](../000_SYSTEM/012_RISK_AND_DEBT_REGISTER.md).

| Metadato | Valor |
|----------|-------|
| Versión | 0.1 (borrador para revisión) |
| Estado | 🟢 Aprobado |
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

> Las decisiones de estilo se registran ahora como ADRs individuales en
> [`./adr/`](./adr/README.md). Resumen:
>
> - **[ADR-001 — Monolito modular sobre microservicios](./adr/ADR-001-modular-monolith.md)**
>   (🟠 superado parcialmente por [ADR-010](./adr/ADR-010-final-stack-and-two-backends.md)):
>   el backend arrancaba como monolito modular con contextos acotados y fronteras
>   internas explícitas, para dar velocidad hoy y permitir extraer servicios
>   después. ADR-010 adelantó esa extracción a **dos backends** desde el inicio.
> - **[ADR-002 — Procesamiento asíncrono del pipeline de comprensión](./adr/ADR-002-async-comprehension-pipeline.md)**
>   (🟢 firme): la captura es síncrona (< 3s); la comprensión (extracción,
>   embeddings, linking) ocurre en workers asíncronos vía cola de trabajos.

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

> Cada decisión de stack se registra ahora como un ADR individual en
> [`./adr/`](./adr/README.md). Índice de las decisiones que antes vivían embebidas
> en esta sección:

| ADR | Decisión | Firmeza / Estado |
|-----|----------|------------------|
| [ADR-003](./adr/ADR-003-backend-python-fastapi.md) | Backend: Python + FastAPI para el núcleo de IA | 🟠 superado parcialmente por [ADR-010](./adr/ADR-010-final-stack-and-two-backends.md) (negocio pasa a NestJS; Python queda para el servicio de IA) |
| [ADR-004](./adr/ADR-004-postgresql-source-of-truth.md) | PostgreSQL como sistema de verdad (incluido el grafo) | 🟠 confirmado por [ADR-012](./adr/ADR-012-canonical-stack.md) |
| [ADR-005](./adr/ADR-005-pgvector-semantic-search.md) | Búsqueda semántica con pgvector (no vector DB dedicada, aún) | 🟠 confirmado por [ADR-012](./adr/ADR-012-canonical-stack.md) |
| [ADR-006](./adr/ADR-006-redis-queue-cache.md) | Cola de trabajos y caché: Redis | 🟢 complementado por [ADR-012](./adr/ADR-012-canonical-stack.md) (BullMQ) |
| [ADR-007](./adr/ADR-007-aiprovider-abstraction.md) | Capa de IA con abstracción agnóstica de proveedor (`AIProvider`) | 🟢 reafirmado por ADR-010/012 |
| [ADR-008](./adr/ADR-008-frontend-react-pwa.md) | Frontend: TypeScript + React (web) + PWA | 🟠 superado parcialmente por [ADR-010](./adr/ADR-010-final-stack-and-two-backends.md) (mobile-first Flutter) |
| [ADR-009](./adr/ADR-009-ai-strategy-external-llm.md) | Estrategia de IA: LLM externo ahora, IP en el motor de contexto, modelos propios después | 🟢 firme |

> El índice completo de TODOS los ADR (001..012) vive en
> [`./adr/README.md`](./adr/README.md).

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
| 0.2 | 2026-07-01 | Founder + CTO | Añadido ADR-09: estrategia de IA (LLM externo ahora + IP en el motor de contexto + modelos propios especializados después). Decisión tomada tras descartar explícitamente la opción de modelo propio desde el día uno. |
| 0.3 | 2026-07-03 | CPTO | Consolidación de ADRs (D-004): los ADR embebidos ADR-01..ADR-09 se extrajeron a archivos individuales `ADR-001`..`ADR-009` en `./adr/` (esquema uniforme de 3 dígitos). §3 y §5 dejan solo un índice con enlaces; el detalle vive en cada archivo. Referencias cruzadas normalizadas a 3 dígitos. |
