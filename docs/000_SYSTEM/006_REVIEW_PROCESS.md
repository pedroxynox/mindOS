# 006 — Review Process

| Metadato | Valor |
|----------|-------|
| Versión | 1.0 |
| Estado | 🟢 Vigente |
| Ámbito | Cómo se revisan código, arquitectura y documentación antes de integrar |
| Depende de | [004](./004_DEVELOPMENT_PROCESS.md), [007](./007_CODE_QUALITY.md); #05 |
| Última actualización | 2026-07-02 |

## 1. Principio
Ninguna revisión es un trámite. Se revisa el **comportamiento** (qué hace el cambio y cómo puede fallar), no solo la sintaxis. El aprobador final es el **CPTO**.

## 2. Requisitos de PR (condición de merge)
Un PR no se integra sin **todos** estos:
- [ ] **CI verde** (lint + tipos + tests + build en las apps afectadas).
- [ ] **Tests** que cubren el comportamiento nuevo/cambiado (unitarios y PBT donde aplique).
- [ ] **Cobertura** por encima del umbral de [007](./007_CODE_QUALITY.md) para el módulo afectado.
- [ ] **Sin secretos** ni credenciales en el diff.
- [ ] **ADR** enlazado si el cambio es estructural ([003](./003_DECISION_FRAMEWORK.md)).
- [ ] Documentación afectada actualizada ([005](./005_DOCUMENTATION_STANDARD.md)).
- [ ] Descripción del PR: qué cambia, por qué, y qué se probó.

## 3. Checklist — revisión de código
- ¿Cumple los principios de [002](./002_ENGINEERING_CONSTITUTION.md) y las reglas de [007](./007_CODE_QUALITY.md)?
- ¿Las fronteras de contexto se respetan (sin fugas entre bounded contexts)?
- ¿El manejo de errores es explícito; el fallo degrada sin perder datos?
- ¿Hay `any`/tipos laxos, funciones demasiado grandes, complejidad excesiva?
- ¿Los nombres comunican intención? ¿Hay lógica muerta o duplicada?
- ¿Los tests prueban lógica real (sin mocks que falseen el resultado)?

## 4. Checklist — revisión de arquitectura
- ¿La decisión respeta las fronteras de dos backends (ADR-010) y la capa `AIProvider`?
- ¿Se introduce una puerta de una vía sin ADR?
- ¿El cambio añade complejidad distribuida no justificada?
- ¿Se preserva "la captura cruda es sagrada" y "la IA propone, el usuario confirma"?
- ¿Aislamiento por usuario + RLS intactos?

## 5. Checklist — revisión de documentación
- ¿Tabla de metadatos e historial de versiones presentes ([005](./005_DOCUMENTATION_STANDARD.md))?
- ¿Enlaces relativos válidos y `Depende de` declarado?
- ¿Si un ADR supersede un documento, este lleva su cabecera de aviso?
- ¿Firmeza (🟢🟠⚪️) marcada donde hay recomendación?

## 6. Revisión semántica
Además de la revisión línea a línea, se reconstruye el cambio como **narrativa por preocupación** (no por archivo): qué comportamiento cambia, qué invariantes toca, qué casos límite abre. Un cambio que no puede explicarse a ese nivel no está listo para revisar.

## 7. Comentarios bloqueantes vs no bloqueantes
- **🔴 Bloqueante:** impide el merge (fallo de correctness, seguridad, violación de principio, falta de tests).
- **🟡 No bloqueante:** mejora sugerida; se puede resolver en el PR o en un follow-up registrado.
Cada comentario indica explícitamente su tipo.

## 8. Definition of Done (recordatorio)
La DoD completa vive en [004](./004_DEVELOPMENT_PROCESS.md) §3. La revisión no aprueba nada que no la cumpla.

## Historial de versiones
| Versión | Fecha | Cambios |
|---------|-------|---------|
| 1.0 | 2026-07-02 | Proceso de revisión inicial: checklists de código, arquitectura y docs. |
