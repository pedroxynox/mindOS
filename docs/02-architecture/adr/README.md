# Índice de ADRs — Architecture Decision Records

> Registro de decisiones de arquitectura de mindOS. Esquema canónico de
> numeración: **3 dígitos, `ADR-0NN`** (ver [003 §7](../../000_SYSTEM/003_DECISION_FRAMEWORK.md)).
> Todo ADR es un archivo propio en esta carpeta. Los ADR-001..ADR-009 estaban
> antes embebidos en el [TAD #02](../technical-architecture.md) y se consolidaron
> aquí (deuda [D-004](../../000_SYSTEM/012_RISK_AND_DEBT_REGISTER.md)).

| Nº | Título | Estado | Archivo |
|----|--------|--------|---------|
| ADR-001 | Monolito modular sobre microservicios (para empezar) | 🟠 Superado parcialmente por ADR-010 | [ADR-001-modular-monolith.md](./ADR-001-modular-monolith.md) |
| ADR-002 | Procesamiento asíncrono del pipeline de comprensión | 🟢 Firme | [ADR-002-async-comprehension-pipeline.md](./ADR-002-async-comprehension-pipeline.md) |
| ADR-003 | Backend: Python + FastAPI para el núcleo de IA | 🟠 Superado parcialmente por ADR-010 | [ADR-003-backend-python-fastapi.md](./ADR-003-backend-python-fastapi.md) |
| ADR-004 | PostgreSQL como sistema de verdad (incluido el grafo) | 🟠 Confirmado por ADR-012 | [ADR-004-postgresql-source-of-truth.md](./ADR-004-postgresql-source-of-truth.md) |
| ADR-005 | Búsqueda semántica con pgvector (no vector DB dedicada, aún) | 🟠 Confirmado por ADR-012 | [ADR-005-pgvector-semantic-search.md](./ADR-005-pgvector-semantic-search.md) |
| ADR-006 | Cola de trabajos y caché: Redis | 🟢 Firme (complementado por ADR-012) | [ADR-006-redis-queue-cache.md](./ADR-006-redis-queue-cache.md) |
| ADR-007 | Capa de IA con abstracción agnóstica de proveedor (`AIProvider`) | 🟢 Firme | [ADR-007-aiprovider-abstraction.md](./ADR-007-aiprovider-abstraction.md) |
| ADR-008 | Frontend: TypeScript + React (web) + PWA | 🟠 Superado parcialmente por ADR-010 | [ADR-008-frontend-react-pwa.md](./ADR-008-frontend-react-pwa.md) |
| ADR-009 | Estrategia de IA: LLM externo ahora, IP en el motor de contexto, modelos propios después | 🟢 Firme | [ADR-009-ai-strategy-external-llm.md](./ADR-009-ai-strategy-external-llm.md) |
| ADR-010 | Stack definitivo y arquitectura de dos backends | 🟢 Aprobado | [ADR-010-final-stack-and-two-backends.md](./ADR-010-final-stack-and-two-backends.md) |
| ADR-011 | Definición de Hecho de F0 y estrategia de infraestructura | 🟢 Aceptado | [ADR-011-f0-definition-of-done-and-infra.md](./ADR-011-f0-definition-of-done-and-infra.md) |
| ADR-012 | Stack canónico confirmado (edge, almacenamiento de objetos y colas) | 🟢 Aceptado | [ADR-012-canonical-stack.md](./ADR-012-canonical-stack.md) |

## Notas

- **Esquema de numeración:** 3 dígitos (`ADR-0NN`), correlativo y estable. No se
  reutilizan números.
- **Superseción:** cada ADR declara qué documentos o ADRs supersede. ADR-010
  supersede parcialmente a ADR-001, ADR-003 y ADR-008.
- **ADR aún embebidos (fuera de esta consolidación):** el [#04 API](../../04-api/api-design-specification.md)
  contiene `ADR-A1` y el [#06 Infraestructura](../../06-infrastructure/infrastructure-and-deployment-strategy.md)
  contiene `ADR-I1..ADR-I4`. Su migración a archivos individuales queda pendiente
  dentro de la deuda [D-004](../../000_SYSTEM/012_RISK_AND_DEBT_REGISTER.md).
