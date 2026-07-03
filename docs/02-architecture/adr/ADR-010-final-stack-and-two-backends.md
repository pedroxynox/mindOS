# ADR-010 — Stack definitivo y arquitectura de dos backends

> **Architecture Decision Record — revisión.**
> Modifica decisiones previas de [TAD #02](../technical-architecture.md)
> (ADR-03, ADR-08), [PRD #01](../../01-product/prd.md) (D1), [API #04](../../04-api/api-design-specification.md)
> ([ADR-013](./ADR-013-rest-json-sse-api-style.md), antes "ADR-A1") y
> [Security #07](../../07-security/security-and-privacy-framework.md) (P3).

| Metadato | Valor |
|----------|-------|
| Estado | 🟢 Aprobado (decisión del founder + CTO) |
| Fecha | 2026-07-01 |
| Reemplaza parcialmente | ADR-03, ADR-08 (#02); D1 (#01); ADR-013 (#04, antes "ADR-A1"); P3 (#07) |

---

## Contexto

Tras definir el mercado inicial (Brasil/Latinoamérica, P2 #07), el founder
decidió un enfoque **mobile-first** y un stack tecnológico concreto. Este ADR lo
registra formalmente y reconcilia las decisiones previas afectadas.

> **Motivo del cambio de mobile:** Latinoamérica es un mercado predominantemente
> móvil. La decisión original (web desktop-primary + PWA de captura, D1) se tomó
> antes de fijar el mercado; se corrige aquí a **mobile-first**.

---

## Decisión

### Stack definitivo

**Frontend (móvil, superficie primaria):**
- Flutter (Dart)
- Riverpod (gestión de estado)
- GoRouter (navegación)
- Drift (SQLite) para almacenamiento local y soporte offline
- Material Design 3

**Backend de negocio (API principal):**
- NestJS (TypeScript)
- Prisma (ORM)
- PostgreSQL
- Redis
- WebSocket (tiempo real)
- Autenticación **JWT propia** (construida en NestJS, no comprada)

**Servicio de IA (separado):**
- Python + FastAPI
- LangGraph (orquestación de agentes)
- LlamaIndex (RAG / indexación)
- LLMs intercambiables (OpenAI, Anthropic u otros) vía capa `AIProvider`

**Infraestructura:**
- Docker, GitHub Actions, Nginx, Cloudflare
- Kubernetes **cuando la escala lo justifique** (no en el MVP)

### Arquitectura de dos backends

Se adopta un sistema de **dos servicios** desde el inicio (en lugar del monolito
modular de ADR-01):

```
   Flutter (móvil)
        │  HTTPS / WebSocket
        ▼
   ┌─────────────────────┐        interno         ┌──────────────────────┐
   │  API de negocio     │  ───────────────────►  │  Servicio de IA       │
   │  NestJS + Prisma    │  ◄───────────────────  │  Python + FastAPI     │
   │                     │                        │  LangGraph/LlamaIndex │
   │  Gobierna:          │                        │  Gobierna:            │
   │  - Auth (JWT)       │                        │  - Comprensión (LLM)  │
   │  - Grafo (nodos/    │                        │  - Embeddings         │
   │    aristas, Postgres)│                       │  - Búsqueda vectorial │
   │  - Tiempo real (WS) │                        │  - RAG                │
   └─────────┬───────────┘                        └───────────┬──────────┘
             │                                                 │
             ▼                                                 ▼
        PostgreSQL (grafo)  ◄───── comparten ─────►  PostgreSQL + pgvector
             Redis (cola/caché/pubsub)                (embeddings)
```

### Frontera de responsabilidad entre backends (definida por el CTO)

| Responsabilidad | Dueño |
|-----------------|-------|
| Autenticación, sesiones, cuentas | **NestJS** |
| Grafo relacional (nodos/aristas, CRUD, travesías) | **NestJS + Prisma** |
| Tiempo real (WebSocket), notificaciones | **NestJS** |
| Orquestación de comprensión (extracción, linking) | **Python (IA)** |
| Embeddings y búsqueda vectorial (pgvector) | **Python (IA)** |
| RAG para consultas contextuales | **Python (IA)** |
| Cola de trabajos async (comprensión) | Redis; productor NestJS, consumidor Python |

> El flujo de captura: NestJS recibe y persiste la `Capture` cruda, publica un
> trabajo en Redis; el servicio Python lo consume, comprende y escribe las
> entidades/aristas/embeddings; NestJS notifica al cliente por WebSocket.

---

## Consecuencias

### Positivas
- Cada capa usa el mejor ecosistema para su trabajo (Node para API/tiempo real;
  Python para IA).
- El servicio de IA nace ya separado — coincide con el "primer candidato a
  extracción" que anticipaba el #02 §4.
- Flutter da apps nativas iOS+Android con una base de código, alineado al
  mercado móvil de LatAm, con soporte offline (Drift).

### Negativas (aceptadas conscientemente por el founder)
- **Tres lenguajes** en el proyecto (Dart, TypeScript, Python): mayor costo de
  tooling, contexto y contratación.
- **Sistema distribuido desde el día uno**: complejidad de coordinación entre
  dos servicios antes de validar el producto.
- **Auth propia (JWT)**: asumimos el riesgo de seguridad de construirla, con los
  controles de #07 (hashing fuerte, tokens de vida corta + refresh, rate
  limiting, protección contra fuerza bruta).

### Mitigaciones
- Contratos claros entre servicios (documentados en #04, revisado).
- La capa `AIProvider` (ADR-09) se mantiene: LLMs intercambiables.
- Estándares de #05 aplican a los tres lenguajes (linters/formatters por app).

---

## Cambios concretos en documentos previos

| Documento | Decisión previa | Nueva decisión |
|-----------|-----------------|----------------|
| #02 ADR-01 | Monolito modular | Dos servicios (NestJS + Python) desde el inicio |
| #02 ADR-03 | Backend único en Python/FastAPI | Backend de negocio en NestJS; IA en Python/FastAPI |
| #02 ADR-08 | Frontend React/TS (web) + PWA | Frontend Flutter (móvil primero); web secundaria/futura |
| #01 D1 | Web desktop-primary + captura móvil | **Mobile-first** (Flutter); web como complemento posterior |
| #04 ADR-013 (antes "ADR-A1") | REST + SSE | REST + **WebSocket** (SSE opcional); NestJS como capa API |
| #07 P3 | Comprar auth gestionada | **Construir** auth JWT propia en NestJS |
