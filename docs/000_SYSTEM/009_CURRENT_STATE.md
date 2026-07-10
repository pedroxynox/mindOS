# 009 — Current State (estado vivo del proyecto)

> 🔴 DOCUMENTO OBLIGATORIO. Se actualiza al CIERRE de CADA sesión (ritual en [008](./008_AI_COLLABORATION_PROTOCOL.md)). Es una FOTO que se sobreescribe. La historia cronológica y el detalle de riesgos/deuda viven en [012](./012_RISK_AND_DEBT_REGISTER.md).

| Metadato | Valor |
|----------|-------|
| Última actualización | 2026-07-10 |
| Fase actual | F1 **COMPLETA**. F2 (Comprensión) **RESUELTA y VIVA en producción** (gate superado: F1 0.890 / taskP 1.000 / hall 0.074 / $0.0023, `gpt-5.4-mini`; Render + Neon + OpenAI). **NUEVO (2026-07-10): APP WEB en línea** — el mismo código Flutter compilado para navegador, con **registro, login, sesión persistente, home y captura**, servido como **sitio estático en Render** (`https://mindos-web.onrender.com`, no se duerme) + **CORS** habilitado en la API. **mindOS está VIVO y usable desde el navegador.** **Siguiente foco = F3 (recuperación de valor):** hoy el cerebro entiende pero la inteligencia **no se muestra**; el próximo salto es exponer el grafo (personas/tareas/proyectos/eventos/temas + conexiones) y mostrarlo en la app, luego Daily Briefing y consulta (query). |
| Avance estimado del MVP (F0–F5) | ~52 % |

## 1. Resumen ejecutivo
**F1 (Capture Engine)** está cerrada y verificada contra infra real (R-006): captura offline-first, grafo `nodes`/`edges` con RLS fail-closed, `POST /v1/captures` idempotente, cola BullMQ, reconciliación y janitor; auth endurecida; builds reproducibles.

**F2 (Comprensión)** — el foco de esta sesión — quedó **de-riesgada y lista para encender**:
1. El motor ya estaba construido (PR #45) y validado contra Postgres+pgvector y Redis/BullMQ reales (R-007 cerrado).
2. **Calidad RESUELTA (R-001):** el founder pagó OpenAI y elegimos `gpt-5.4-mini`. Iteración honesta de prompt **v6→v7→v8** (sin tocar gold/umbrales): v6 0.819/hall 0.059 (PASS) → v7 0.870/**0.118** (FAIL solo por alucinación) → **v8 F1 0.890 (P 0.926 / R 0.857) / taskP 1.000 / hall 0.074 / $0.0023 = GATE PASSED con margen**. El recall subió de 0.726 a 0.857 sin disparar la alucinación.
3. **Motor cableado para encenderse:** `main.py` ahora arranca/cierra el worker BullMQ vía *lifespan*, con interruptor `WORKER_ENABLED` (apagado por defecto para no romper health-only ni tests). Un fallo de arranque se loguea pero no tumba `/health`.
4. **Voz DECIDIDA:** text-first ahora; la transcripción de voz se difiere (el pipeline ya preserva la captura de voz con un *seam* seguro).
5. **Finanzas ANOTADA** como función futura (V4) en el roadmap §3.1 — ampliación sobre F2, no ahora.
6. **Despliegue PREPARADO:** `render.yaml` (Key Value/Redis + API + IA+worker en Render; **base de datos en Neon gratis** vía `sync:false`) + `docs/06-infrastructure/DEPLOY_RENDER.md`. Arreglados dos huecos de imagen (worker deps `.[worker]`; Prisma CLI en la imagen de la API para migraciones).

Suite: **100 offline + 5 integración**, `ruff`/`mypy` limpios (Python 3.11).

## 2. Qué existe hoy (verificado, ya en main)
- **F1 end-to-end** (captura offline-first, grafo + RLS fail-closed, `POST /v1/captures` idempotente, cola BullMQ, reconciliación, janitor), **auth endurecida**, **builds reproducibles**, integración **8/8** contra infra real (R-006), **ADRs** 001..019.
- **Motor de comprensión F2** (`apps/ai/app/understanding/`): contrato, `enrichment` puro, puerto `GraphStore`+`InMemory`+`PgGraphStore`, `rls`, `cost_meter`, `pipeline`, `worker` BullMQ. Migración pgvector/`llm_usage`. Validado contra infra real (R-007).
- **Extractor `extract.py` en prompt v8** (R-001 superado); capa **`AIProvider`** intercambiable (`fake`/`openai`/`groq`/`gemini`) con **temperatura adaptativa** (envía `temperature=0`; si el modelo lo rechaza —p.ej. gpt-5.5— lo omite en runtime).
- **Arranque del worker cableado** (`main.py` lifespan + `WORKER_ENABLED`, apagado por defecto).
- **Config de despliegue en Render** (`render.yaml` + `DEPLOY_RENDER.md`) — ver §5 y §6.

## 3. Cómo funciona el sistema (mapa mental para retomar)
`Móvil (Flutter, offline-first)` → guarda la captura y la sincroniza → **API NestJS** `POST /v1/captures` (idempotente) → **encola** un job en Redis (BullMQ) → **Servicio IA (Python)**: el **worker** consume el job → **pipeline** llama al **`AIProvider` (OpenAI `gpt-5.4-mini`)** para extraer entidades/tareas/temas → **escribe en el grafo** Postgres bajo RLS (aislado por usuario) con provenance + embedding (pgvector) + coste. Todo con idempotencia (una captura se procesa una vez). La calidad de la extracción se mide con el **examen F2** (45 casos gold, `apps/ai/app/eval/`) contra un **gate ratificado** (ADR-018: F1≥0.80, taskP≥0.85, hallucination≤0.10, coste≤$0.01).

## 4. Últimas decisiones (esta sesión)
- **Proveedor de comprensión = OpenAI `gpt-5.4-mini`** (no la 5.5: la 5.5 atrapa más recall pero **inventa más** y cuesta ~12x; la mini supera el gate barato). PRs #47/#49/#50.
- **Prompt v8** como versión de producción (R-001 resuelta). PRs #51 (v7) → #52 (v8) → #53 (registro).
- **Worker: cableado pero apagado por defecto** (`WORKER_ENABLED`); se enciende en el despliegue. PR #54.
- **Voz: text-first, transcripción diferida** (sub-proyecto propio: `AIProvider.transcribe` + acceso al blob). PR #54 / design §19.
- **Finanzas: función futura reservada (V4)**, ampliación sobre F2, se construye DESPUÉS de encender el bucle central. Roadmap §3.1 (PR #54).
- **Despliegue = servicios+cola en Render, base de datos en Neon (gratis).** El cupo único de Postgres gratis de Render ya está ocupado por otro proyecto del founder, y el gratis de Render se borra a los ~30 días; Neon gratis NO se borra, tiene pgvector y es portable (Postgres estándar). Empezar **GRATIS** (Neon + Render free), luego pasar los 2 servicios a Starter (~$14/mes) para 24/7. `render.yaml` ya NO crea la base de Render (usa Neon vía `sync:false`). PRs #55/#56 + PR de Neon.
- Vigentes: **ADR-012** (stack), **ADR-018/019** (gate + puente cola), norma "aprovisionar antes de degradar".

## 5. Próxima acción inmediata — YA DESPLEGADO Y VIVO; sigue producto
**HECHO (2026-07-09): mindOS desplegado y VALIDADO end-to-end en producción** (Render + Neon + OpenAI, gratis). Prueba real: captura de texto `raw`→`processed` en la nube. URLs: API `https://mindos-api.onrender.com`, IA `https://mindos-ai.onrender.com`. Cómo se hizo y cómo recuperar fallos: `docs/06-infrastructure/DEPLOY_RENDER.md`. Config del deploy: `render.yaml` + `apps/*/Dockerfile` + `apps/api/docker-entrypoint.sh`.

**HECHO (2026-07-10): APP WEB en línea.** El código Flutter existente se habilitó para navegador (Drift condicional native/WASM, lector de audio condicional), se construyó el feature de **auth** (cliente `/v1/auth/*`, `TokenStore` con `shared_preferences`, controller Riverpod, pantallas login/registro), un **router con guard** de sesión y un **home** (estado de conexión + capturas recientes + logout); el `accessTokenProvider` ahora usa el token del usuario. Desplegada como **sitio estático en Render** (`mindos-web`, no se duerme; build instala Flutter y compila con `--dart-define=API_BASE_URL`) y se habilitó **CORS** configurable en la API (`CORS_ORIGIN`). `flutter analyze` limpio, 16/16 tests, `flutter build web` OK. Docs: `docs/ESTADO_DEL_PROYECTO.md` (founder) + `DEPLOY_RENDER.md` actualizado.

**Siguiente foco = F3 (recuperación de valor / hacerlo "extremadamente inteligente"):**
1. **Exponer el grafo (habilitador):** endpoints de LECTURA en la API para el conocimiento derivado (nodos por tipo: person/project/event/topic/task; y conexiones). Hoy solo existen `POST/GET /v1/captures`; **no** hay forma de leer lo que el cerebro extrajo. Sin esto, la app no puede mostrar la inteligencia.
2. **Mostrar la inteligencia en la app (el "wow"):** al crear una captura, ver las tarjetas de personas/tareas/proyectos/eventos/temas y sus conexiones; pantallas "mis tareas", "personas", etc.
3. **Daily Briefing** (`GET /v1/briefing`): resumen proactivo al abrir.
4. **Consulta** (`POST /v1/query` con RAG + citas de fuentes).
5. **Voz** (diferida, hueco listo) y luego **Finanzas (V4)**.
6. **Observabilidad (papercut):** subir logging a INFO en `mindos-ai`.
7. **24/7 real cuando se quiera:** `mindos-api` + `mindos-ai` a **starter** (~$7 c/u; la web estática ya no se duerme).

## 6. Bloqueadores y avisos importantes
- **NO hay bloqueadores.** mindOS está desplegado y validado end-to-end en producción; R-001 resuelta, R-007 cerrado, D-011 mitigado.
- **Modo gratis (actual):** los servicios de Render se **duermen** a los ~15 min (despiertan lentos, ~30-60 s) — por eso el worker no drena la cola 24/7 hasta que algo lo despierta. La **BD de Neon gratis NO se borra** (a diferencia de la de Render). Para uso real 24/7, subir los 2 servicios a `starter` (~$7 c/u).
- **Observabilidad:** el log "worker started" es INFO y no se ve con la config actual (solo se ven ERROR); por eso durante el deploy el éxito se confirmó por ausencia de error + estado `processed`. Mejora pendiente: subir logging a INFO.

## 7. Riesgos vivos (detalle e historia en [012](./012_RISK_AND_DEBT_REGISTER.md))
- **R-001 (RESUELTA para el gate, 2026-07-09):** calidad de comprensión. v8: F1 0.890 / taskP 1.000 / hall 0.074 / $0.0023 = GATE PASSED con margen (OpenAI `gpt-5.4-mini`). Residual NO gated: connections F1 0.187 (graph-linking).
- **R-007 (cerrado):** motor F2 validado contra infra real.
- **R-005 (validado en F1), R-002 (mitigado), R-003 (mitigado), R-006 (cerrado), R-004 (en corrección).**

## 8. Deuda técnica top (detalle en [012](./012_RISK_AND_DEBT_REGISTER.md))
- **D-011 (nueva, abierta):** config de despliegue de Render (`render.yaml` + Dockerfiles) **no verificada** contra Render/Docker desde el entorno; validar en el primer deploy (permiso CREATE ROLE/EXTENSION en la BD gestionada, mapeo de Redis host/port/password).
- **D-008 (en progreso):** dimensión de embedding fijada en 1536; proveedor de embeddings definitivo pendiente.
- **D-010 (en progreso):** prompt consolidado (ahora en **v8**); ~28% menos tokens que el apilado v2+v3+v4; se puede cerrar tras confirmar estabilidad en producción.
- **D-005, D-006 (abiertos).** Cerrados/mitigados: D-001..D-004, D-007, D-009.

## 9. Salud de la arquitectura
Alta coherencia doc→código. El motor de F2 respeta el estilo de puertos (`AIProvider`, `GraphStore`), probable sin infra. La temperatura adaptativa del proveedor evita casarse con un nombre de modelo. La frontera de dos backends sigue bien definida (ADR-010). El despliegue es portable (Docker, ADR-015): si se quiere abaratar, la BD puede moverse a Neon (gratis) sin rediseño.

## 10. Cambios recientes (esta sesión, 2026-07-09)
- **R-001 RESUELTA:** OpenAI `gpt-5.4-mini` + prompt v6→v7→v8 → v8 GATE PASSED con margen (PRs #47/#49/#50/#51/#52/#53).
- **Temperatura adaptativa** en el proveedor OpenAI-compatible (desbloquea gpt-5.x/o-series sin perder determinismo en la mini).
- **Arranque del worker cableado** (`WORKER_ENABLED`, lifespan) — PR #54.
- **Voz decidida** (text-first/diferida) y **Finanzas anotada** (V4) — PR #54 / roadmap §3.1 / design §19.
- **Despliegue en Render preparado** (`render.yaml` + `DEPLOY_RENDER.md`; fixes de Dockerfiles) — PR #55 (+ fix a plan gratis en el PR de handoff).

## 11. Preguntas abiertas
- **¿Cuándo pasar a 24/7 de pago?** (hoy: gratis para probar). Decisión del founder según cuándo quiera uso real.
- **Transcripción de voz:** ¿cliente o F2? Decidido *diferir*; se elegirá con datos de calidad/latencia cuando toque.
- **Proveedor de embeddings definitivo** (D-008) → se fija con el motor en producción.

## 12. Acciones recomendadas (priorizadas)
1. **Mergear el PR de handoff** (este) para dejar `render.yaml` en gratis y el estado documentado.
2. **Aplicar el Blueprint en Render** (§5) y verificar el circuito end-to-end en gratis.
3. **Pasar a 24/7** (servicios starter + BD de pago) cuando el founder lo decida.
4. **Voz** y luego **Finanzas (V4)**.
5. Refrescar 009 y 012 al cierre (ritual [008](./008_AI_COLLABORATION_PROTOCOL.md)).

## 13. PRs de esta sesión (todos MERGEADOS salvo el de handoff)
- **#47** cableado OpenAI GPT-5.x (precios, default `gpt-5.4-mini`, Variable `OPENAI_MODEL`). **Mergeado.**
- **#49** Variable `EVAL_COST_PER_CAPTURE_MAX_USD` en el workflow del examen. **Mergeado.**
- **#50** fix `temperature` para GPT-5/o-series (luego reemplazado por adaptación en runtime en #51). **Mergeado.**
- **#51** prompt **v7** (recall) + temperatura adaptativa + registro decisión mini-vs-5.5. **Mergeado.**
- **#52** prompt **v8** (baja alucinación conservando recall). **Mergeado.**
- **#53** registro de R-001 v8 GATE PASSED en 009/012. **Mergeado.**
- **#54** arranque del worker (`WORKER_ENABLED`) + ficha Finanzas (V4) + decisión de voz. **Mergeado.**
- **#55** Blueprint de Render + guía + fixes de Dockerfiles. **Mergeado** (⚠ con servicios en `starter`; ver §6).
- **PR de handoff (este):** este 009 + 012 + **fix `render.yaml` a plan gratis**. Pendiente de merge.

## 14. Nota para la nueva sesión (importante)
- **Hablar en español y en lenguaje no técnico** con el founder (CEO no programador); actuar como **CPTO con pensamiento crítico**.
- **NO relajar umbrales ni gold** para "aprobar": el rigor es el producto.
- **Patrón observado:** el founder a veces **mergea los PRs ANTES** de que yo suba un ajuste de seguimiento a la misma rama → SIEMPRE verificar el estado REAL de `main` (`list_pull_requests` + pull) antes de asumir qué está desplegado. Ya pasó con #51 (v7 en vez de v8) y #55 (starter en vez de free).
- **Siguiente hito:** DESPLEGAR EN RENDER siguiendo `docs/06-infrastructure/DEPLOY_RENDER.md` (empezar gratis). El motor está listo para encenderse; falta el "enchufe" del servidor.
- **Mantener el ritual:** actualizar 009 y 012 al cierre.

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
