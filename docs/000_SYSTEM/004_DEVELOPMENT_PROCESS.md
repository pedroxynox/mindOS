# 004 — Development Process

| Metadato | Valor |
|----------|-------|
| Versión | 1.0 |
| Estado | 🟢 Vigente |
| Ámbito | El flujo oficial de trabajo, de idea a producción |
| Depende de | [002](./002_ENGINEERING_CONSTITUTION.md), [003](./003_DECISION_FRAMEWORK.md), [006](./006_REVIEW_PROCESS.md); #05, #08 |
| Última actualización | 2026-07-02 |

## 1. El flujo oficial
Ninguna línea de código de producción nace fuera de esta secuencia:

1. **Comprender el problema** — enunciar qué se resuelve y para quién (ancla en #00/#01).
2. **Investigar** — explorar el repo, la cadena documental y prior art; identificar restricciones.
3. **Diseñar (spec)** — producir una especificación en `.kiro/specs/` (requisitos → diseño → tareas).
4. **Documentar** — reflejar decisiones estructurales en un ADR ([003](./003_DECISION_FRAMEWORK.md)) y en el documento de fundación afectado.
5. **Aprobar** — el CPTO (y el founder si es estructural) valida el diseño antes de implementar.
6. **Implementar** — TDD y PBT donde aporte valor (lógica central); código correcto y simple.
7. **Revisar** — según [006](./006_REVIEW_PROCESS.md): PR obligatorio, CI verde, revisión semántica.
8. **Release** — merge a `main` tras aprobación; despliegue según #06.
9. **Feedback** — observar comportamiento real y señales del usuario.
10. **Actualizar [009](./009_CURRENT_STATE.md)** — cerrar la sesión reflejando el nuevo estado y registrando riesgos/deuda en [012](./012_RISK_AND_DEBT_REGISTER.md).

> Corolario de la [Constitución](./002_ENGINEERING_CONSTITUTION.md) §1: nunca programar antes de diseñar; nunca diseñar antes de comprender.

## 2. Definition of Ready (DoR)
Una tarea puede empezar a implementarse solo si:
- El problema está enunciado y anclado a un requisito (#01) o a una fase (#08).
- Existe un diseño aprobado (o es un cambio trivial documentado).
- Los criterios de aceptación son verificables.
- Las dependencias (datos, contratos, decisiones) están resueltas o registradas.

## 3. Definition of Done (DoD)
Una tarea está hecha solo si:
- El código cumple [007](./007_CODE_QUALITY.md) y pasa todos los gates de CI.
- Hay pruebas (unitarias y, donde aplique, de propiedades) que validan comportamiento real, sin mocks que falseen la lógica.
- La documentación afectada y, si aplica, el ADR están actualizados.
- El PR fue revisado y aprobado por el CPTO ([006](./006_REVIEW_PROCESS.md)).
- [009](./009_CURRENT_STATE.md) y [012](./012_RISK_AND_DEBT_REGISTER.md) reflejan el resultado.

## 4. Ramas y Pull Requests
- **Ramas cortas y enfocadas.** Una rama = una unidad de trabajo coherente.
- **PR obligatorio.** **Nunca** se hace push directo a `main`.
- El PR enlaza su spec y su ADR (si lo hay), y describe qué se probó.
- CI verde es condición de merge, no una sugerencia.

## 5. Relación con specs y ADRs
- Las **specs** (`.kiro/specs/{feature}/`) son el vehículo del paso 3–5: requisitos, diseño y tareas.
- Los **ADRs** (`../02-architecture/adr/`) capturan las decisiones estructurales que emergen de una spec, según [003](./003_DECISION_FRAMEWORK.md).
- Una spec sin ADR es válida cuando no toma decisiones estructurales; una decisión estructural sin ADR está prohibida.

## 6. Mapeo del proceso a las fases F0–F5 (#08)
| Fase | Aplicación del proceso |
|------|------------------------|
| **F0** — Cimientos | Diseño ligero; el foco es infraestructura ejecutable, CI/CD e IaC. DoD estricta: nada de "hecho" sin CD a staging. |
| **F1** — Captura | Primera spec de producto completa (Capture Engine): requisitos→diseño→tareas→PBT del camino de captura. |
| **F2** — Comprensión | Spec + PoC de-riesgo previo; eval set de calidad como parte de la DoD. |
| **F3** — Recuperación | Spec de briefing y query; pruebas de grounding (sin alucinación). |
| **F4** — Pulido | Specs de export/borrado, MFA, observabilidad; endurecimiento de seguridad. |
| **F5** — Beta | Proceso orientado a medición; feedback loop rápido, iteración sobre datos. |

## Historial de versiones
| Versión | Fecha | Cambios |
|---------|-------|---------|
| 1.0 | 2026-07-02 | Proceso de desarrollo inicial y mapeo a fases F0–F5. |
