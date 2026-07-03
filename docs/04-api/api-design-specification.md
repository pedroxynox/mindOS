# mindOS — API Design Specification

> **Documento #04 de la cadena documental.**
> Deriva del [TAD (#02)](../02-architecture/technical-architecture.md) y del
> [Data Model (#03)](../03-data/data-architecture-and-domain-model.md).
> Define **los contratos entre las superficies y el núcleo**. No define el
> esquema de base de datos (eso es #03) ni el despliegue (eso es #06).
>
> ⚠️ **REVISADO por [ADR-010](../02-architecture/adr/ADR-010-final-stack-and-two-backends.md)
> (2026-07-01):** la API la sirve **NestJS** (no FastAPI); el tiempo real usa
> **WebSocket** ([ADR-013](../02-architecture/adr/ADR-013-rest-json-sse-api-style.md) pasa de SSE a WebSocket); el servicio de IA (Python)
> expone su propia API interna consumida por NestJS. Los recursos y endpoints
> definidos aquí siguen siendo el contrato de referencia.

| Metadato | Valor |
|----------|-------|
| Versión | 0.1 (borrador para revisión) |
| Estado | 🟢 Aprobado |
| Autor | CTO |
| Depende de | #00, #01, #02, #03 |
| Última actualización | 2026-07-01 |

---

## 0. Propósito

La API es el **único punto de contacto** entre las superficies (web, PWA móvil,
y futuras: nativo, wearables, integraciones) y el núcleo (Core-first, #02). Un
contrato de API bien diseñado permite que las superficies evolucionen sin tocar
el cerebro, y que añadir superficies nuevas sea trivial.

Este documento define la forma, las convenciones y los endpoints de la API del
MVP.

---

## 1. Principios de diseño de la API

1. **Orientada a recursos y predecible.** Mismos patrones en todos los
   endpoints; sin sorpresas.
2. **La captura es sagrada y rápida.** El endpoint de captura nunca bloquea
   esperando a la IA (async, ADR-02). Devuelve en milisegundos.
3. **Contrato estable, implementación flexible.** La API oculta si por debajo
   hay un monolito, workers o qué LLM (ADR-07).
4. **Segura por defecto.** Toda ruta (salvo auth) exige autenticación; todo dato
   se filtra por usuario.
5. **Evolutiva.** Versionado desde el día uno; los cambios no rompen clientes
   existentes.

---

## 2. Decisiones de estilo de API

> La decisión de estilo de API se registra ahora como un ADR individual en
> [`../02-architecture/adr/`](../02-architecture/adr/README.md) (consolidación de
> ADRs, deuda [D-004](../000_SYSTEM/012_RISK_AND_DEBT_REGISTER.md)). Antes vivía
> embebida aquí como "ADR-A1".
>
> - **[ADR-013 — REST/JSON como estilo primario + SSE para streaming](../02-architecture/adr/ADR-013-rest-json-sse-api-style.md)**
>   (🟠 Decisión de CTO, sujeta a veto — revisada parcialmente por
>   [ADR-010](../02-architecture/adr/ADR-010-final-stack-and-two-backends.md): el
>   tiempo real pasa de SSE a **WebSocket**, SSE queda opcional; NestJS como capa
>   API): REST sobre JSON para operaciones de recursos y SSE para el streaming
>   token a token de las respuestas de IA. Alternativas consideradas: GraphQL
>   (pospuesto por complejidad de caché/seguridad/tooling en el MVP) y WebSockets
>   para todo (innecesario en su momento).
>
> El índice completo de TODOS los ADR vive en
> [`../02-architecture/adr/README.md`](../02-architecture/adr/README.md).

---

## 3. Convenciones globales

| Aspecto | Convención |
|---------|-----------|
| **Base URL** | `https://api.mindos.app` |
| **Versionado** | Prefijo de ruta: `/v1/...`. Cambios incompatibles → `/v2`. |
| **Formato** | `application/json` (UTF-8). Streaming: `text/event-stream`. |
| **Autenticación** | `Authorization: Bearer <access_token>`. |
| **IDs** | UUID v4 en todo recurso. |
| **Tiempos** | ISO 8601 en UTC (`2026-07-01T09:00:00Z`). |
| **Nombres** | Recursos en plural, `snake_case` en los campos JSON. |
| **Paginación** | Basada en cursor: `?limit=50&cursor=<opaque>`. |
| **Idempotencia** | Header `Idempotency-Key` en `POST /captures` (evita duplicados por reintento móvil offline). |
| **Rate limiting** | Por usuario; respuestas `429` con `Retry-After`. |
| **Correlación** | Header `X-Request-Id` propagado para trazabilidad (#06). |

### Envoltura de error estándar

```json
{
  "error": {
    "code": "validation_error",
    "message": "El campo 'content' es obligatorio.",
    "request_id": "req_01H..."
  }
}
```

Códigos HTTP: `200/201` éxito, `202` aceptado (async), `400` validación,
`401` no autenticado, `403` no autorizado, `404` no encontrado, `409` conflicto,
`422` no procesable, `429` rate limit, `5xx` error de servidor.

---

## 4. Mapa de recursos (por contexto acotado)

| Contexto (#02) | Recursos / rutas |
|----------------|------------------|
| Identity | `/v1/auth/*`, `/v1/account`, `/v1/account/export`, `/v1/account` (DELETE) |
| Capture | `/v1/captures` |
| Knowledge Graph | `/v1/nodes`, `/v1/nodes/{id}`, `/v1/nodes/{id}/connections`, `/v1/edges/{id}` |
| Query/Retrieval | `/v1/query` (SSE) |
| Proactivity | `/v1/briefing` |
| (transversal) | `/v1/feedback` |

---

## 5. Endpoints del MVP

### 5.1 Identity & Account

#### `POST /v1/auth/register`
```json
// Request
{ "email": "alex@example.com", "password": "••••••••" }
// Response 201
{ "user_id": "u_...", "access_token": "...", "refresh_token": "..." }
```

#### `POST /v1/auth/login`
```json
// Request
{ "email": "alex@example.com", "password": "••••••••" }
// Response 200
{ "access_token": "...", "refresh_token": "...", "expires_in": 3600 }
```

#### `POST /v1/auth/refresh`
Intercambia un `refresh_token` por un nuevo `access_token`.

#### `GET /v1/account/export`  *(FR-X.3)*
Inicia una exportación completa del grafo del usuario. Devuelve `202` y, cuando
está lista, un enlace de descarga (JSON portable: nodos + aristas + capturas).

#### `DELETE /v1/account`  *(FR-X.4)*
Borra permanentemente la cuenta y todo su grafo (cascada). Requiere
reconfirmación. Devuelve `202`.

---

### 5.2 Capture — el endpoint más crítico

#### `POST /v1/captures`  *(FR-1.1, FR-1.2)*
Camino síncrono mínimo: persiste la captura cruda y devuelve de inmediato. La
comprensión ocurre después (async).

```json
// Request (texto)
{ "type": "text", "content": "Reunión con Ana el jueves para el pitch; me debe el deck." }

// Request (voz) → se sube el audio o el texto ya transcrito en cliente
{ "type": "voice", "content": "<transcripción>", "audio_ref": "optional_upload_id" }

// Response 202 (Accepted) — inmediato
{
  "capture_id": "n_cap_123",
  "status": "raw",
  "created_at": "2026-07-01T09:00:00Z"
}
```

> **Header `Idempotency-Key`:** si el móvil reintenta por mala conexión, el
> servidor reconoce la clave y no duplica la captura.

El cliente descubre el resultado de la comprensión mediante el contrato async
(§6).

---

### 5.3 Knowledge Graph

#### `GET /v1/nodes`
Lista nodos del usuario con filtros.
```
GET /v1/nodes?type=task&status=understood&limit=50&cursor=...
```
```json
// Response 200
{
  "data": [
    { "id": "n_task_9", "type": "task", "title": "Ana debe enviar el deck",
      "attributes": { "status": "pending", "due_date": "2026-07-03" },
      "confidence": 0.82, "occurred_at": null, "created_at": "..." }
  ],
  "next_cursor": "..."
}
```

#### `GET /v1/nodes/{id}`
Devuelve un nodo con sus atributos completos.

#### `GET /v1/nodes/{id}/connections`  *(Pilar 2)*
Devuelve los nodos conectados y el tipo de relación (travesía de 1 salto por
defecto; `?depth=2` opcional).
```json
// Response 200
{
  "node": { "id": "n_person_ana", "type": "person", "title": "Ana" },
  "connections": [
    { "edge_id": "e_1", "type": "assigned_to", "direction": "incoming",
      "node": { "id": "n_task_9", "type": "task", "title": "Ana debe enviar el deck" },
      "confidence": 0.82, "user_confirmed": false }
  ]
}
```

#### `PATCH /v1/nodes/{id}`
Permite al usuario editar/corregir un nodo (título, atributos, tipo).

#### `PATCH /v1/edges/{id}`  *(FR-2.4 — feedback loop)*
El usuario confirma o corrige una conexión propuesta por la IA.
```json
// Request
{ "user_confirmed": true }
// o para rechazar:
{ "deleted": true }
```

> Estas confirmaciones/correcciones son la **señal de entrenamiento** para los
> modelos propios futuros (ADR-09).

---

### 5.4 Query — consulta contextual (RAG, streaming)

#### `POST /v1/query`  *(FR-3.2, FR-3.3)*
Pregunta en lenguaje natural sobre el propio contexto. Responde por **SSE**
(streaming de tokens) y cita los nodos fuente para evitar alucinación.

```json
// Request
{ "question": "¿Qué tengo pendiente con Ana?" }
```
```
// Response: text/event-stream
event: token
data: {"text": "Ana "}

event: token
data: {"text": "te debe el deck del pitch..."}

event: sources
data: {"nodes": ["n_task_9", "n_project_pitch", "n_event_jueves"]}

event: done
data: {"query_id": "q_555"}
```

> El evento `sources` devuelve los nodos del grafo usados como fundamento. La
> superficie puede enlazarlos → transparencia y confianza (FR-3.3).

---

### 5.5 Briefing — proactividad

#### `GET /v1/briefing`  *(FR-3.1, FR-3.4)*
Devuelve el Daily Briefing priorizado por contexto temporal.
```json
// Response 200
{
  "briefing_id": "b_777",
  "generated_at": "2026-07-01T07:00:00Z",
  "sections": [
    { "kind": "events_today", "items": [ { "node_id": "n_event_jueves", "title": "Reunión pitch (jueves)" } ] },
    { "kind": "priority_tasks", "items": [ { "node_id": "n_task_9", "title": "Ana debe enviar el deck" } ] },
    { "kind": "pending_with_people", "items": [ { "person": "Ana", "summary": "Te debe el deck del pitch" } ] }
  ]
}
```

> **Pregunta abierta (heredada del PRD/TAD):** ¿el briefing es *pull* (este
> `GET`, al abrir la app) o *push* (notificación/email)? El MVP implementa
> **pull**; el push se añade con la arquitectura de notificaciones en #06.

---

### 5.6 Feedback — señal de valor

#### `POST /v1/feedback`  *(FR-3.5 — alimenta la North Star Metric)*
```json
// Request
{ "target_type": "briefing" , "target_id": "b_777", "useful": true }
// o sobre una respuesta de consulta:
{ "target_type": "query", "target_id": "q_555", "useful": false, "reason": "no era lo que buscaba" }
```

> Este endpoint es la fuente directa de la métrica **Interacciones de Valor por
> Usuario/semana** (PRD §8). No es opcional: sin él, no medimos valor.

---

## 6. Contrato de procesamiento asíncrono

Cómo el cliente descubre que una captura ya fue comprendida (ADR-02):

- **MVP — Polling:** el cliente consulta `GET /v1/nodes/{capture_id}` hasta que
  `status` pasa de `raw` a `understood`. Simple y suficiente.
- **Evolución — SSE de eventos:** un canal `GET /v1/events` (SSE) que empuja
  `capture.understood`, `connections.updated`, etc. Se añade cuando la
  experiencia lo requiera (evita polling agresivo). Documentado como puerta
  abierta, no MVP.

```json
// GET /v1/nodes/n_cap_123  (tras la comprensión)
{
  "id": "n_cap_123",
  "type": "capture",
  "status": "understood",
  "derived_nodes": ["n_person_ana", "n_event_jueves", "n_project_pitch", "n_task_9"]
}
```

---

## 7. Seguridad a nivel de API

- **Autenticación:** Bearer token (access de vida corta + refresh). Proveedor de
  identidad concreto se decide en #07.
- **Autorización:** todo recurso se filtra por `user_id` del token; refuerzo con
  RLS en BD (#03). Un usuario nunca puede pedir el nodo de otro.
- **Transporte:** solo HTTPS/TLS.
- **Rate limiting y cuotas:** por usuario, con foco en `POST /query` y
  `POST /captures` (operaciones que consumen LLM → costo).
- **Validación de entrada:** estricta (Pydantic en FastAPI, ADR-03).
- **Minimización:** las respuestas no exponen datos internos del pipeline ni del
  proveedor de LLM.

---

## 8. Fuera de alcance del API del MVP (non-goals)

- Webhooks salientes para integraciones de terceros.
- API pública para desarrolladores externos.
- Endpoints de colaboración/compartición (multiusuario).
- Operaciones masivas (bulk) más allá de export/borrado.
- GraphQL.

> Coherente con los non-goals del PRD (#01 §7). Se añaden en fases posteriores.

---

## 9. Preguntas abiertas (para #06, #07 e implementación)

1. Proveedor de identidad/auth concreto (gestionado vs. propio) → **#07**.
2. Briefing push vs. pull y arquitectura de notificaciones → **#06**.
3. Límites concretos de rate limiting por plan → depende del modelo de negocio.
4. Formato exacto del export (¿JSON plano, JSON-LD, otros?) → implementación.
5. ¿Se expone `?depth=2` en connections desde el MVP o se pospone por costo de
   travesía? → decisión de implementación con datos de rendimiento (#03 §11).

---

## Historial de versiones

| Versión | Fecha | Autor | Cambios |
|---------|-------|-------|---------|
| 0.1 | 2026-07-01 | CTO | Borrador inicial. Estilo REST/JSON + SSE (ADR-013, antes "ADR-A1"), convenciones globales, mapa de recursos por contexto, endpoints del MVP (auth, captura, grafo, query streaming, briefing, feedback), contrato async, seguridad a nivel de API y non-goals. |
| 0.2 | 2026-07-03 | CPTO | Consolidación de ADRs (D-004): la decisión de estilo de API embebida ("ADR-A1") se extrajo a un archivo individual [ADR-013](../02-architecture/adr/ADR-013-rest-json-sse-api-style.md) en `../02-architecture/adr/`; §2 deja solo un índice con enlace. Referencia cruzada normalizada a 3 dígitos. |
