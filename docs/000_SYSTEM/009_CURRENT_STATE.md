# 009 — Current State (estado vivo del proyecto)

> 🔴 DOCUMENTO OBLIGATORIO. Se actualiza al CIERRE de CADA sesión (ritual en [008](./008_AI_COLLABORATION_PROTOCOL.md)). Es una FOTO que se sobreescribe. La historia cronológica y el detalle de riesgos y deuda viven en [012](./012_RISK_AND_DEBT_REGISTER.md).

| Metadato | Valor |
|----------|-------|
| Última actualización | 2026-10-27 |
| Fase actual | F1 completa. F2 (Comprensión) en producción. **F3 (Recuperación de valor) construida en su mayor parte:** lectura del grafo y "Lo que entendí", Daily Briefing (API), "Conversar" (RAG con citas, sin streaming). **Adelantados fuera de plan:** Tareas con prioridad, Crecimiento (metas, hábitos, reflexión) y Finanzas básico ([ADR-020](../02-architecture/adr/ADR-020-life-modules-as-note-nodes.md)). UI rediseñada (oscura, "presence"). Faltan de F3 el feedback, el RAG con grafo y el streaming. Faltan también la voz y F4 entera. |
| Avance estimado del MVP (F0–F5) | ~62 % (F0 ~90 %, F1 100 %, F2 100 %, F3 ~70 %, F4 ~10 %, F5 0 %) |

## 1. Resumen ejecutivo
mindOS está **vivo en internet** (`https://mindos-web.onrender.com`) y ya **devuelve valor**, no solo entiende. El usuario:
- escribe una captura y ve en segundos lo que la IA entendió (personas, tareas, proyectos, eventos, temas y conexiones);
- explora su memoria;
- le pregunta cosas a mindOS y recibe respuestas citando sus notas;
- gestiona tareas, metas, hábitos, reflexiones y gastos desde el dashboard "Hoy".

Lo que se construyó entre el 2026-07-10 y hoy entró con **9 commits directos a `main`, sin PR**. El CI de la IA quedó **en rojo 7 commits** sin que nadie lo viera (lint). Se arregló en PR #69 (R-008). La documentación tampoco se actualizó (D-017). Esta sesión la pone al día.

Calidad: 81 tests unitarios y 8 de integración en la API, 109 en la IA y 15 en Flutter. CI verde en `main` (`e4feb7b`). Lo nuevo tiene poca cobertura (D-012).

## 2. Qué existe hoy (verificado en `main` `e4feb7b`)
**API NestJS (`/v1`, JWT salvo health y auth):**
- `auth/*` (register, login, refresh, logout).
- `captures` (POST idempotente que devuelve 202, presign de audio, GET y listado).
- `graph/summary`, `graph/nodes?type=` y `graph/captures/:id/entities`.
- `briefing`.
- `query` (proxy RAG hacia la IA).
- `tasks` (GET, POST y PATCH con prioridad, `done`, fecha y área).
- `growth/goals|habits|habits/:id/check|reflections`.
- `finance/summary|expenses`.
- Detalle de contratos: [#04 §5.0](../04-api/api-design-specification.md).

**IA FastAPI:**
- `/health`.
- `/internal/query`: RAG vectorial sobre las capturas procesadas (top 6), responde citando `[n]` y está protegido por `QUERY_INTERNAL_SECRET`.
- Worker BullMQ con prompt **v8** (`gpt-5.4-mini` + `text-embedding-3-small`).
- Examen F2: 45 casos, gate superado (F1 0.890, taskP 1.000, alucinación 0.074, coste $0.0023).

**App Flutter (web + móvil, tema oscuro forzado, fuente Inter):**

| Pantalla | Qué hace |
|---|---|
| **Hoy** | Saludo, tarjeta de enfoque con *focus score*, resumen de Finanzas (con registro rápido de gasto), Hábitos, "Proyectos" (en realidad metas, D-015), Recordatorios y Recomendación |
| **Conversar** | Preguntas con la esfera "presence" y "En qué me baso" |
| **Memoria** | Conteos del grafo y línea de tiempo |
| **Capturar** | Solo texto |
| **Lo que entendí** | Entidades y conexiones de una captura |
| **Listas por tipo** | Nodos del grafo de un tipo |
| **Tareas** | Marcar hechas, cambiar prioridad y crear |
| **Crecimiento** | Pestañas Metas, Hábitos y Reflexión |

Finanzas no tiene pantalla propia, solo la tarjeta de Hoy. El **Daily Briefing de la API no se muestra en ninguna pantalla** (D-016).

**Infra:** Render (`mindos-api`, `mindos-ai` con worker, `mindos-web` estático, `mindos-redis`) y Neon (Postgres + pgvector), todo en plan **gratis**. API e IA se duermen; la web no.

**Kiro:** `.kiro/steering/mindos-context.md`, que se carga siempre, y 40 skills en `.kiro/skills/` (PR #69).

## 3. Cómo funciona el sistema (mapa mental para retomar)
`Flutter` guarda la captura (offline-first) → `POST /v1/captures` (idempotente) → cola BullMQ en Redis → **worker Python** → `gpt-5.4-mini` extrae entidades y tareas → embedding → escritura en el grafo `nodes`/`edges` bajo RLS → `processed`.

**Lectura:**
- La API lee el grafo directamente: graph, briefing, tasks, growth y finance.
- Para preguntar: API → `POST /internal/query` en la IA, que hace búsqueda vectorial con RLS y responde con citas.

**Datos:** un único grafo por usuario. Las tareas son nodos `task`. Metas, hábitos, reflexiones y gastos son nodos `note` con `attributes.kind` ([ADR-020](../02-architecture/adr/ADR-020-life-modules-as-note-nodes.md)).

## 4. Últimas decisiones
- **Adelantar Tareas, Crecimiento y Finanzas** sobre el grafo, sin tablas nuevas. Se tomó en código el 2026-07-10 y se registra hoy como **ADR-020 retroactivo**, sujeto a veto.
- **"Conversar" como RAG solo vectorial y sin streaming.** Suficiente para el MVP. La travesía de grafo y el SSE quedan pendientes en F3.
- **UI oscura "presence"** como identidad visual. El tema claro existe pero no se usa.
- **24/7 (plan starter, ~$14/mes) diferido** por el founder (2026-10-27): se sigue en gratis.
- **Comunicación con el founder:** español, sin tecnicismos y **súper resumido**.
- Siguen vigentes ADR-012 (stack), ADR-018/019 (gate y puente de cola) y la norma "aprovisionar antes de degradar".

## 5. Próxima acción inmediata
El founder quiere **seguir desarrollando la app**. Candidatos, en orden de recomendación:
1. 🟢 **Voz** (dictar capturas). Es lo que más falta en la captura y la tubería ya está preparada: subida de audio, `audio_ref` y outbox. Falta `AIProvider.transcribe`, el `audio_loader` del pipeline, grabar en la app y activar S3 (R2 o MinIO) en Render.
2. 🟢 **Mostrar el Daily Briefing** en Hoy, que ya existe en la API pero no se ve (D-016). Arreglar de paso los defectos de D-015.
3. 🟠 **Feedback 👍/👎** (`POST /v1/feedback`, FR-3.5): North Star y corrección de lo extraído.
4. 🟠 **Zona horaria y moneda por usuario** (D-013, D-014), clave para BR/LatAm.
5. 🟠 **Tests de lo nuevo** (D-012) antes de crecer más.
6. ⚪ **Finanzas con IA** (de "gasté $50 en el súper" a un gasto) y **RAG con grafo y streaming**.
7. ⚪ **F4:** exportar y borrar cuenta, consentimiento de IA, observabilidad (Sentry, D-005).

## 6. Bloqueadores y avisos importantes
- **No hay bloqueadores.**
- **Modo gratis:** API e IA se duermen a los ~15 min. Despiertan en 30-60 s y el worker solo procesa la cola cuando algo lo despierta. Pasar a 24/7 queda diferido por decisión del founder.
- **Proceso:** todo cambio entra **por PR y con CI verde** (R-008). Render despliega desde `main`.
- **Observabilidad:** los logs INFO de `mindos-ai` no se ven (solo ERROR). Mejora pendiente.

## 7. Riesgos vivos (detalle en [012](./012_RISK_AND_DEBT_REGISTER.md))
- **R-008 (nuevo, 🟡):** integración sin red de seguridad (commits directos y CI en rojo). Mitigación pendiente: *branch protection*.
- **R-001 (🟢 resuelta para el gate):** residual no gated, connections F1 0.187.
- R-004 y R-005 pasan a 🟢 mitigados. R-002 y R-003 mitigados. R-006 y R-007 cerrados.

## 8. Deuda técnica top (detalle en [012](./012_RISK_AND_DEBT_REGISTER.md))
- **D-012:** tests insuficientes en todo lo construido después de F2.
- **D-013:** "hoy" calculado en UTC (rachas y semanas descuadradas en LatAm).
- **D-014:** moneda de Finanzas (fila arbitraria, mezcla de monedas, USD forzado).
- **D-015:** defectos menores de lógica y UX (saludo, "Proyectos" que son metas, focus score, hábitos semanales, paginación…).
- **D-016:** briefing sin pantalla, clientes HTTP duplicados, código muerto.
- Siguen abiertos D-005 (Sentry y secretos) y D-006 (barridos O(usuarios)). En progreso: D-008 (embeddings; ya en producción con OpenAI 1536) y D-010 (prompt v8 estable).

## 9. Salud de la arquitectura
Sigue sana:
- Dos backends bien separados.
- RLS en todo acceso a datos, incluidos los módulos nuevos.
- Puertos `AIProvider` y `GraphStore` intactos.

Riesgos de forma:
- Los módulos adelantados usan `note` + `attributes.kind`: rápido, pero sin integridad en la base de datos (ver criterios de salida en ADR-020).
- La app tiene dos clientes HTTP.
- La documentación había derivado 3,5 meses; quedó corregida hoy.

## 10. Cambios recientes (desde la v1.16)
| Commit | Qué entró |
|--------|-----------|
| `b368748` | Lectura del grafo + "Lo que entendí" + listas por tipo (Paso 1) |
| `fb1ff5c` | `GET /v1/briefing` + tarjeta (Paso 2; la tarjeta ya no se monta) |
| `267300d` | "Conversar" / RAG (Paso 3) |
| `a97846d` | Tareas con prioridad + Crecimiento |
| `cf3d6b3`, `1e1ab83`, `8b2adf7` | Rediseño visual (morado → oscuro "presence", esfera, Memoria, Inter, animaciones) |
| `14de5ab` | Dashboard "Hoy" + Finanzas |
| `09254b9` | Auditoría de código ([013](./013_CODEBASE_AUDIT.md)) |
| PR #69 (`e4feb7b`) | Steering y skills de Kiro + arreglo del CI de la IA |

## 11. Preguntas abiertas (para el founder)
- ¿**Branch protection** en `main` (PR y CI verde obligatorios)? Recomendado 🟢.
- ¿Moneda por defecto (BRL, MXN, USD…) y zona horaria por usuario?
- ¿La IA debe crear gastos y tareas con fecha desde las capturas, o basta con el registro manual?
- ¿Cuándo pasar a 24/7?
- ¿Publicar la app móvil en las tiendas o seguir solo en web?

## 12. Acciones recomendadas (priorizadas)
1. Mergear el PR de esta puesta al día.
2. Activar *branch protection* en `main` (R-008).
3. **Voz** (§5.1).
4. Mostrar el briefing en Hoy + correcciones de D-015, en un PR pequeño con tests.
5. Feedback 👍/👎.
6. Zona horaria y moneda (D-013, D-014).
7. Refrescar 009 y 012 al cierre de cada sesión (ritual de [008](./008_AI_COLLABORATION_PROTOCOL.md)).

## 13. PRs de esta etapa
- **#64–#68** (cerrados): Paso 1, Paso 2, Paso 3, Tareas+Crecimiento y fix de build web. El contenido entró por commits directos a `main`.
- **#69** (mergeado): `.kiro` (steering + 40 skills) + fix de lint de la IA (CI verde).
- **Este PR:** puesta al día documental (009, 012, ESTADO, README, #01, #02, #03, #04, #08, 000, 010, 011, ADR-020, `tasks.md` de F1).

## 14. Nota para la nueva sesión (importante)
- **Hablar en español, sin tecnicismos y SÚPER RESUMIDO** con el founder (CEO no programador). Actuar como **CPTO con pensamiento crítico**.
- **No relajar umbrales ni gold** para "aprobar".
- **Verificar siempre el estado real de `main`** (PRs + `git log`): el founder mergea rápido y a veces hay commits directos.
- **Todo por PR con CI verde.** Comprobar el CI después de cada push.
- Leer `.kiro/steering/mindos-context.md` (mapa del proyecto) y este 009.
- **Mantener el ritual:** actualizar 009 y 012 al cierre, y crear un ADR si hay una decisión estructural.

## Historial de versiones
| Versión | Fecha | Cambios |
|---------|-------|---------|
| 1.0–1.8 | 2026-07-02/03 | Fundación de la gobernanza → F1 completada, validada (R-006) y ADRs consolidados (ver 012 para el detalle cronológico). |
| 1.9 | 2026-07-03 | Foco en F2/R-001: medición estable (Groq, prompt v3/v5), decisión de iterar hacia hallucination ≤0.10, proveedor Gemini; bloqueo por cupos free-tier; PR #40. |
| 1.10 | 2026-07-09 | Gate de F2 ratificado (ADR-018) y motor CONSTRUIDO (PR #45): Groq 0.782/0.930/0.091; motor F2 + migración pgvector/`llm_usage`, 84 tests offline. Alta de R-007; D-008 en progreso. |
| 1.11 | 2026-07-09 | PR #45 mergeado y motor VALIDADO contra infra real → R-007 cerrado (Postgres 18 + pgvector + Redis 6; 5/5 integración; fix `nodes.updated_at`). PR #40 mergeado. 97 offline + 5 integración. |
| 1.12 | 2026-07-09 | Gate SUPERADO por primera vez (OpenAI `gpt-5.4-mini`, F1 0.819/1.000/0.059) → R-001 mitigado; decisión mini vs 5.5. PRs #47/#49/#50. |
| 1.13 | 2026-07-09 | R-001 RESUELTA para el gate: prompt v6→v7→v8; v8 F1 0.890/1.000/0.074 = PASS con margen. PRs #51/#52/#53. |
| 1.14 | 2026-07-09 | **Cierre de sesión (handoff):** arranque del worker cableado (`WORKER_ENABLED`, PR #54); voz decidida (text-first/diferida) y Finanzas anotada V4 (PR #54); despliegue en Render preparado (`render.yaml` + `DEPLOY_RENDER.md`, PR #55) con fixes de Dockerfiles; alta de deuda **D-011** (config de deploy no verificada). Documentación completa del estado y lo que falta (desplegar en Render, empezar gratis). Nota: `render.yaml` en main quedó en `starter`; este PR lo pasa a gratis. Suite 100 offline + 5 integración; ruff/mypy limpios. |
| 1.15 | 2026-07-09 | **🟢 mindOS DESPLEGADO Y VALIDADO END-TO-END EN PRODUCCIÓN (Render + Neon + OpenAI, gratis).** Base de datos en Neon gratis (PR #57); migraciones al arranque vía `docker-entrypoint.sh` (free tier no soporta preDeploy; PRs #58/#59); rol `mindos_app` creado en la Consola de Neon (Neon rechaza contraseñas débiles vía SQL) + reset `DROP SCHEMA public` para limpiar el `P3009`; bloqueo final resuelto = faltaba `OPENAI_API_KEY` en `mindos-ai`. **Prueba real:** registrar usuario → crear captura de texto → `raw`→`processed` en ~5-10 s en la nube (API→Redis→worker→`gpt-5.4-mini`→grafo Neon). D-011 mitigado. Papercut pendiente: subir logging a INFO para ver "worker started"/procesamiento. Siguiente: voz, luego Finanzas (V4), y 24/7 (starter) cuando se quiera. |
| 1.16 | 2026-07-10 | **🟢 APP WEB EN LÍNEA + documentación de estado.** El código Flutter se habilitó para navegador reutilizando UNA sola base de código: conexión Drift condicional (archivo nativo en móvil / WASM `sqlite3.wasm`+`drift_worker.js` en web) y lector de audio condicional; feature **auth** nuevo (cliente `/v1/auth/*`, `TokenStore` con `shared_preferences`, `AuthController` Riverpod, pantallas login/registro con validación), **router con guard** de sesión, **home** (estado de conexión + capturas recientes + logout) y `accessTokenProvider` conectado al token real. Desplegada como **sitio estático en Render** (`mindos-web`, no se duerme; el build clona Flutter y compila con `--dart-define=API_BASE_URL`) y **CORS** configurable habilitado en la API (`CORS_ORIGIN`, PR de infra). `flutter analyze` limpio, **16/16 tests**, `flutter build web` OK; API typecheck OK. Documentado el estado completo para el founder en **`docs/ESTADO_DEL_PROYECTO.md`** y actualizado `DEPLOY_RENDER.md` (4º servicio + paso de apertura de la web). **Hallazgo/decisión de producto:** el cerebro ya entiende pero la **inteligencia no se muestra** → siguiente foco = **F3 (recuperación de valor)**: (1) endpoints de LECTURA del grafo (hoy inexistentes), (2) mostrar en la app lo extraído (personas/tareas/proyectos/eventos/temas + conexiones), (3) Daily Briefing, (4) consulta con citas. Avance MVP ~45%→~52%. |
| 1.17 | 2026-10-27 | **Puesta al día tras F3 y módulos adelantados.**<br>- Recoge lo que entró en `main` desde la v1.16: lectura del grafo, "Lo que entendí", briefing (API), "Conversar"/RAG, Tareas, Crecimiento, Finanzas, rediseño "presence" y auditoría 013.<br>- PR #69: steering y skills de Kiro + CI verde.<br>- Alta de R-008 y D-012…D-017; ADR-020 retroactivo.<br>- 24/7 diferido por el founder; comunicación súper resumida.<br>- MVP ~52 % → ~62 %. Siguiente: voz. |
