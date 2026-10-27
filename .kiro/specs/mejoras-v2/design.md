# mejoras-v2 — diseño de las 8 mejoras (2026-10-27)

> Spec ligero (design-first) de las 8 mejoras que el founder aprobó el
> 2026-10-27. Cada sección es un PR independiente, apilado sobre el anterior, y
> los PRs se mergean en orden. Las decisiones estructurales tienen su ADR. Este
> documento fija contratos y criterios de aceptación; el detalle de cada línea
> vive en el código y en sus tests.

| PR | Rama | Mejora | Deuda que cierra |
|----|------|--------|------------------|
| A | `fix/hoy-briefing-detalles` | 2 · Briefing visible en Hoy + detalles | D-015, D-016, sesión que caduca, respuestas JSON en Conversar |
| B | `feat/hora-y-moneda` | 4 · Zona horaria y moneda por usuario | D-013, D-014 (moneda) |
| C | `feat/notas-de-voz` | 1 · Notas por voz ([ADR-021](../../../docs/02-architecture/adr/ADR-021-voice-transcribe-and-discard.md)) | voz pendiente desde F1 |
| D | `feat/feedback-correcciones` | 3 · 👍/👎 y corregir lo extraído | FR-2.4, FR-3.5 |
| E | `feat/finanzas-ia` | 6 · Gastos detectados por la IA + pantalla Finanzas | D-014 (resto) |
| F | `feat/conversar-grafo-streaming` | 7 · RAG con grafo + respuesta en vivo | F3 pendiente |
| G | `feat/cuenta-privacidad` | 8 · Consentimiento IA, exportar, borrar cuenta | F4 parcial |
| — | (en cada PR) | 5 · Tests de lo nuevo | D-012 |

Reglas comunes:
- Todo bajo RLS (`withUser` / `rls_tx`).
- Respuestas en `snake_case`.
- Ningún cambio en el prompt v8 ni en el gold (gate ADR-018 intacto).
- Cada PR deja CI verde y añade tests: unitarios, de controlador y, si toca
  datos, integración RLS contra Postgres real.

---

## A. Briefing en Hoy + detalles

**API**
- `GET /v1/briefing` (solo campos aditivos):
  - `task_total` pasa a contar solo las **pendientes**.
  - `tasks[]` son las 5 pendientes más importantes (mismo orden que
    `/v1/tasks`), con `priority` y `due_at`.
  - Nuevos `overdue_count` y `due_today_count`.
  - Nuevo `people[]`: personas con tareas pendientes asignadas, mediante
    aristas `assigned_to`, agrupadas por nombre normalizado
    (`{name, pending_count}`).
- `PATCH /v1/tasks/:id`: `title` no puede quedar vacío.
- Las entradas aceptan `snake_case` (`due_at`, `target_date`). `dueAt` y
  `targetDate` siguen aceptándose como alias deprecados durante una versión.
- `DELETE /v1/tasks/:id` hace soft delete (devuelve 204).
- Metas: `done` se **deriva** de `progress >= 100`, así que bajar el progreso
  revierte la meta.
- Hábitos semanales: la racha cuenta **semanas** consecutivas (semana ISO) con
  al menos un check y la respuesta añade `streak_unit: day|week`.

**IA**
- Bug: el RAG usaba `complete()` en modo JSON. Se añade
  `AIProvider.complete_text()` (texto libre, temperatura 0) y el RAG lo usa.
  Una respuesta que llegue con forma JSON se desenvuelve de forma defensiva.

**App**
- Un único cliente autenticado (`MindosApi`) con **renovación automática del
  token**: ante un 401 hace un único refresh y reintenta; si el refresh falla,
  cierra la sesión. `GraphApiClient` se funde en él.
- Hoy:
  - El saludo depende de la hora e incluye el nombre.
  - La tarjeta de briefing ("mindOS te habla primero") muestra pendientes,
    vencidas, personas y próximo evento.
  - La tarjeta "Proyectos" pasa a llamarse **"Metas"**.
  - El focus score solo cuenta las tareas hechas **hoy**.
- Listas del grafo con "Cargar más" (`next_cursor`).
- Memoria muestra las capturas del **servidor** (`GET /v1/captures`), no solo
  las locales, de modo que un dispositivo nuevo también ve su historia.
- Se elimina el código muerto (`BriefingCard`, el comentario obsoleto del
  router). `AppTheme.light()` se conserva como respaldo documentado.

## B. Zona horaria y moneda por usuario

- **Migración:** `users.timezone TEXT NOT NULL DEFAULT 'UTC'` y
  `users.currency TEXT NULL` (null significa "sin elegir"; la moneda efectiva es
  USD).
- **API:**
  - `GET /v1/me` → `{id, email, timezone, currency, created_at}`.
  - `PATCH /v1/me {timezone?, currency?}` valida la zona contra la base IANA de
    `Intl` y la moneda contra ISO-4217 (`Intl.supportedValuesOf('currency')`).
- **Utilidad pura `common/time/tz.ts`:**
  - `localDateKey(instant, tz)`;
  - `startOfLocalDay(instant, tz)`, que respeta los cambios de horario (DST);
  - `isoWeekKey(dateKey)`.
- **Cálculos en hora local del usuario:** briefing, finanzas (cubos diarios),
  check-in y rachas de hábitos.
- **Finanzas:**
  - El resumen suma solo los gastos en la moneda del usuario; las demás monedas
    se informan aparte en `other_currencies[]`, sin convertir.
  - La consulta usa `orderBy` explícito.
  - Nuevo campo `by_category[]` de la semana.
- **App:**
  - Al iniciar sesión envía la zona del dispositivo (`flutter_timezone`).
  - Si la moneda es null, propone la del locale del dispositivo
    (es_MX→MXN, pt_BR→BRL…).
  - Formatea los importes con `intl`.

## C. Notas por voz — ver ADR-021

- **Flujo:** la app graba (`record`: opus/webm en web, AAC/m4a en móvil) → guarda
  los bytes en el outbox de Drift (schema v2: `audio_data` BLOB, `audio_mime`,
  `audio_duration_ms`) → `SyncService` →
  `POST /v1/captures/voice?client_id=&occurred_at=&duration_ms=`, con el cuerpo
  binario (`audio/*`, ≤ 10 MB) e `Idempotency-Key`.
- **API:**
  1. Idempotencia por sha256 del audio.
  2. Llama a la IA `POST /internal/transcribe` (cuerpo binario + secreto
     interno).
  3. Si el texto sale vacío, devuelve 422 `empty_transcript`.
  4. Crea la captura (`origin=voice`, `body` = transcripción,
     `attributes.transcription{model,language,duration_s}`) y registra
     `llm_usage` en la misma transacción RLS.
  5. Encola y responde 202 con `content` (la transcripción).
- **IA:** `transcribe()` en el proveedor OpenAI-compatible
  (`OPENAI_TRANSCRIBE_MODEL=gpt-transcribe`, pistas de idioma es/pt/en). En Groq
  usa `whisper-large-v3-turbo`.
- **El audio no se guarda en ningún servidor:** se transcribe y se descarta. El
  outbox local libera los bytes al sincronizar.

## D. Feedback y correcciones

- **Migración:** tabla `feedback(id, user_id, target_type, target_id, useful,
  reason, created_at)` con RLS fail-closed y grants mínimos.
- **API:**
  - `POST /v1/feedback {target_type: capture|query|briefing|node, target_id?, useful, reason?}`.
  - `GET /v1/graph/nodes/:id` → la entidad (agrupada por nombre normalizado
    entre capturas), sus conexiones, las tareas relacionadas y las capturas
    donde aparece.
  - `PATCH /v1/graph/nodes/:id {title}` renombra.
  - `DELETE /v1/graph/nodes/:id` hace soft delete del nodo y de sus aristas. Si
    la captura se reprocesa, el nodo sigue borrado.
  - `PATCH /v1/graph/edges/:id {confirmed}`: `true` → `user_confirmed`;
    `false` → soft delete.
  - Las aristas de `captures/:id/entities` incluyen `id`.
  - `GET /v1/graph/nodes?type=` agrupa por nombre normalizado
    (`{id, title, mentions}`), salvo las tareas. `summary` cuenta entidades
    distintas.
- **App:**
  - "Lo que entendí" con 👍/👎 global y quitar o renombrar cada elemento.
  - Ficha de entidad (`/node/:id`).
  - 👍/👎 en Conversar y en el briefing.

## E. Finanzas con IA

- **IA:** un detector de importes (regex de pistas: $, R$, €, "gasté",
  "paguei", "spent"…) decide si hace falta una **segunda llamada pequeña**
  (`EXPENSE_PROMPT_V1`). Así el prompt v8 y su gate no se tocan.
  - Salida: `{expenses:[{amount, currency?, category, description}]}`.
  - Solo cuentan gastos **ya hechos**; los pagos futuros son tareas.
  - La moneda la fija el símbolo o código; si es ambiguo, la del usuario.
  - Categorías canónicas: food, transport, home, health, leisure, shopping,
    bills, education, other.
  - Se escriben como nodos `note`, `kind=expense`, `origin=ai`, con
    `spent_at` = `occurred_at` o `created_at` de la captura y una arista
    `derived_from`.
- **Eval propio** (`app/eval/expenses_dataset.json`, `--suite expenses`). Está
  fuera del gate ADR-018 y se mide en CI con OpenAI.
- **API:**
  - `GET /v1/finance/expenses` (lista, marca el origen IA o manual).
  - `DELETE /v1/finance/expenses/:id`.
  - El resumen usa `spent_at`.
- **App:** pantalla `/finance` (semana, categorías, lista y alta con selector de
  categoría). La tarjeta de Hoy abre esa pantalla.

## F. Conversar con grafo + streaming

- **Recuperación:**
  1. Las top-k capturas por vector.
  2. Entidades del usuario cuyo nombre aparece en la pregunta.
  3. Vecinos a un salto de esas entidades: tareas con su estado y fecha,
     eventos, proyectos y las capturas de origen.
  4. Si la pregunta es sobre pendientes, se añaden las tareas abiertas.
- **Prompt:** NOTAS `[n]` + HECHOS DEL GRAFO, cada uno con la nota `[n]` de la
  que sale.
- **Streaming:**
  - IA: `POST /internal/query/stream` (SSE con los eventos `sources`, `token`,
    `done` y `error`).
  - API: `POST /v1/query/stream` reenvía el SSE.
  - App: lee el SSE (`fetch_client` en web) y pinta los tokens a medida que
    llegan.
- `POST /v1/query` (JSON) se mantiene y añade `entities[]`.

## G. Cuenta y privacidad

- **Migración:** `users.ai_consent_at TIMESTAMPTZ NULL` y `GRANT DELETE ON users`
  al rol de la app (necesario para borrar la cuenta; el borrado arrastra los
  datos por cascada de claves foráneas).
- **API:**
  - `POST /v1/me/consent`.
  - Crear capturas (texto y voz) y consultar exigen consentimiento
    (403 `ai_consent_required`). Para la app, ese 403 es transitorio y no
    descarta el outbox.
  - `GET /v1/account/export` devuelve un JSON con todo excepto los embeddings.
  - `DELETE /v1/account {password}` verifica la contraseña con bcrypt y borra
    en cascada.
- **App:**
  - Pantalla de consentimiento antes de usar la app.
  - Pantalla Cuenta (`/account`, desde el avatar de Hoy): zona, moneda,
    exportar (descarga en web), borrar cuenta (con contraseña) y cerrar sesión.

## Criterios de aceptación globales
- CI verde en las tres apps en cada PR.
- Integración RLS en verde contra Postgres 16 + pgvector real
  (`RUN_INTEGRATION=1`).
- Gate de comprensión intacto (prompt v8 sin cambios). El eval de gastos se
  documenta aparte.
- 009, 012 y #04 actualizados al cerrar.
