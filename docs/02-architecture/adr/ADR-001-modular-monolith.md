# ADR-001 — Monolito modular sobre microservicios (para empezar)

> **Architecture Decision Record.** Extraído del [TAD #02](../technical-architecture.md)
> (§3), donde estaba embebido como "ADR-01". Numeración normalizada a 3 dígitos
> (`ADR-001`) durante la consolidación de ADRs (deuda [D-004](../../000_SYSTEM/012_RISK_AND_DEBT_REGISTER.md)).
>
> ⚠️ **SUPERADO PARCIALMENTE por [ADR-010](./ADR-010-final-stack-and-two-backends.md)
> (2026-07-01):** el estilo cambió a una arquitectura de **dos backends** (NestJS
> para negocio + Python/FastAPI para IA) desde el inicio, en lugar del monolito
> modular. El principio de fronteras de contexto limpias sigue vigente.

| Metadato | Valor |
|----------|-------|
| Estado | 🟠 Decisión de CTO — superada parcialmente por ADR-010 |
| Fecha | 2026-07-01 |
| Autor | CTO |
| Origen | #02 §3 (embebido) |

---

## Contexto

Los microservicios prematuros son la causa más común de muerte por complejidad
en startups. Añaden sobrecarga operativa (despliegue, observabilidad distribuida,
consistencia entre servicios) que no se justifica sin escala ni equipo grande.

## Decisión

El backend se construye como un **monolito modular** con contextos acotados bien
definidos y fronteras internas explícitas.

Un monolito modular con fronteras limpias nos da velocidad hoy y permite
**extraer servicios** (empezando por los workers de IA) cuando los datos de carga
lo justifiquen.

## Consecuencias

- **Punto de extensión:** los contextos acotados se comunican por interfaces
  internas, de modo que extraer uno a un servicio independiente sea mecánico, no
  una reescritura.

## Alternativas consideradas

- **Microservicios desde el día uno.** Rechazada por costo operativo y velocidad.
