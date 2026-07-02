# ADR-002 — Procesamiento asíncrono del pipeline de comprensión

> **Architecture Decision Record.** Extraído del [TAD #02](../technical-architecture.md)
> (§3), donde estaba embebido como "ADR-02". Numeración normalizada a 3 dígitos
> (`ADR-002`) durante la consolidación de ADRs (deuda [D-004](../../000_SYSTEM/012_RISK_AND_DEBT_REGISTER.md)).

| Metadato | Valor |
|----------|-------|
| Estado | 🟢 Firme (deriva de FR-1.1 + FR-2.x) |
| Fecha | 2026-07-01 |
| Autor | CTO |
| Origen | #02 §3 (embebido) |

---

## Contexto

El requisito de captura instantánea (< 3s) no puede bloquear al usuario esperando
a la IA. Además conviene desacoplar el costo/latencia del LLM de la experiencia de
captura, y permitir reintentos y escalado independiente.

## Decisión

La captura es síncrona y devuelve en < 3s. La comprensión (extracción de
entidades, embeddings, linking) ocurre en **workers asíncronos** vía cola de
trabajos.

## Consecuencias

- Cumple el requisito de captura instantánea sin bloquear al usuario.
- Desacopla el costo/latencia del LLM de la experiencia de captura.
- Permite reintentos idempotentes y escalado independiente de los workers.
