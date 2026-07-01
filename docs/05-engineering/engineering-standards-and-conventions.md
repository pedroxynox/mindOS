# mindOS — Engineering Standards & Conventions

> **Documento #05 de la cadena documental.**
> Deriva del [TAD (#02)](../02-architecture/technical-architecture.md).
> Define **cómo se escribe, organiza, revisa, prueba y entrega el código.**
> Es el último documento antes de poder escribir código de producción con
> estándares profesionales.

| Metadato | Valor |
|----------|-------|
| Versión | 0.1 (borrador para revisión) |
| Estado | 🟢 Aprobado |
| Autor | CTO |
| Depende de | #02 TAD |
| Última actualización | 2026-07-01 |

---

## 0. Propósito

Un producto de clase mundial se construye con disciplina de ingeniería
consistente. Este documento define los estándares no negociables que todo el
código de mindOS debe cumplir, de modo que:

- Cualquier ingeniero pueda leer y entender cualquier parte del código.
- La calidad no dependa de quién escribió el código.
- Las decisiones se automaticen (linters, CI) en lugar de discutirse en cada PR.

> **Principio rector:** las convenciones se **automatizan**, no se memorizan. Si
> una regla puede imponerla una herramienta, la impone una herramienta.

---

## 1. Estructura del repositorio (monorepo)

### ADR-E1 — Monorepo
- **Decisión:** un único repositorio contiene las tres apps y la documentación.
- **Estado:** 🟢 Aprobado.
- **Por qué:** con un equipo pequeño, el monorepo simplifica cambios atómicos
  entre las apps, centraliza CI y facilita compartir contratos.

> ⚠️ **Actualizado por [ADR-010](../02-architecture/adr/ADR-010-final-stack-and-two-backends.md):**
> la estructura refleja el stack definitivo (Flutter + NestJS + Python IA), no
> el `backend/frontend` original.

```
mindOS/
├── docs/                  # Cadena documental (#00–#08) + ADRs
├── apps/
│   ├── mobile/            # Flutter (Riverpod, GoRouter, Drift, Material 3)
│   │   ├── lib/
│   │   └── pubspec.yaml
│   ├── api/               # NestJS + Prisma (negocio, grafo, auth, WebSocket)
│   │   ├── src/
│   │   │   ├── identity/        # contextos acotados (#02 §4)
│   │   │   ├── capture/
│   │   │   ├── graph/
│   │   │   ├── realtime/
│   │   │   └── health/
│   │   ├── prisma/
│   │   └── package.json
│   └── ai/                # Python + FastAPI (comprensión, embeddings, RAG)
│       ├── app/
│       │   ├── understanding/
│       │   ├── query/
│       │   └── providers/       # capa AIProvider (ADR-09)
│       └── pyproject.toml
├── infra/                 # docker-compose, Nginx, IaC (#06)
├── .github/workflows/     # CI/CD (detalle en #06)
└── README.md
```

> Cada contexto acotado es una **frontera de módulo**: no se importa lógica de
> dominio de un contexto a otro directamente. La frontera entre `api` (NestJS) y
> `ai` (Python) está definida en el ADR-010.

---

## 2. Estándares de lenguaje

### 2.1 Python (backend)

| Aspecto | Estándar |
|---------|----------|
| Versión | Python 3.12+ |
| Formateo + lint | **Ruff** (formateo y linting unificados). Sin debate de estilo. |
| Tipado | **Type hints obligatorios** en toda función pública. Verificado con **mypy** (o pyright) en modo estricto. |
| Validación de datos | **Pydantic** para todo modelo de entrada/salida y configuración. |
| Docstrings | Obligatorios en módulos y funciones públicas (estilo Google). |
| Gestión de dependencias | **uv** (o Poetry) con lockfile versionado. |
| Imports | Ordenados por Ruff; sin imports sin usar. |

### 2.2 TypeScript (frontend)

| Aspecto | Estándar |
|---------|----------|
| Modo | `strict: true` en `tsconfig`. Prohibido `any` implícito. |
| Formateo | **Prettier** (config única compartida). |
| Lint | **ESLint** con reglas de TypeScript + React + accesibilidad (a11y). |
| Gestión de dependencias | **pnpm** con lockfile versionado. |
| Componentes | Funcionales + hooks. Sin componentes de clase. |
| Tipos de API | Generados o compartidos desde el contrato de API (#04) para evitar drift. |

> **Regla anti-drift:** los tipos del frontend que representan respuestas de la
> API se derivan del contrato (#04), no se escriben a mano por duplicado.

---

## 3. Convenciones de nomenclatura

| Elemento | Convención | Ejemplo |
|----------|-----------|---------|
| Módulos/paquetes Python | `snake_case` | `understanding/entity_extractor.py` |
| Clases | `PascalCase` | `KnowledgeGraphService` |
| Funciones/variables Python | `snake_case` | `extract_entities()` |
| Constantes | `UPPER_SNAKE_CASE` | `MAX_CAPTURE_LENGTH` |
| Componentes React | `PascalCase` | `DailyBriefing.tsx` |
| Hooks | `camelCase` con prefijo `use` | `useCaptureDraft()` |
| Campos JSON de API | `snake_case` | `created_at` (coherente con #04) |
| Ramas Git | `tipo/descripcion-corta` | `feat/capture-endpoint` |

---

## 4. Flujo de trabajo Git

### 4.1 Ramas
- `main` es siempre desplegable. Nadie hace push directo a `main`.
- Todo cambio pasa por una rama y un Pull Request.
- Nomenclatura: `feat/`, `fix/`, `refactor/`, `docs/`, `chore/`, `test/`.

### 4.2 Commits — Conventional Commits
Formato obligatorio (habilita changelogs y versionado automáticos):
```
tipo(alcance): descripción breve en imperativo

[cuerpo opcional]
```
Ejemplos: `feat(capture): add idempotency key handling`,
`fix(graph): prevent duplicate person nodes on entity resolution`.

Tipos: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `perf`, `build`, `ci`.

### 4.3 Pull Requests
- **Pequeños y enfocados.** Un PR = un cambio coherente. PRs gigantes se
  rechazan.
- Descripción con: qué cambia, por qué, cómo se probó, y riesgos.
- Debe pasar **todo el CI** (lint, tipos, tests) antes de poder mergearse.
- Requiere al menos **una aprobación** de revisión (cuando haya equipo).
- Se mergea con **squash** para mantener un historial limpio en `main`.

---

## 5. Estándares de revisión de código

El revisor evalúa, en este orden de prioridad:

1. **Correctitud:** ¿hace lo que dice? ¿maneja errores y casos límite?
2. **Seguridad y privacidad:** ¿filtra por `user_id`? ¿expone datos sensibles?
   ¿envía al LLM más de lo necesario (ADR-09)?
3. **Fronteras de contexto:** ¿respeta el aislamiento entre contextos acotados?
4. **Legibilidad:** ¿se entiende sin explicación verbal?
5. **Pruebas:** ¿el cambio está cubierto?
6. **Estilo:** lo verifica la herramienta; el revisor no pierde tiempo en esto.

> **Regla de tono:** se critica el código, nunca a la persona. Los comentarios
> proponen, no imponen ("¿qué te parece si...?"). El objetivo es el mejor
> código, no ganar la discusión.

---

## 6. Filosofía y estrategia de pruebas

> **Postura:** pruebas pragmáticas, no dogma. Probamos lo que aporta confianza,
> no perseguimos un número de cobertura por vanidad. **No** exigimos TDD
> estricto, pero **sí** exigimos que la lógica de dominio crítica esté probada.

| Tipo | Qué cubre | Prioridad |
|------|-----------|-----------|
| **Unitarias** | Lógica de dominio pura (resolución de entidades, priorización del briefing, parsing temporal). | Alta |
| **Integración** | Endpoints de API + BD (con Postgres real en contenedor), contratos del #04. | Alta |
| **De contrato** | Que la API cumple el esquema del #04 (evita drift con el frontend). | Media |
| **E2E** | Flujos críticos: captura → comprensión → briefing → consulta. | Media (los bucles clave del PRD) |
| **De IA/evaluación** | Calidad de extracción y de respuestas (eval sets), no aserciones exactas. | Especial (ver §6.1) |

### 6.1 Pruebas de componentes de IA
La IA no es determinista; no se prueba con `assertEquals`. Se evalúa con:
- **Conjuntos de evaluación (golden sets):** capturas de ejemplo con las
  entidades/conexiones esperadas; se mide precisión/recall a lo largo del tiempo.
- **Aserciones de propiedades:** ("la respuesta cita al menos una fuente del
  grafo", "no inventa personas inexistentes") en lugar de igualdad exacta.
- **Regresión:** el eval set corre en CI para detectar degradación al cambiar de
  modelo o prompt.

> Esto conecta con el criterio de aceptación del PRD (§9): el umbral de calidad
> de extracción se mide con estos eval sets.

---

## 7. Manejo de errores y logging

- **Errores:** nunca se silencian. Se manejan explícitamente o se propagan con
  contexto. La envoltura de error de la API (#04 §3) es la única forma de
  exponer errores al cliente.
- **La captura cruda nunca se pierde por un error del pipeline** (ADR-02): si la
  comprensión falla, se reintenta; la `Capture` ya está persistida.
- **Logging estructurado (JSON)** con `request_id`/`user_id` (sin PII sensible en
  logs). Niveles: `debug`, `info`, `warning`, `error`. Detalle de observabilidad
  en #06.
- **Nunca** se registran contenidos sensibles del usuario ni secretos en logs.

---

## 8. Estándares de seguridad en el código

- Todo acceso a datos filtra por `user_id`; jamás se confía solo en el filtro de
  la aplicación (RLS como refuerzo, #03).
- Secretos y claves **solo** por variables de entorno / gestor de secretos.
  Nunca en el repositorio. CI bloquea commits con secretos detectados.
- Entrada del usuario siempre validada (Pydantic / esquemas).
- Dependencias escaneadas por vulnerabilidades en CI.
- Principio de mínima exposición de datos hacia el LLM externo (ADR-09).

---

## 9. Definición de "Hecho" (Definition of Done)

Un cambio está "hecho" cuando:
1. Cumple el requisito y sus criterios de aceptación.
2. Pasa lint, chequeo de tipos y todas las pruebas en CI.
3. Tiene pruebas para la lógica nueva relevante.
4. Está revisado y aprobado por al menos otra persona (cuando haya equipo).
5. No introduce secretos, PII en logs ni deuda no documentada.
6. La documentación afectada (contratos, ADRs) está actualizada.

---

## 10. Documentación en el código

- **Docstrings** en toda función/módulo público.
- **ADRs** para toda decisión arquitectónica significativa: se registran en la
  cadena documental (como los ADR-01..09 del #02), no en la cabeza de alguien.
- **READMEs** por módulo cuando la complejidad lo amerite.
- Comentarios que explican el **porqué**, no el **qué** (el qué lo dice el
  código).

---

## 11. Preguntas abiertas (para #06 e implementación)

1. Configuración concreta de CI/CD y gates → **#06**.
2. Herramienta exacta de gestión de dependencias Python (uv vs. Poetry) → se
   fija al iniciar el scaffolding del backend.
3. Estrategia de generación de tipos de API para el frontend (OpenAPI codegen)
   → decisión de implementación al construir el contrato #04.
4. Política de versionado semántico y releases → **#06 / release management**.

---

## Historial de versiones

| Versión | Fecha | Autor | Cambios |
|---------|-------|-------|---------|
| 0.1 | 2026-07-01 | CTO | Borrador inicial. Estructura de monorepo, estándares de Python y TypeScript, nomenclatura, flujo Git (Conventional Commits + PRs), estándares de revisión, filosofía de pruebas (incluida evaluación de IA), manejo de errores/logging, seguridad en el código y Definition of Done. |
