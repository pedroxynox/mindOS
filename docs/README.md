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
| 00 | [Vision & Problem Statement](./00-foundation/vision-and-problem-statement.md) | 🟡 En revisión | QUÉ problema resolvemos y PARA QUIÉN |
| 01 | Product Requirements Document (PRD) | ⚪ Pendiente | QUÉ debe hacer el producto |
| 02 | Technical Architecture Document (TAD) | ⚪ Pendiente | CÓMO lo construimos a nivel de sistema |
| 03 | Data Architecture & Domain Model | ⚪ Pendiente | El modelo de información central |
| 04 | API Design Specification | ⚪ Pendiente | Contratos entre servicios |
| 05 | Engineering Standards & Conventions | ⚪ Pendiente | Cómo se escribe, revisa y despliega código |
| 06 | Infrastructure & Deployment Strategy | ⚪ Pendiente | Entornos, CI/CD, observabilidad |
| 07 | Security & Privacy Framework | ⚪ Pendiente | Políticas de datos, auth, compliance |
| 08 | Roadmap Técnico | ⚪ Pendiente | Secuencia de implementación por fases |

### Leyenda de estados
- ⚪ Pendiente — aún no iniciado
- 🟡 En revisión — redactado, en proceso de validación
- 🟢 Aprobado — validado y en vigor
- 🔵 En evolución — aprobado pero sujeto a actualización activa

## Regla de oro

Ningún documento marcado como 🟢 Aprobado se modifica sin dejar registro del
cambio (fecha, autor, motivo) en su sección de historial de versiones.
