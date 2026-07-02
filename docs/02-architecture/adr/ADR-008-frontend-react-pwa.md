# ADR-008 — Frontend: TypeScript + React (web responsive) + PWA

> **Architecture Decision Record.** Extraído del [TAD #02](../technical-architecture.md)
> (§5), donde estaba embebido como "ADR-08". Numeración normalizada a 3 dígitos
> (`ADR-008`) durante la consolidación de ADRs (deuda [D-004](../../000_SYSTEM/012_RISK_AND_DEBT_REGISTER.md)).
>
> ⚠️ **SUPERADO PARCIALMENTE por [ADR-010](./ADR-010-final-stack-and-two-backends.md)
> (2026-07-01):** la superficie primaria pasa a **Flutter (móvil, mobile-first)**
> por el mercado LatAm; la web queda como complemento secundario/futuro.

| Metadato | Valor |
|----------|-------|
| Estado | 🟠 Decisión de CTO — superada parcialmente por ADR-010 |
| Fecha | 2026-07-01 |
| Autor | CTO |
| Origen | #02 §5 (embebido) |

---

## Contexto

Se buscaba un ecosistema maduro, con contratación sencilla, que cubriera la
captura móvil del MVP sin el costo de apps nativas (alineado con non-goals del
PRD).

## Decisión

Superficie web en **React + TypeScript**, responsive (desktop-primary), con
capacidades **PWA** para la captura móvil. El framework concreto (Next.js vs. SPA
con Vite) se decidiría en la fase de frontend; recomendación inicial: Next.js por
routing, SSR opcional y madurez.

## Consecuencias

- **Trade-off aceptado:** una PWA tiene limitaciones frente a nativo (captura en
  background, notificaciones en iOS). Aceptable para MVP; app nativa era un
  candidato de V2.
- **Nota histórica:** ADR-010 adelantó esa app nativa al hacer Flutter la
  superficie primaria desde el inicio.
