# ADR-016 — Toda la infraestructura se define como código

> **Architecture Decision Record.** Extraído de la [Infrastructure & Deployment
> Strategy #06](../../06-infrastructure/infrastructure-and-deployment-strategy.md)
> (§4), donde estaba embebido como "ADR-I3". Numeración normalizada al esquema
> canónico de 3 dígitos (`ADR-016`) durante la consolidación de ADRs (deuda
> [D-004](../../000_SYSTEM/012_RISK_AND_DEBT_REGISTER.md); ver [003 §7](../../000_SYSTEM/003_DECISION_FRAMEWORK.md)).
>
> ℹ️ **Nota:** la IaC completa y la infraestructura pesada se **difieren a
> pre-beta** según [ADR-011](./ADR-011-f0-definition-of-done-and-infra.md) y
> [ADR-012](./ADR-012-canonical-stack.md) (D8). El principio de "nada a mano en la
> consola" sigue vigente cuando se aprovisione infraestructura.

| Metadato | Valor |
|----------|-------|
| Estado | 🟢 Firme |
| Fecha | 2026-07-01 |
| Autor | CTO |
| Origen | #06 §4 (embebido como "ADR-I3") |

---

## Contexto

La infraestructura creada a mano en la consola del cloud no es reproducible, no
se revisa ni se recupera fácilmente ante desastres, y su historia de cambios se
pierde.

## Decisión

La infraestructura se declara con **Terraform** (o equivalente), versionada en el
repositorio. Nada se crea a mano en la consola del cloud.

## Estado

🟢 Firme. Su ejecución completa se difiere a pre-beta
([ADR-011](./ADR-011-f0-definition-of-done-and-infra.md),
[ADR-012](./ADR-012-canonical-stack.md) D8).

## Consecuencias

- Reproducibilidad de entornos.
- Revisión por PR (igual que el código, #05).
- Recuperación ante desastres y trazabilidad de cambios de infraestructura.

## Alternativas consideradas

- **Aprovisionamiento manual en la consola del cloud (ClickOps).** Rechazado: no
  reproducible, no revisable y sin trazabilidad.
