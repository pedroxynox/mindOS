# 000 — Sistema Operativo del Proyecto (Gobernanza)

| Metadato | Valor |
|----------|-------|
| Versión | 1.0 |
| Estado | 🟢 Vigente |
| Ámbito | Puerta de entrada a la capa de gobernanza de mindOS |
| Depende de | — (raíz de la serie 000) |
| Última actualización | 2026-07-02 |

Bienvenido al **Sistema Operativo del Proyecto** de mindOS. Este directorio (`docs/000_SYSTEM/`) es la **capa de gobernanza**: el conjunto de documentos que rige **toda** la cadena documental de fundación (#00–#08) y **todo** el código del monorepo. Si la cadena #00–#08 responde *qué construimos y cómo*, la serie 000 responde *cómo decidimos, cómo trabajamos y cómo nos mantenemos honestos*.

> **Principio fundacional:** el conocimiento vive en el **repo**, no en el chat. Toda decisión, riesgo, deuda y estado se persiste en estos documentos. Una conversación que no deja rastro en el repo no ocurrió.

## 1. Los 13 documentos de gobernanza (000–012)

| # | Documento | Propósito (una línea) |
|---|-----------|-----------------------|
| 000 | [README](./000_README.md) | Puerta de entrada y mapa de la capa de gobernanza. |
| 001 | [CPTO Charter](./001_CPTO_CHARTER.md) | Quién es el responsable técnico, su mandato y su autoridad. |
| 002 | [Engineering Constitution](./002_ENGINEERING_CONSTITUTION.md) | Los principios inmutables (las leyes) de ingeniería. |
| 003 | [Decision Framework](./003_DECISION_FRAMEWORK.md) | Cómo se toman y se registran las decisiones (ADRs). |
| 004 | [Development Process](./004_DEVELOPMENT_PROCESS.md) | El flujo oficial de comprender→diseñar→implementar→revisar. |
| 005 | [Documentation Standard](./005_DOCUMENTATION_STANDARD.md) | Cómo se escribe y versiona toda la documentación. |
| 006 | [Review Process](./006_REVIEW_PROCESS.md) | Checklists de revisión de código, arquitectura y docs. |
| 007 | [Code Quality](./007_CODE_QUALITY.md) | Estándares ejecutables por lenguaje (los reglamentos). |
| 008 | [AI Collaboration Protocol](./008_AI_COLLABORATION_PROTOCOL.md) | Cómo colabora la IA/CPTO y el ritual de sesión. |
| 009 | [Current State](./009_CURRENT_STATE.md) | Estado vivo del proyecto (foto que se sobreescribe). |
| 010 | [Master Index](./010_MASTER_INDEX.md) | Mapa completo del conocimiento y dueños de la verdad. |
| 011 | [Glossary](./011_GLOSSARY.md) | Lenguaje ubicuo: definiciones canónicas. |
| 012 | [Risk & Debt Register](./012_RISK_AND_DEBT_REGISTER.md) | Registro append-only de riesgos y deuda técnica. |

## 2. Orden de lectura (ingeniero o IA nuevo)
1. **001 — CPTO Charter:** entiende quién manda técnicamente y con qué criterio.
2. **002 — Engineering Constitution:** interioriza los principios que nunca se rompen.
3. **009 — Current State:** descubre dónde está el proyecto **hoy**.
4. **012 — Risk & Debt Register:** conoce lo que está roto, en riesgo o pendiente de pagar.
5. **003 / 004 / 005:** cómo se decide, se trabaja y se documenta.
6. **006 / 007:** cómo se revisa y qué estándares de código aplican.
7. **008:** cómo colaborar (humano o IA) y cómo cerrar cada sesión.
8. **010 / 011:** referencia continua — mapa del conocimiento y glosario.

## 3. Ritual de sesión (resumen)
El detalle completo vive en [008](./008_AI_COLLABORATION_PROTOCOL.md).

**Al EMPEZAR una sesión:**
- Leer [001](./001_CPTO_CHARTER.md) (mandato) + [009](./009_CURRENT_STATE.md) (estado) y, si aplica, [012](./012_RISK_AND_DEBT_REGISTER.md) (riesgos/deuda) para recuperar el contexto **desde el repo**.

**Al TERMINAR una sesión:**
1. Actualizar [009](./009_CURRENT_STATE.md) con el nuevo estado.
2. Registrar en [012](./012_RISK_AND_DEBT_REGISTER.md) todo riesgo o deuda nuevo (append-only).
3. Escribir un ADR en `../02-architecture/adr/` si se tomó una decisión estructural.
4. Cerrar con el **Informe Ejecutivo** (formato en [008](./008_AI_COLLABORATION_PROTOCOL.md)).

## 4. Relación con la cadena de fundación
La serie 000 no reemplaza a la cadena [#00–#08](../README.md); la **gobierna**. Cuando un documento de gobernanza y uno de fundación parecen chocar, gana el principio de la [Constitución (002)](./002_ENGINEERING_CONSTITUTION.md) y se abre un ADR para reconciliarlos.

## Historial de versiones
| Versión | Fecha | Cambios |
|---------|-------|---------|
| 1.0 | 2026-07-02 | Puerta de entrada inicial a la capa de gobernanza. |
