# Documento de Requisitos — Capture Engine (F1)

| Metadato | Valor |
|----------|-------|
| Versión | 0.1 (borrador para revisión) |
| Estado | Borrador |
| Autor | Ingeniería (spec design-first) |
| Ámbito | Requisitos formales (EARS) del motor de captura F1: API síncrona de creación (texto/voz), idempotencia, aislamiento por usuario (RLS), no-pérdida de la captura, lectura/listado propios, coherencia temporal y handoff a la cola de comprensión. Derivados del diseño técnico aprobado. |
| Derivado de | [design.md](./design.md) (flujo design-first) |
| Depende de | [002 Constitución](../../../docs/000_SYSTEM/002_ENGINEERING_CONSTITUTION.md), [ADR-010](../../../docs/02-architecture/adr/ADR-010-final-stack-and-two-backends.md), [ADR-012](../../../docs/02-architecture/adr/ADR-012-canonical-stack.md), [#03 Data Model](../../../docs/03-data/data-architecture-and-domain-model.md), [#04 API](../../../docs/04-api/api-design-specification.md) |
| Fuera de alcance | Comprensión/IA (F2): el consumo del mensaje de cola, la creación de nodos derivados y aristas, y las transiciones `processing → processed`. F1 sólo entrega el trabajo a la cola. |
| Última actualización | 2026-07-02 |

---

## Introducción

El **Capture Engine** es la fase F1 de mindOS y cubre el primer tercio del bucle de
valor (**capturar → comprender → recuperar**). Permite que un usuario autenticado
registre un pensamiento —texto o voz— desde la app móvil y que ese dato se persista
de forma fiable e instantánea como un nodo `Capture` (`status=raw`) del property
graph, quedando encolado para la comprensión asíncrona posterior (F2, fuera de
alcance salvo el punto de entrega a la cola).

Este documento deriva los requisitos formales **a partir del diseño técnico ya
aprobado** ([design.md](./design.md)). Cada requisito se expresa en formato **EARS**,
es trazable a las decisiones del diseño, a las **propiedades de correctitud P1–P9**
(§12 del diseño) y a los **principios de la Constitución** ([#002](../../../docs/000_SYSTEM/002_ENGINEERING_CONSTITUTION.md))
cuando aplica. Dos principios rigen todo el documento: **la captura cruda es sagrada
y nunca se pierde** (Constitución §9) y **el fallo del pipeline de IA nunca pierde la
captura** (Constitución §10).

El alcance de F1 abarca: el contrato de API síncrono (`POST /v1/captures` + lectura y
listado propios) con `Idempotency-Key` y objetivo **p95 < 300 ms**; el modelo de datos
`nodes`/`edges` con **RLS** por usuario; el almacenamiento de blobs de voz en
S3-compatible; el handoff asíncrono a F2 vía BullMQ; y la captura offline-first en
Flutter con sincronización idempotente.

## Glosario

- **Capture_System**: Motor de captura F1 en su conjunto (backend NestJS + almacenes + cliente móvil). Nombre de sistema por defecto cuando un requisito abarca varios componentes.
- **Capture_API**: Superficie HTTP del bounded context Capture en NestJS (`CaptureController`): endpoints `POST /v1/captures`, `POST /v1/captures/audio-upload`, `GET /v1/captures/{id}`, `GET /v1/captures`.
- **Capture_Service**: Servicio de dominio que orquesta el flujo síncrono (idempotencia → persistir → encolar) descrito en §8 del diseño.
- **Idempotency_Service**: Componente que resuelve la semántica de `Idempotency-Key` (§7.2 del diseño).
- **Blob_Storage**: Servicio de almacenamiento de blobs de voz sobre S3-compatible (MinIO/R2) descrito en §9 del diseño.
- **Understanding_Queue**: Productor BullMQ sobre Redis que entrega el trabajo de comprensión a F2 (§10 del diseño).
- **RLS_Context**: Mecanismo `PrismaRlsService.withUser` que fija `app.current_user_id` por transacción para activar las políticas RLS (§6 del diseño).
- **Sync_Service**: Servicio Flutter que drena el outbox local (Drift) y sincroniza con la `Capture_API` (§11 del diseño).
- **Captura (`Capture`)**: Nodo del property graph con `type=capture`, creado con `status=raw` en F1. Contiene contenido crudo (`body`) y/o referencia de audio (`attributes.audio_ref`).
- **Idempotency-Key**: Clave provista por el cliente (UUID) que hace idempotente la creación; en sync offline equivale al `client_id` del outbox.
- **audio_ref**: Clave/URI del objeto de audio en S3 (`audio/{user_id}/{uuid}.ext`); nunca el binario.
- **occurred_at**: Momento en que ocurrió el hecho registrado, si el cliente lo conoce (modelo temporal #03 §9).
- **created_at**: Momento de creación del registro en el servidor (asignado por `Capture_System`).
- **client_id**: UUID generado en el dispositivo para cada captura del outbox de Drift; se usa como `Idempotency-Key`.
- **owner (dueño)**: Usuario autenticado (`user_id` extraído del JWT) al que pertenece una captura.

---

## Requisitos

### Requisito 1: Crear captura de texto autenticada

**Historia de usuario:** Como usuario autenticado, quiero registrar un pensamiento de
texto, para que quede persistido de forma fiable e inmediata como una captura cruda.

*Trazabilidad: diseño §3.1, §7.1, §8; Constitución §9, §12; propiedades P2, P3, P5.*

#### Criterios de aceptación

1. WHEN se recibe una solicitud `POST /v1/captures` autenticada con `type=text`, contenido no vacío y `Idempotency-Key` presente, THE Capture_Service SHALL persistir una Captura con `status=raw` y `origin=manual_text` asociada al `user_id` del token, antes de encolar ningún trabajo.
2. WHEN una Captura de texto se persiste correctamente, THE Capture_API SHALL responder `202 Accepted` con `capture_id`, `status`, `created_at` y `occurred_at`.
3. THE Capture_Service SHALL derivar el `user_id` de la Captura exclusivamente del JWT verificado por `JwtAuthGuard`, y no del cuerpo de la solicitud.
4. IF la solicitud `POST /v1/captures` carece del token de autenticación o presenta un JWT inválido o expirado, THEN THE Capture_API SHALL responder `401` sin crear ninguna Captura.
5. IF el cuerpo de la solicitud no cumple el DTO (`type` inválido, `content` vacío para texto, o campos fuera de rango), THEN THE Capture_API SHALL responder `400 validation_error` sin crear ninguna Captura.
6. WHILE el camino síncrono de `POST /v1/captures` se ejecuta, THE Capture_Service SHALL limitar el trabajo a una transacción de inserción y un encolado no bloqueante, con objetivo de latencia p95 inferior a 300 ms.

### Requisito 2: Crear captura de voz (subida de audio y referencia)

**Historia de usuario:** Como usuario autenticado, quiero registrar una nota de voz
subiendo el audio y referenciándolo, para capturar pensamientos hablados sin que el
binario sobrecargue la API ni la base de datos.

*Trazabilidad: diseño §3.2, §7.1, §9; ADR-012 D6; propiedades P6.*

#### Criterios de aceptación

1. WHEN se recibe una solicitud `POST /v1/captures/audio-upload` autenticada con `content_type` en la allowlist (`audio/m4a`, `audio/mpeg`, `audio/webm`) y `size_bytes` dentro del límite permitido, THE Blob_Storage SHALL generar una URL de subida firmada de vida corta y un `audio_ref` bajo el prefijo `audio/{user_id}/`.
2. IF el `content_type` no está en la allowlist o `size_bytes` excede el límite máximo, THEN THE Capture_API SHALL rechazar la solicitud de presigned con `400 validation_error` sin generar URL de subida.
3. WHEN se recibe una solicitud `POST /v1/captures` autenticada con `type=voice` y un `audio_ref`, THE Capture_Service SHALL verificar que el `audio_ref` pertenece al `user_id` del token y existe en S3 antes de persistir la Captura.
4. WHEN una Captura de voz con `audio_ref` válido se persiste, THE Capture_Service SHALL crear la Captura con `origin=voice` y almacenar únicamente el `audio_ref` en `attributes.audio_ref`, sin escribir el binario de audio en PostgreSQL.
5. IF el `audio_ref` referenciado no pertenece al `user_id` del token o no existe en S3, THEN THE Capture_API SHALL responder `403 forbidden` o `422` sin crear ninguna Captura.

### Requisito 3: Idempotencia de creación y reuso incoherente de clave

**Historia de usuario:** Como cliente de la API (móvil), quiero que reenviar la misma
solicitud de creación no genere duplicados, para que los reintentos de red sean
seguros y coherentes.

*Trazabilidad: diseño §7.2, §8; #04 idempotencia; propiedades P3, P4.*

#### Criterios de aceptación

1. WHEN se recibe una solicitud `POST /v1/captures` con una `Idempotency-Key` ya registrada para el usuario y con el mismo payload, THE Idempotency_Service SHALL devolver la respuesta de la Captura original con el mismo `capture_id`, sin crear una segunda Captura.
2. IF se recibe una solicitud `POST /v1/captures` con una `Idempotency-Key` ya registrada para el usuario pero con un payload distinto (`request_hash` diferente), THEN THE Capture_API SHALL responder `409 idempotency_key_reuse` sin modificar la Captura original.
3. IF una solicitud `POST /v1/captures` no incluye la cabecera `Idempotency-Key`, THEN THE Capture_API SHALL responder `400 missing_idempotency_key` sin crear ninguna Captura.
4. THE Idempotency_Service SHALL almacenar el registro de idempotencia con unicidad por `(user_id, key)` y persistir el `request_hash` del payload dentro de la misma transacción que crea la Captura.

### Requisito 4: Aislamiento por usuario (RLS fail-closed)

**Historia de usuario:** Como usuario, quiero que mis capturas sean visibles y
accesibles únicamente para mí, para que mis datos permanezcan privados incluso ante
un fallo de la capa de aplicación.

*Trazabilidad: diseño §6, §16; Constitución §7; propiedades P1, P8.*

#### Criterios de aceptación

1. WHEN un usuario dueño solicita `GET /v1/captures/{id}` de una Captura propia, THE Capture_API SHALL devolver la Captura.
2. IF un usuario solicita `GET /v1/captures/{id}` de una Captura que no le pertenece, THEN THE Capture_API SHALL responder `404` sin revelar el contenido ni la existencia de la Captura.
3. WHEN un usuario solicita `GET /v1/captures`, THE Capture_API SHALL incluir en el resultado únicamente Capturas cuyo `user_id` coincide con el `user_id` del token.
4. WHILE una operación de lectura o escritura sobre `nodes`, `edges` o `idempotency_keys` se ejecuta, THE RLS_Context SHALL fijar `app.current_user_id` con el `user_id` del token dentro de la misma transacción que las consultas.
5. IF una consulta a `nodes`, `edges` o `idempotency_keys` se ejecuta sin `app.current_user_id` fijado, THEN THE Capture_System SHALL impedir la lectura y la escritura de toda fila (comportamiento fail-closed).

### Requisito 5: Garantía de no-pérdida ante fallo de encolado o worker

**Historia de usuario:** Como usuario, quiero que mi captura permanezca a salvo aunque
falle el encolado o el procesamiento de IA, para no perder nunca lo que registré.

*Trazabilidad: diseño §8, §10.1, §10.2, §13; Constitución §9, §10; riesgo R-005; propiedades P2.*

#### Criterios de aceptación

1. THE Capture_Service SHALL persistir la Captura en PostgreSQL antes de intentar encolar el trabajo de comprensión.
2. IF el encolado en Understanding_Queue falla después de persistir la Captura, THEN THE Capture_API SHALL responder `202 Accepted` y conservar la Captura con `status=raw`.
3. WHEN una Captura permanece con `status=raw` más allá del umbral de reconciliación sin un trabajo activo asociado, THE Capture_System SHALL reencolar el trabajo de comprensión mediante el barrido de reconciliación.
4. WHEN el barrido de reconciliación reencola un trabajo, THE Understanding_Queue SHALL evitar duplicados usando `jobId = capture_id`.
5. IF el worker de F2 agota sus reintentos (`attempts`), THEN THE Capture_System SHALL conservar la Captura cruda intacta y retener el trabajo fallido para inspección o reintento posterior.

### Requisito 6: Captura offline y sincronización idempotente

**Historia de usuario:** Como usuario en movilidad, quiero registrar capturas sin
conexión y que se sincronicen automáticamente al reconectar, para no depender de la
red y no generar duplicados.

*Trazabilidad: diseño §3.3, §11; riesgo R-005; Constitución §9; propiedades P9, P3.*

#### Criterios de aceptación

1. WHEN un usuario registra una captura sin conexión, THE Sync_Service SHALL persistirla en el outbox local (Drift) con `sync_state=pending` y un `client_id` UUID, y confirmar el guardado de forma optimista.
2. WHEN se recupera la conectividad, THE Sync_Service SHALL enviar cada captura pendiente mediante `POST /v1/captures` en orden FIFO usando `Idempotency-Key = client_id`.
3. WHEN la Capture_API confirma la creación o la coincidencia de una captura sincronizada, THE Sync_Service SHALL marcar la entrada local como `synced` y almacenar el `capture_id` devuelto como `server_id`.
4. WHEN una misma captura del outbox se reenvía múltiples veces con el mismo `client_id`, THE Capture_System SHALL crear exactamente una Captura en el servidor.
5. IF la sincronización de una captura recibe un error `5xx`, un timeout o pérdida de red, THEN THE Sync_Service SHALL incrementar el contador de reintentos y reprogramar el envío con backoff exponencial.
6. IF la sincronización recibe un error de validación `4xx`, THEN THE Sync_Service SHALL marcar la entrada local como `failed` sin reintentar automáticamente.

### Requisito 7: Lectura y listado paginado de capturas propias

**Historia de usuario:** Como usuario, quiero leer una captura concreta y listar mis
capturas de forma paginada, para consultar lo que he registrado y sondear su estado
de procesamiento.

*Trazabilidad: diseño §7.1, §15; propiedades P1.*

#### Criterios de aceptación

1. WHEN un usuario dueño solicita `GET /v1/captures/{id}` con un UUID válido, THE Capture_API SHALL devolver `capture_id`, `status`, `created_at` y `occurred_at` de la Captura.
2. WHEN un usuario solicita `GET /v1/captures`, THE Capture_API SHALL devolver una página de Capturas propias junto con un `next_cursor` que es `null` cuando no hay más resultados.
3. WHERE la solicitud de listado incluye un parámetro `status`, THE Capture_API SHALL devolver únicamente Capturas propias cuyo estado coincide con el filtro.
4. IF el parámetro `id` de `GET /v1/captures/{id}` no es un UUID válido, THEN THE Capture_API SHALL responder `400 validation_error`.

### Requisito 8: Coherencia temporal (occurred_at ≤ created_at)

**Historia de usuario:** Como consumidor de los datos de captura, quiero que el momento
del hecho no sea posterior al momento de registro, para preservar la coherencia del
modelo temporal.

*Trazabilidad: diseño §7.1 (DTO), §12 P5; #03 §9; propiedades P5.*

#### Criterios de aceptación

1. WHEN se crea una Captura con `occurred_at` presente, THE Capture_Service SHALL garantizar que `occurred_at` es anterior o igual a `created_at`.
2. IF una solicitud `POST /v1/captures` incluye un `occurred_at` posterior a la hora del servidor en el momento de creación, THEN THE Capture_API SHALL responder `400 validation_error` sin crear la Captura.
3. WHEN se crea una Captura sin `occurred_at`, THE Capture_Service SHALL persistir `occurred_at` como `null` y asignar `created_at` con la hora del servidor.

### Requisito 9: Handoff a la cola de comprensión (contrato del mensaje)

**Historia de usuario:** Como equipo de F2, quiero recibir un mensaje de trabajo con un
contrato estable y fiable por cada captura, para consumir y comprender capturas sin
ambigüedad ni duplicados.

*Trazabilidad: diseño §10, §10.1; Constitución §10, §12; propiedades P7. (El consumo del mensaje es F2, fuera de alcance.)*

#### Criterios de aceptación

1. WHEN una Captura se persiste correctamente, THE Understanding_Queue SHALL encolar un trabajo `understanding.process` que incluye `schema_version`, `capture_id`, `user_id` y `enqueued_at`.
2. THE Understanding_Queue SHALL asignar `jobId = capture_id` de modo que un mismo `capture_id` encolado o entregado más de una vez resulte en un único trabajo.
3. WHERE un trabajo de comprensión falla en el consumidor, THE Understanding_Queue SHALL reintentarlo hasta `attempts` veces con backoff exponencial y retener el trabajo fallido tras agotar los reintentos.
4. THE Understanding_Queue SHALL versionar el contrato del mensaje mediante `schema_version` para permitir la evolución sin romper al consumidor de F2.

---

## Trazabilidad Requisitos ↔ Propiedades ↔ Constitución

| Requisito | Propiedades de correctitud | Principios de Constitución | Referencias de diseño |
|-----------|----------------------------|----------------------------|-----------------------|
| R1 — Captura de texto | P2, P3, P5 | §9, §12 | §3.1, §7.1, §8 |
| R2 — Captura de voz | P6 | §9 | §3.2, §7.1, §9 |
| R3 — Idempotencia / reuso incoherente | P3, P4 | §12 | §7.2, §8 |
| R4 — Aislamiento por usuario (RLS) | P1, P8 | §7 | §6, §16 |
| R5 — No-pérdida ante fallo | P2, P7 | §9, §10 | §8, §10.1, §10.2, §13 |
| R6 — Offline + sync idempotente | P9, P3 | §9 | §3.3, §11 |
| R7 — Lectura / listado propios | P1 | §7 | §7.1, §15 |
| R8 — Coherencia temporal | P5 | — | §7.1, §12 |
| R9 — Handoff a la cola | P7 | §10, §12 | §10, §10.1 |

---

## Historial de versiones

| Versión | Fecha | Autor | Cambios |
|---------|-------|-------|---------|
| 0.1 | 2026-07-02 | Ingeniería | Requisitos iniciales de F1 derivados del diseño aprobado (design-first): 9 requisitos EARS (captura de texto, captura de voz, idempotencia y reuso de clave, aislamiento RLS fail-closed, no-pérdida ante fallo de encolado/worker, offline + sync idempotente, lectura/listado propios, coherencia temporal `occurred_at ≤ created_at`, handoff a la cola de comprensión), con Introducción, Glosario y matriz de trazabilidad a las propiedades P1–P9 y a la Constitución (#002). |
