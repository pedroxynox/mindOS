# 003 — Decision Framework

| Metadato | Valor |
|----------|-------|
| Versión | 1.0 |
| Estado | 🟢 Vigente |
| Ámbito | Cómo se toman, evalúan y registran las decisiones técnicas |
| Depende de | [001](./001_CPTO_CHARTER.md), [002](./002_ENGINEERING_CONSTITUTION.md) |
| Última actualización | 2026-07-03 |

## 1. Propósito
Toda decisión técnica de mindOS se toma con el mismo método: explícito, trazable y proporcional a su riesgo. Este documento define los criterios, cómo comparar alternativas, cuándo se exige un ADR y qué plantilla usar.

## 2. Criterios de decisión
Cada decisión se evalúa contra cuatro ejes:
1. **Reversibilidad** — ¿es una puerta de una vía (*one-way door*) o de dos vías (*two-way door*)? Las de dos vías se toman rápido y se corrigen con datos; las de una vía se estudian a fondo.
2. **Riesgo** — ¿qué puede salir mal y con qué impacto sobre el proyecto, el usuario o el dato?
3. **Coste** — coste de construir, operar y mantener; incluye coste cognitivo y de contratación.
4. **Alineación con la visión a 10 años** — ¿acerca o aleja del bucle de valor y del sistema operativo personal del #00?

## 3. Cómo evaluar alternativas
Nunca se decide sobre una sola opción. Se listan al menos dos y se comparan en una tabla de trade-offs:

| Alternativa | Reversibilidad | Riesgo | Coste | Alineación 10 años | Firmeza |
|-------------|----------------|--------|-------|--------------------|---------|
| Opción A (recomendada) | Two-way | Bajo | Medio | Alta | 🟢 |
| Opción B | One-way | Alto | Bajo | Media | 🟠 |
| Opción C (descartada) | — | — | — | Baja | ⚪️ |

La recomendación se marca y se justifica por qué gana en el balance, no en un solo eje.

## 4. Niveles de firmeza
- 🟢 **Firme:** convicción alta, respaldada por principios o datos. Cuestionarla requiere evidencia nueva.
- 🟠 **Opinión fuerte:** recomendación con criterio, pero abierta a un buen contraargumento.
- ⚪️ **Tentativa:** hipótesis o preferencia débil; se decide rápido y se revisa.

## 5. Cuándo se EXIGE un ADR
Un ADR (Architecture Decision Record) es **obligatorio** cuando la decisión implica:
- **Cambio de stack** (lenguaje, framework, motor de datos, proveedor).
- **Cambio de arquitectura** (fronteras de contexto, número de servicios, patrón estructural).
- **Cambio de alcance del MVP** (añadir o quitar del roadmap #08).
- **Cualquier decisión irreversible** (puerta de una vía) con impacto de proyecto.

Las decisiones reversibles de bajo impacto (elección de librería dentro del stack, refactor interno) se registran en [012](./012_RISK_AND_DEBT_REGISTER.md) o en el documento afectado, sin ADR — salvo que sean estructurales.

## 6. Plantilla de ADR
```markdown
# ADR-0NN — Título de la decisión

| Metadato | Valor |
|----------|-------|
| Estado | Propuesto / 🟢 Aprobado / Superado |
| Fecha | AAAA-MM-DD |
| Decisores | Founder + CPTO |

## Contexto
Qué situación fuerza la decisión y qué restricciones aplican.

## Decisión
Qué se decide, en términos accionables.

## Estado
Propuesto / Aprobado / Superado (y por qué ADR, si aplica).

## Consecuencias
Positivas, negativas (aceptadas conscientemente) y mitigaciones.

## Alternativas consideradas
Opciones evaluadas y por qué se descartaron.
```

## 7. REGLA: unificación del sistema de ADRs 🟢
Los ADR se gestionan como **archivos individuales** en `../02-architecture/adr/`, con un **esquema canónico de numeración de 3 dígitos: `ADR-0NN`** (`ADR-001`, …, `ADR-012`, …).

**Reglas:**
1. **Todo ADR es un archivo propio** en `../02-architecture/adr/`. No se embeben ADRs dentro de otros documentos.
2. **Esquema canónico de ID: 3 dígitos, `ADR-0NN`.** Es correlativo, estable y no se reutiliza. Esta es la forma definitiva; **no hay migración futura a 4 dígitos** (fue una aspiración previa que se descarta: la realidad y lo consistente en el repo es 3 dígitos, alineado con `ADR-010`/`011`/`012`).
3. Los ADR que estuvieron **embebidos en el [#02 Technical Architecture](../02-architecture/technical-architecture.md)** (antes "ADR-01".."ADR-09") se migraron a archivos individuales `ADR-001`..`ADR-009`, dejando en #02 solo un índice con enlaces. El índice de todos los ADR vive en [`../02-architecture/adr/README.md`](../02-architecture/adr/README.md). Esta consolidación se registra como deuda [D-004](./012_RISK_AND_DEBT_REGISTER.md) (aún pendiente migrar los ADR embebidos en #04 `ADR-A*` y #06 `ADR-I*`).
4. Cada archivo ADR declara qué documentos o ADRs supersede, y esos documentos reciben la cabecera de aviso del [005](./005_DOCUMENTATION_STANDARD.md).

## 8. "Disagree & commit"
Si el CPTO objeta y el founder decide igual, la objeción y su motivo se registran en el ADR como **decisión del founder**, y se ejecuta con lealtad total. El desacuerdo se documenta una vez; después, el equipo rema junto.

## Historial de versiones
| Versión | Fecha | Cambios |
|---------|-------|---------|
| 1.0 | 2026-07-02 | Framework inicial de decisiones + regla de unificación de ADRs. |
| 1.1 | 2026-07-02 | Aclaración transitoria del esquema de numeración de ADRs. |
| 1.2 | 2026-07-03 | Esquema canónico de ADR fijado en **3 dígitos `ADR-0NN`** (se descarta la migración futura a 4 dígitos). §7 actualizada tras consolidar los ADR embebidos del #02 en archivos individuales `ADR-001`..`ADR-009` (D-004); plantilla §6 alineada a `ADR-0NN`. |
