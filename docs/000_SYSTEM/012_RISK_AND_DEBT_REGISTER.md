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
| R-005 | Estrategia offline-first / sincronización Drift↔API sin diseñar; riesgo de pérdida o conflicto de capturas. | Medio | Media | Diseñar el protocolo de sync y resolución de conflictos en el spec de F1. | 🟠 Abierto | 2026-07-02 |
| R-006 | La suite de integración de F1 (aislamiento P1/P8, dedup de cola P7, no-pérdida P2, blobs) aún NO se ha ejecutado contra infraestructura real; un test "verde en teoría" podría fallar en la práctica | Medio | Media | Levantar docker-compose (Postgres+RLS rol no-owner, Redis, MinIO) y ejecutar los *.integration.spec.ts + `flutter test` | 🟠 Abierto | 2026-07-02 |

## Tabla de DEUDA
| ID | Descripción | Interés / coste | Plan | Estado | Fecha |
|----|-------------|-----------------|------|--------|-------|
| D-001 | Sin lockfiles commiteados; CI usa `npm install` (no `npm ci`). | Builds no reproducibles; riesgo de "funciona en mi máquina" y regresiones silenciosas por drift de dependencias. | Commitear lockfiles y migrar CI a instalación reproducible (`npm ci` / equivalentes por app). | 🟡 En progreso — (2026-07-02) API: package-lock.json commiteado y CI migrado a `npm ci` + caché. Pendiente: pubspec.lock (móvil, requiere Flutter) y lock de deps Python (ai). | 2026-07-02 |
| D-002 | nodes/edges + RLS del #03 no implementados (hoy Prisma solo tiene `User`). | El core del producto (grafo) aún no existe; bloquea F1/F2. | Implementar tablas nodes/edges y RLS como parte del diseño de F1. | 🔴 abierto (esperado por fase) | 2026-07-02 |
| D-003 | TODO de "dummy compare" en login: posible side-channel de enumeración de usuarios por timing. | Fuga de existencia de cuentas; riesgo de privacidad/seguridad. | Implementar comparación en tiempo constante y respuesta uniforme; cubrir con test. | 🔴 abierto | 2026-07-02 |
| D-004 | ADRs inconsistentes: ADR-01..09 embebidos en #02 vs ADR-010 como archivo suelto, sin cero-padding uniforme. | Trazabilidad rota; difícil superseder decisiones individuales. | Migrar ADRs embebidos a archivos `ADR-0001..0009`, normalizar `ADR-0010`, dejar índice en #02 ([003](./003_DECISION_FRAMEWORK.md) §7). Incluye renombrar ADR-010→ADR-0010 y ADR-011→ADR-0011 al migrar; hasta entonces los nuevos ADR usan 3 dígitos (ver 003). | 🔴 abierto | 2026-07-02 |
| D-005 | Sin rastreo de errores (Sentry) ni gestión formal de secretos. | Incidentes ciegos en prod y secretos mal gestionados. | Adoptar Sentry (móvil+backends) y un gestor de secretos antes de pre-beta. | 🟠 Abierto | 2026-07-02 |
| D-006 | El barrido de reconciliación y el janitor de blobs iteran sobre TODOS los usuarios por lote | Coste O(usuarios) por ejecución; no escala a millones | Acotar a usuarios con actividad reciente / índice dedicado antes de escala | 🟠 Abierto | 2026-07-02 |
| D-007 | El código Flutter solo se valida en CI (no hay SDK de Flutter en el entorno de desarrollo) → bucles de iteración lentos | Feedback lento en cambios móviles; riesgo de fallos detectados tarde | Aceptar CI-driven para móvil o provisionar un entorno con Flutter cuando el volumen lo justifique | 🟢 Mitigado — (2026-07-02) SDK de Flutter instalado y operativo en el entorno; el móvil ya se valida localmente, no solo en CI. | 2026-07-02 |
| D-009 | El widget test de la pantalla de captura se cuelga en CI (timeout) y no es depurable sin un entorno Flutter local; queda skippeado | Cobertura de UI ausente para la pantalla de captura (la pantalla sí pasa `flutter analyze`; la lógica sí tiene tests) | Depurar con Flutter local (probable `tester.runAsync` para el stream Drift) y reactivar los tests; relacionado con D-007 | 🟢 Cerrado — (2026-07-02) Flutter ejecutable localmente; diagnosticada la causa real (un `Timer(Duration.zero)` de cierre del stream de Drift quedaba pendiente al disponer el árbol → cuelgue). Arreglado desmontando el árbol y vaciando ese timer con un `pump` acotado; widget tests reactivados (16/16 verde). | 2026-07-02 |

## Historial de versiones
| Versión | Fecha | Cambios |
|---------|-------|---------|
| 1.0 | 2026-07-02 | Registro inicial: R-001..R-004 y D-001..D-004 sembrados. |
| 1.1 | 2026-07-02 | Actualización de estado de R-003/R-004 y plan de D-004. |
| 1.2 | 2026-07-02 | R-003 mitigado tras aprobación de ADR-011. |
| 1.3 | 2026-07-02 | Alta de R-005 (offline sync) y D-005 (observabilidad/secretos) tras ADR-012. |
| 1.4 | 2026-07-02 | Alta de R-006, D-006, D-007; D-001 en progreso tras hardening de reproducibilidad de la API. |
| 1.5 | 2026-07-02 | Alta de D-009 (widget test de captura skippeado, pendiente de entorno Flutter). |
| 1.6 | 2026-07-02 | D-009 cerrado y D-007 mitigado: SDK de Flutter instalado y operativo localmente; widget tests de captura estabilizados (fix del timer de cierre del stream de Drift al disponer el árbol) y reactivados; suite móvil 16/16 en verde. |
