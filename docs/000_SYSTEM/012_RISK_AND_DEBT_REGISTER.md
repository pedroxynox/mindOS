# 012 — Risk & Debt Register

| Metadato | Valor |
|----------|-------|
| Versión | 1.0 |
| Estado | 🟢 Vigente |
| Ámbito | Registro append-only de riesgos y deuda técnica de mindOS |
| Depende de | [001](./001_CPTO_CHARTER.md), [009](./009_CURRENT_STATE.md) |
| Última actualización | 2026-07-02 |

## Reglas del registro
1. **Append-only:** las filas **nunca se borran**. La historia es parte del valor.
2. Un ítem solo cambia de **estado** (`abierto` → `mitigado` / `aceptado` / `cerrado`), añadiendo una **nota fechada** en su fila (columna Estado).
3. Cada ítem tiene un **ID estable** (`R-NNN` para riesgos, `D-NNN` para deuda) que no se reutiliza.
4. Todo riesgo o deuda nuevo detectado en una sesión se añade aquí al cierre (ritual de [008](./008_AI_COLLABORATION_PROTOCOL.md)).
5. La deuda no registrada está **prohibida** ([002](./002_ENGINEERING_CONSTITUTION.md) §14).

## Tabla de RIESGOS
| ID | Descripción | Severidad | Probabilidad | Mitigación | Estado | Fecha |
|----|-------------|-----------|--------------|------------|--------|-------|
| R-001 | Calidad de comprensión de F2 aún no de-riesgada: el pipeline IA podría no "entender" lo bastante bien. | Alto | Media | PoC aislada de comprensión en paralelo a F1; eval set con umbral de aceptación antes de invertir en F3. | 🔴 abierto | 2026-07-02 |
| R-002 | Auth propia (JWT) sin endurecer: falta rate limiting, rotación de refresh y protección contra enumeración por timing. | Medio | Media | Endurecimiento planificado en F4 (#07); registrar controles y añadir pruebas de seguridad. | 🔴 abierto | 2026-07-02 |
| R-003 | F0 declarado "hecho" sin cumplir su Definición de Hecho (falta CD a staging + IaC) → falsa señal de avance. | Medio | Alta | Cerrar CD+IaC o posponer formalmente vía ADR; corregir la señal en README/009. | 🟢 Mitigado — (2026-07-02) Abordado por ADR-011 (propuesto): DoD mínima de F0 + diferimiento de infra. Pendiente de aprobación del founder. (2026-07-02) ADR-011 ACEPTADO: DoD de F0 redefinida a criterio realista. Queda como trabajo (no riesgo) ejecutar CD mínimo + IaC. | 2026-07-02 |
| R-004 | Deriva documental: el roadmap #08 contradice ADR-010 (aún dice "backend FastAPI + frontend React" en F0 y "auth vía proveedor gestionado" en F0/F1). | Medio | Alta | Aplicar cabecera de aviso al #08 y corregir el texto ([005](./005_DOCUMENTATION_STANDARD.md) §6). | 🟡 En corrección — (2026-07-02) Corrección de deriva del #08 en curso vía PR de coherencia + ADR-010 referenciado. | 2026-07-02 |

## Tabla de DEUDA
| ID | Descripción | Interés / coste | Plan | Estado | Fecha |
|----|-------------|-----------------|------|--------|-------|
| D-001 | Sin lockfiles commiteados; CI usa `npm install` (no `npm ci`). | Builds no reproducibles; riesgo de "funciona en mi máquina" y regresiones silenciosas por drift de dependencias. | Commitear lockfiles y migrar CI a instalación reproducible (`npm ci` / equivalentes por app). | 🔴 abierto | 2026-07-02 |
| D-002 | nodes/edges + RLS del #03 no implementados (hoy Prisma solo tiene `User`). | El core del producto (grafo) aún no existe; bloquea F1/F2. | Implementar tablas nodes/edges y RLS como parte del diseño de F1. | 🔴 abierto (esperado por fase) | 2026-07-02 |
| D-003 | TODO de "dummy compare" en login: posible side-channel de enumeración de usuarios por timing. | Fuga de existencia de cuentas; riesgo de privacidad/seguridad. | Implementar comparación en tiempo constante y respuesta uniforme; cubrir con test. | 🔴 abierto | 2026-07-02 |
| D-004 | ADRs inconsistentes: ADR-01..09 embebidos en #02 vs ADR-010 como archivo suelto, sin cero-padding uniforme. | Trazabilidad rota; difícil superseder decisiones individuales. | Migrar ADRs embebidos a archivos `ADR-0001..0009`, normalizar `ADR-0010`, dejar índice en #02 ([003](./003_DECISION_FRAMEWORK.md) §7). Incluye renombrar ADR-010→ADR-0010 y ADR-011→ADR-0011 al migrar; hasta entonces los nuevos ADR usan 3 dígitos (ver 003). | 🔴 abierto | 2026-07-02 |

## Historial de versiones
| Versión | Fecha | Cambios |
|---------|-------|---------|
| 1.0 | 2026-07-02 | Registro inicial: R-001..R-004 y D-001..D-004 sembrados. |
| 1.1 | 2026-07-02 | Actualización de estado de R-003/R-004 y plan de D-004. |
| 1.2 | 2026-07-02 | R-003 mitigado tras aprobación de ADR-011. |
