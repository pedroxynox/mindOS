# ADR-006 — Cola de trabajos y caché: Redis

> **Architecture Decision Record.** Extraído del [TAD #02](../technical-architecture.md)
> (§5), donde estaba embebido como "ADR-06". Numeración normalizada a 3 dígitos
> (`ADR-006`) durante la consolidación de ADRs (deuda [D-004](../../000_SYSTEM/012_RISK_AND_DEBT_REGISTER.md)).
>
> ➕ Complementado por [ADR-012](./ADR-012-canonical-stack.md) (D7): **BullMQ sobre
> Redis** como cola concreta del pipeline de comprensión.

| Metadato | Valor |
|----------|-------|
| Estado | 🟢 Firme |
| Fecha | 2026-07-01 |
| Autor | CTO |
| Origen | #02 §5 (embebido) |

---

## Contexto

Se necesita caché y una cola de trabajos asíncronos para el pipeline de
comprensión, con el mínimo de componentes operativos en la fase inicial.

## Decisión

**Redis** para caché y como backend de la cola de trabajos asíncronos (con un
framework de workers sobre él).

## Consecuencias

- Estándar probado, simple, cubre caché y colas con un solo componente en la fase
  inicial.
