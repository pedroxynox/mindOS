# mindOS — Documentación de Ingeniería

Este directorio contiene toda la documentación oficial del proyecto mindOS.

## Filosofía

> Nunca programes antes de diseñar.
> Nunca diseñes antes de comprender el problema.
> Nunca implementes una funcionalidad sin documentación previa.

Cada documento de esta cadena depende del anterior. Un documento no se
comienza hasta que su predecesor ha sido validado.

## Cadena Documental

| # | Documento | Estado | Propósito |
|---|-----------|--------|-----------|
| 00 | [Vision & Problem Statement](./00-foundation/vision-and-problem-statement.md) | 🟢 Aprobado | QUÉ problema resolvemos y PARA QUIÉN |
| 01 | [Product Requirements Document (PRD)](./01-product/prd.md) | 🟢 Aprobado | QUÉ debe hacer el producto |
| 02 | [Technical Architecture Document (TAD)](./02-architecture/technical-architecture.md) | 🟢 Aprobado | CÓMO lo construimos a nivel de sistema |
| 03 | [Data Architecture & Domain Model](./03-data/data-architecture-and-domain-model.md) | 🟢 Aprobado | El modelo de información central |
| 04 | [API Design Specification](./04-api/api-design-specification.md) | 🟢 Aprobado | Contratos entre servicios |
| 05 | [Engineering Standards & Conventions](./05-engineering/engineering-standards-and-conventions.md) | 🟢 Aprobado | Cómo se escribe, revisa y despliega código |
| 06 | [Infrastructure & Deployment Strategy](./06-infrastructure/infrastructure-and-deployment-strategy.md) | 🟢 Aprobado | Entornos, CI/CD, observabilidad |
| 07 | [Security & Privacy Framework](./07-security/security-and-privacy-framework.md) | 🟢 Aprobado | Políticas de datos, auth, compliance |
| 08 | [Roadmap Técnico](./08-roadmap/technical-roadmap.md) | 🟡 En revisión | Secuencia de implementación por fases |

### Leyenda de estados
- ⚪ Pendiente — aún no iniciado
- 🟡 En revisión — redactado, en proceso de validación
- 🟢 Aprobado — validado y en vigor
- 🔵 En evolución — aprobado pero sujeto a actualización activa

## Regla de oro

Ningún documento marcado como 🟢 Aprobado se modifica sin dejar registro del
cambio (fecha, autor, motivo) en su sección de historial de versiones.
