# ADR-013 — REST/JSON como estilo primario + SSE para streaming

> **Architecture Decision Record.** Extraído de la [API Design Specification #04](../../04-api/api-design-specification.md)
> (§2), donde estaba embebido como "ADR-A1". Numeración normalizada al esquema
> canónico de 3 dígitos (`ADR-013`) durante la consolidación de ADRs (deuda
> [D-004](../../000_SYSTEM/012_RISK_AND_DEBT_REGISTER.md); ver [003 §7](../../000_SYSTEM/003_DECISION_FRAMEWORK.md)).
>
> ⚠️ **REVISADO por [ADR-010](./ADR-010-final-stack-and-two-backends.md)
> (2026-07-01):** el tiempo real pasa de **SSE** a **WebSocket** y la API la sirve
> **NestJS** (no FastAPI); SSE queda como opción. Los recursos y endpoints del #04
> siguen siendo el contrato de referencia.

| Metadato | Valor |
|----------|-------|
| Estado | 🟠 Decisión de CTO, sujeta a veto — revisada parcialmente por [ADR-010](./ADR-010-final-stack-and-two-backends.md) (SSE → WebSocket) |
| Fecha | 2026-07-01 |
| Autor | CTO |
| Origen | #04 §2 (embebido como "ADR-A1") |

---

## Contexto

La API es el único punto de contacto entre las superficies (web, PWA móvil, y
futuras) y el núcleo. Hace falta fijar el estilo del contrato: cómo se modelan
las operaciones de recursos y cómo se transmiten las respuestas de IA que fluyen
token a token (consultas contextuales).

## Decisión

- **API REST sobre JSON** para operaciones de recursos.
- **Server-Sent Events (SSE)** para respuestas de IA que se transmiten token a
  token (consultas contextuales).

## Estado

🟠 Decisión de CTO, sujeta a veto. Revisada parcialmente por
[ADR-010](./ADR-010-final-stack-and-two-backends.md): el tiempo real pasa a
**WebSocket** (SSE opcional) y NestJS actúa como capa de API.

## Consecuencias

- REST es universal, cacheable, fácil de consumir desde cualquier cliente y de
  depurar.
- SSE cubre el streaming de respuestas del LLM con mínima complejidad
  (unidireccional servidor→cliente, sobre HTTP, sin la sobrecarga de WebSockets).
- Tras [ADR-010](./ADR-010-final-stack-and-two-backends.md), el canal de tiempo
  real se unifica en WebSocket; SSE queda disponible como alternativa.

## Alternativas consideradas

- **GraphQL.** Potente para consultas flexibles del grafo, pero añade complejidad
  de caché, seguridad (queries costosas) y tooling que no se justifica en el MVP.
  **Punto de reevaluación:** si las superficies necesitan consultas de grafo muy
  variables, se evalúa GraphQL para el subdominio de lectura del grafo.
- **WebSockets para todo.** Rechazada en su momento: bidireccional y con estado,
  innecesario para el MVP; SSE bastaba para streaming. (ADR-010 posteriormente
  adopta WebSocket para el tiempo real por otros motivos de arquitectura.)
