# Desplegar mindOS en Render ("todo en Render")

> Guía paso a paso para poner el backend de mindOS a funcionar 24/7 en Render:
> la API (NestJS), el servicio de IA + worker (Python), la base de datos
> (Postgres con pgvector) y la cola (Redis / "Key Value"). Pensada para un
> founder no técnico: son clics en el panel de Render + rellenar unos pocos
> valores. La receta base está en el `render.yaml` de la raíz del repo.

## Qué se va a crear (4 piezas, una sola cuenta)
1. **mindos-postgres** — base de datos con búsqueda inteligente (pgvector).
2. **mindos-redis** — la "cola" de tareas (Key Value de Render).
3. **mindos-api** — la API del negocio (recibe capturas, las mete en la cola).
4. **mindos-ai** — el "cerebro": responde `/health` y **consume la cola**
   (worker) para entender cada captura y escribirla en el grafo.

> No toca ninguna otra app que ya tengas en Render: esto crea servicios nuevos.

## Prerrequisito
- El PR que enciende el worker (`WORKER_ENABLED`, arranque del worker) debe
  estar **mergeado en `main`**. Sin él, `mindos-ai` no consumiría la cola.

## Paso 1 — Crear todo desde el Blueprint
1. En Render: **New → Blueprint**.
2. Conecta el repo `pedroxynox/mindOS` y elige la rama `main`.
3. Render lee `render.yaml` y muestra las 4 piezas. Dale **Apply**.
4. Render pedirá los valores marcados como "no sincronizados" (secretos). Los
   rellenamos en el Paso 2.

## Paso 2 — Rellenar los pocos valores manuales
Render no puede adivinar estos; se ponen una sola vez:

- **`OPENAI_API_KEY`** (en `mindos-ai`): tu clave de OpenAI (`sk-...`).
- **`DATABASE_URL`** (en `mindos-api` y `mindos-ai`): la conexión del rol de
  aplicación (no-dueño), que aísla datos por usuario (RLS). Es **igual** a la
  cadena de la base de datos `mindos-postgres`, pero cambiando el usuario y la
  contraseña por `mindos_app` / `mindos_app`.
  - Copia la **Internal Database URL** de `mindos-postgres` (panel de la BD).
  - Reemplaza `usuario:contraseña@` por `mindos_app:mindos_app@`.
  - Pega el resultado como `DATABASE_URL` en **ambos** servicios.
- **`REDIS_PASSWORD`** (en `mindos-api`): cópialo de la info de conexión de
  `mindos-redis` (dentro de su "connection string", la parte tras `:` y antes
  de `@`). Si la API se conecta por `REDIS_URL`, este campo puede quedar vacío.

## Paso 3 — Migraciones (se ejecutan solas)
El servicio `mindos-api` corre `prisma migrate deploy` **antes de cada deploy**
(con la conexión de **dueño**, `MIGRATION_DATABASE_URL`). Esa migración crea:
las tablas, las reglas de aislamiento (RLS), el rol `mindos_app` (con su
contraseña `mindos_app`) y la extensión **pgvector**.

- Si el primer deploy falla en la migración con un error de **permisos para
  crear rol o extensión**, es porque el usuario dueño de la BD gestionada no
  tiene ese permiso. Solución (una vez): abre el **PSQL / Shell** de
  `mindos-postgres` en Render y ejecuta a mano el rol de app + `CREATE EXTENSION
  vector;` (te paso el SQL exacto cuando lleguemos ahí), luego reintenta el
  deploy. El SQL del rol está en `infra/postgres-init/01-app-role.sql`.

## Paso 4 — Verificar que el motor "está vivo"
- `mindos-api` → abre `https://<tu-api>.onrender.com/v1/health` → debe responder
  OK.
- `mindos-ai` → `https://<tu-ai>.onrender.com/health` → OK, y en sus **Logs**
  debe aparecer "understanding worker started: consuming the queue".
- Prueba real: crea una captura vía la API (o la app). En segundos, los **Logs**
  de `mindos-ai` deben mostrar que la procesó, y quedará escrita en el grafo.

## Costo (honesto)
- **Para PROBAR (gratis):** pon `mindos-postgres` y `mindos-redis` en plan
  **free** y los servicios en free. Funciona para verlo vivo, PERO los servicios
  free se "duermen" y la **BD free se borra a los ~30 días**. No guardes nada
  que te importe.
- **Para 24/7 real:** `mindos-api` y `mindos-ai` en **Starter** (siempre
  despiertos) + Postgres/Key Value en un plan pago pequeño. Estimado
  **~$15–25/mes** (además de lo que ya pagas por tu otra API).

## Notas
- **Voz:** diferida, así que NO hace falta almacenamiento de audio (S3/R2)
  todavía. Menos piezas ahora.
- **Portabilidad:** todo está en Docker; si algún día quieres mover la base de
  datos a Neon (gratis) o el conjunto a otro proveedor, el proyecto lo permite
  (ADR-015).
- Esta guía no pudo probarse desde el entorno de desarrollo (sin acceso a
  Render); afinaremos los detalles específicos de Render en el primer deploy.
