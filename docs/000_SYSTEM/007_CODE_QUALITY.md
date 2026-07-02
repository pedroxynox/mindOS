# 007 — Code Quality

| Metadato | Valor |
|----------|-------|
| Versión | 1.0 |
| Estado | 🟢 Vigente |
| Ámbito | Estándares ejecutables por lenguaje (los reglamentos) |
| Depende de | [002](./002_ENGINEERING_CONSTITUTION.md), [006](./006_REVIEW_PROCESS.md); #05 |
| Última actualización | 2026-07-02 |

> **Relación con [002](./002_ENGINEERING_CONSTITUTION.md):** la Constitución define los **principios** (el porqué inmutable). Este documento define su **aplicación concreta** (el cómo, ejecutable y verificable en CI). Si un principio y una regla chocan, gana el principio y se corrige la regla.

## 1. Reglas transversales
- **Manejo de errores explícito:** nada de errores silenciados; el fallo degrada sin perder la captura.
- **Complejidad:** complejidad ciclomática objetivo ≤ 10 por función; funciones ≤ ~50 líneas salvo justificación.
- **Naming:** nombres que comunican intención; sin abreviaturas crípticas.
- **Sin código muerto ni comentarios TODO sin ticket/registro en [012](./012_RISK_AND_DEBT_REGISTER.md).**
- **Cobertura:** umbral mínimo **80 %** en lógica de dominio; el camino de captura y el pipeline de comprensión aspiran a más.

## 2. TypeScript / NestJS (`apps/api`)
- **Lint/format:** ESLint + Prettier; el build falla ante warnings de lint.
- **`any` prohibido** (`@typescript-eslint/no-explicit-any` en error). Usar tipos precisos o genéricos.
- **DTOs validados** con `class-validator` + `class-transformer`; toda entrada externa se valida en el borde.
- **Fronteras de módulos:** un bounded context no importa internals de otro; se comunican por interfaces/servicios públicos.
- **Async:** `Promise` correctamente esperadas (`no-floating-promises`).

## 3. Python / FastAPI (`apps/ai`)
- **Lint/format:** `ruff` (incluye ordenación de imports y formato).
- **Tipado:** `mypy` en modo estricto; type hints obligatorios en toda función pública.
- **Validación:** `pydantic` para modelos de entrada/salida y configuración.
- **Fronteras:** todo acceso a LLM tras la capa `AIProvider`; ninguna llamada directa a un SDK de proveedor fuera de esa capa.

## 4. Dart / Flutter (`apps/mobile`)
- **Análisis:** `analysis_options.yaml` con lints estrictos; el análisis debe pasar sin issues.
- **Estado:** patrones **Riverpod** (providers tipados, sin estado global mutable ad-hoc).
- **Navegación:** rutas centralizadas con GoRouter.
- **Capas:** UI → providers → repositorios; la UI no llama red directamente.

## 5. Cuándo usar Property-Based Testing (PBT)
- **Sí:** lógica central e invariantes — idempotencia de captura, no-pérdida de la captura cruda, aislamiento por usuario, transformaciones del grafo, resolución temporal.
- **No (basta ejemplo):** wiring trivial, mapeos 1:1, controladores sin lógica.
- Las propiedades se nombran/numeran y se enlazan al requisito que validan (`**Validates: Requirements X.Y**`).

## 6. Antipatrones prohibidos
- Mocks que falsean la lógica solo para que el test pase.
- `any`/`# type: ignore`/`dynamic` para silenciar el checker.
- Lógica de negocio en controladores o widgets.
- Llamadas a LLM fuera de `AIProvider`.
- Deuda técnica sin registrar en [012](./012_RISK_AND_DEBT_REGISTER.md).

## 7. Cadencia de refactor
El refactor es continuo (regla del boy scout): se deja el módulo mejor de como se encontró. El refactor estructural grande se planifica como tarea propia con su spec.

## 8. Gates de CI
Estas reglas son **ejecutables**: se aplican en los 3 jobs de CI (api/ai/mobile) descritos en #05/#06 — lint + tipos + tests + build. Un gate rojo bloquea el merge ([006](./006_REVIEW_PROCESS.md) §2). Deuda vigente relacionada: los lockfiles deben commitearse y CI migrar a instalación reproducible (`npm ci`) — ver [D-001](./012_RISK_AND_DEBT_REGISTER.md).

## Historial de versiones
| Versión | Fecha | Cambios |
|---------|-------|---------|
| 1.0 | 2026-07-02 | Estándares ejecutables iniciales para TS/NestJS, Python/FastAPI y Dart/Flutter. |
