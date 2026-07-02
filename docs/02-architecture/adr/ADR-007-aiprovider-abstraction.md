# ADR-007 — Capa de IA con abstracción agnóstica de proveedor

> **Architecture Decision Record.** Extraído del [TAD #02](../technical-architecture.md)
> (§5), donde estaba embebido como "ADR-07". Numeración normalizada a 3 dígitos
> (`ADR-007`) durante la consolidación de ADRs (deuda [D-004](../../000_SYSTEM/012_RISK_AND_DEBT_REGISTER.md)).
>
> ➕ Reafirmado por [ADR-010](./ADR-010-final-stack-and-two-backends.md) y
> [ADR-012](./ADR-012-canonical-stack.md) (D4): ningún SDK de LLM se invoca fuera
> de la capa `AIProvider`.

| Metadato | Valor |
|----------|-------|
| Estado | 🟢 Firme (principio anti-lock-in) |
| Fecha | 2026-07-01 |
| Autor | CTO |
| Origen | #02 §5 (embebido) |

---

## Contexto

El mercado de modelos cambia cada trimestre. No podemos acoplar la lógica de
negocio a un proveedor concreto.

## Decisión

Todo acceso a LLMs pasa por una **capa de abstracción interna** (interfaz
`AIProvider`) que oculta al proveedor concreto. El MVP usa un LLM de terceros vía
API (decisión D6 del PRD).

## Consecuencias

- La abstracción permite: cambiar de proveedor, hacer A/B entre modelos, enrutar
  por costo/calidad, y migrar a modelos propios post-MVP sin tocar la lógica de
  dominio.
- **Nota:** La elección del proveedor concreto (costo, latencia, privacidad,
  residencia de datos) es una decisión con implicaciones de negocio y privacidad;
  se cierra junto con #07 (Security & Privacy Framework).
