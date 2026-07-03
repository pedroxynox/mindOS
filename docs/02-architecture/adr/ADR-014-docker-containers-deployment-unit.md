# ADR-014 — Contenedores (Docker) como unidad de despliegue

> **Architecture Decision Record.** Extraído de la [Infrastructure & Deployment
> Strategy #06](../../06-infrastructure/infrastructure-and-deployment-strategy.md)
> (§2), donde estaba embebido como "ADR-I1". Numeración normalizada al esquema
> canónico de 3 dígitos (`ADR-014`) durante la consolidación de ADRs (deuda
> [D-004](../../000_SYSTEM/012_RISK_AND_DEBT_REGISTER.md); ver [003 §7](../../000_SYSTEM/003_DECISION_FRAMEWORK.md)).

| Metadato | Valor |
|----------|-------|
| Estado | 🟢 Firme |
| Fecha | 2026-07-01 |
| Autor | CTO |
| Origen | #06 §2 (embebido como "ADR-I1") |

---

## Contexto

mindOS necesita una unidad de despliegue portable y reproducible para todos sus
componentes (API, workers, frontend), que garantice paridad entre entornos
(local, staging, production) y evite el "en mi máquina funciona".

## Decisión

Todo componente (API, workers, frontend) se empaqueta en **imágenes Docker**.

## Estado

🟢 Firme.

## Consecuencias

- Portabilidad total (evita lock-in de proveedor, principio del #02).
- Paridad entre entornos: mismos contenedores en local, staging y production.
- Base para escalar horizontalmente (api stateless, ai-workers por profundidad
  de cola).

## Alternativas consideradas

- **Despliegue directo sobre VM/host sin contenedores.** Rechazado: pierde
  paridad de entornos y portabilidad, y complica el escalado horizontal.
