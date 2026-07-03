# ADR-017 — Estrategia de despliegue: rolling con health checks (MVP)

> **Architecture Decision Record.** Extraído de la [Infrastructure & Deployment
> Strategy #06](../../06-infrastructure/infrastructure-and-deployment-strategy.md)
> (§5), donde estaba embebido como "ADR-I4". Numeración normalizada al esquema
> canónico de 3 dígitos (`ADR-017`) durante la consolidación de ADRs (deuda
> [D-004](../../000_SYSTEM/012_RISK_AND_DEBT_REGISTER.md); ver [003 §7](../../000_SYSTEM/003_DECISION_FRAMEWORK.md)).

| Metadato | Valor |
|----------|-------|
| Estado | 🟠 Decisión de CTO, sujeta a veto |
| Fecha | 2026-07-01 |
| Autor | CTO |
| Origen | #06 §5 (embebido como "ADR-I4") |

---

## Contexto

El pipeline de CD debe llevar el código a producción sin downtime y con capacidad
de rollback seguro, con una complejidad razonable para el tamaño del equipo y del
MVP.

## Decisión

Despliegues **rolling** con health checks; migraciones de BD compatibles hacia
atrás (expand/contract). Las migraciones se versionan (Alembic para el backend
Python) y son siempre compatibles hacia atrás para permitir rollback sin pérdida.

## Estado

🟠 Decisión de CTO, sujeta a veto.

## Consecuencias

- Cero downtime con complejidad razonable.
- Rollback seguro gracias a migraciones compatibles hacia atrás.
- Blue/green o canary se adoptan cuando el volumen de usuarios lo justifique.

## Alternativas consideradas

- **Blue/green o canary desde el MVP.** Pospuesto: mayor complejidad operativa no
  justificada al volumen actual; se adoptará cuando el número de usuarios lo exija.
