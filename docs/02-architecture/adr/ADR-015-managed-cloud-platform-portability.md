# ADR-015 — Plataforma gestionada sobre un cloud mayor, con portabilidad

> **Architecture Decision Record.** Extraído de la [Infrastructure & Deployment
> Strategy #06](../../06-infrastructure/infrastructure-and-deployment-strategy.md)
> (§3), donde estaba embebido como "ADR-I2". Numeración normalizada al esquema
> canónico de 3 dígitos (`ADR-015`) durante la consolidación de ADRs (deuda
> [D-004](../../000_SYSTEM/012_RISK_AND_DEBT_REGISTER.md); ver [003 §7](../../000_SYSTEM/003_DECISION_FRAMEWORK.md)).
>
> ➕ **Complementado por [ADR-012](./ADR-012-canonical-stack.md) (2026-07-02):**
> confirma Cloudflare como capa edge, almacenamiento de objetos S3-compatible
> (MinIO local / R2 en prod) y BullMQ sobre Redis para colas.

| Metadato | Valor |
|----------|-------|
| Estado | 🟠 Decisión de CTO, sujeta a veto |
| Fecha | 2026-07-01 |
| Autor | CTO |
| Origen | #06 §3 (embebido como "ADR-I2") |

---

## Contexto

Un equipo pequeño no puede permitirse el trabajo operativo de autogestionar base
de datos, colas, secretos y logs. A la vez, mindOS quiere un camino de escalado a
millones sin migrar de casa y sin caer en lock-in propietario difícil de revertir.

## Decisión

Desplegar sobre un **proveedor cloud mayor** usando **servicios gestionados** (BD,
colas, cómputo de contenedores), manteniendo portabilidad vía Docker + IaC.
Recomendación inicial: **AWS** (madurez, PostgreSQL gestionado con soporte
pgvector, ecosistema).

**Regla anti-lock-in:** favorecer servicios estándar (PostgreSQL, Redis,
almacenamiento S3-compatible) sobre servicios propietarios difíciles de migrar,
salvo justificación clara.

### Servicios gestionados objetivo (MVP)

| Necesidad | Servicio gestionado |
|-----------|---------------------|
| Cómputo de contenedores | Servicio de contenedores gestionado (ej. ECS/Fargate o equivalente). |
| Base de datos | PostgreSQL gestionado con pgvector. |
| Caché + colas | Redis gestionado. |
| Object storage | Almacenamiento S3-compatible. |
| Secretos | Gestor de secretos del proveedor. |
| CDN | CDN del proveedor para el frontend. |

## Estado

🟠 Decisión de CTO, sujeta a veto. Complementada por
[ADR-012](./ADR-012-canonical-stack.md) en las decisiones de edge, blobs y colas.

## Consecuencias

- Los servicios gestionados eliminan trabajo operativo que un equipo pequeño no
  puede permitirse.
- Un cloud mayor ofrece el camino de escalado a millones sin migrar de casa.
- La regla anti-lock-in preserva la portabilidad a 10 años.

## Alternativas consideradas

- **PaaS simplificado (Render/Fly/Railway):** excelente velocidad inicial y menor
  curva; **punto de reevaluación válido** si se prioriza time-to-market extremo en
  el MVP. Trade-off: menos control y posible migración futura.
- **Kubernetes propio desde el día uno:** rechazado. Sobre-ingeniería para el MVP;
  complejidad operativa enorme sin equipo de plataforma.
