# Desplegar mindOS — servicios y cola en Render, base de datos en Neon

> Guía paso a paso (para founder no técnico) para poner el backend de mindOS a
> funcionar: la API (NestJS) y el servicio de IA + worker (Python) y la cola
> (Redis) en **Render**, y la base de datos (Postgres con pgvector) **gratis en
> Neon**. La base va en Neon porque el único cupo de Postgres gratis de Render
> ya está ocupado por otro proyecto, y el gratis de Neon **no se borra** (el de
> Render se borra a los ~30 días). Neon es Postgres estándar → totalmente
> portable (se puede migrar luego). La receta está en `render.yaml` (raíz).

## Qué se va a crear
- **En Neon (gratis):** `mindos` — la base de datos con búsqueda inteligente.
- **En Render (gratis):**
  - `mindos-redis` — la cola de tareas (Key Value).
  - `mindos-api` — la API (recibe capturas y las mete en la cola).
  - `mindos-ai` — el cerebro: responde `/health` y **consume la cola** (worker),
    entiende cada captura y la escribe en el grafo.

> No toca ninguna otra app ni base de datos que ya tengas: crea recursos nuevos.

## Prerrequisitos
- PRs de arranque del worker (`WORKER_ENABLED`) y de la receta Neon **mergeados
  en `main`**.
- Tener a mano tu **clave de OpenAI** (`sk-...`).

## Paso 1 — Crear la base de datos en Neon (~2 min)
1. Entra a https://neon.tech → **Sign up** (Google/GitHub; gratis, sin tarjeta).
2. **Create project** → nombre `mindos`, región la más cercana a ti. Postgres por
   defecto.
3. Al terminar, Neon muestra la **Connection string** (empieza con
   `postgresql://...` y termina en `?sslmode=require`). **Guárdala** (es la
   conexión del DUEÑO). No la pegues en el chat; la pondremos en Render.
   - Usa la cadena **directa** (no la "pooled") para las migraciones.

## Paso 2 — Crear los servicios en Render desde el Blueprint
1. En Render: **New → Blueprint**.
2. Conecta el repo `pedroxynox/mindOS`, rama `main`.
3. Render lee `render.yaml` y muestra **3 recursos** (mindos-redis, mindos-api,
   mindos-ai). **Apply**.
4. Render pedirá los valores "no sincronizados" (secretos) → Paso 3.

## Paso 3 — Rellenar los valores manuales (una sola vez)
- **`OPENAI_API_KEY`** (en `mindos-ai`): tu clave `sk-...`.
- **`MIGRATION_DATABASE_URL`** (en `mindos-api`): pega la **Connection string de
  Neon** del Paso 1 (la del dueño, con `?sslmode=require`). Se usa solo para
  crear las tablas.
- **`DATABASE_URL`** (en `mindos-api` **y** `mindos-ai`): es la misma cadena de
  Neon pero con el **rol de aplicación** (aislamiento por usuario, RLS). Toma la
  de Neon y cambia el `usuario:contraseña@` del inicio por
  `mindos_app:mindos_app@`, **conservando** el `?sslmode=require` del final.
  Pégala en **ambos** servicios.
- **`REDIS_PASSWORD`** (en `mindos-api`): cópiala de la info de conexión de
  `mindos-redis` (la parte de la contraseña de su "connection string"). Si la
  API se conecta bien por `REDIS_URL`, puede quedar vacía.

> El rol `mindos_app` y su contraseña los CREA la migración (Paso 4); por eso la
> `DATABASE_URL` de app funciona después de migrar.

## Paso 4 — Migraciones (se ejecutan solas)
`mindos-api` corre `prisma migrate deploy` antes de cada deploy usando
`MIGRATION_DATABASE_URL` (rol dueño de Neon). Crea: tablas, RLS, el rol
`mindos_app` (contraseña `mindos_app`) y la extensión **pgvector**. Neon permite
crear roles y extensiones con el rol por defecto, así que debería correr sin
tocar nada a mano.

- Si fallara por permisos, abre el **SQL Editor de Neon** y ejecuta el rol de app
  (`infra/postgres-init/01-app-role.sql`) + `CREATE EXTENSION IF NOT EXISTS
  vector;`, y reintenta el deploy.

## Paso 5 — Verificar que el motor "está vivo"
- `mindos-api`: abre `https://<tu-api>.onrender.com/v1/health` → OK.
- `mindos-ai`: `https://<tu-ai>.onrender.com/health` → OK, y en sus **Logs**
  aparece "understanding worker started: consuming the queue".
- Prueba real: crea una captura vía la API. En segundos, los Logs de `mindos-ai`
  muestran que la procesó y queda escrita en el grafo (Neon).
- En modo gratis los servicios se DUERMEN a los ~15 min; el primer clic los
  despierta (lento) y el worker despierto procesa la cola.

## Costo (honesto)
- **Ahora (probar): $0.** Neon gratis (no se borra) + Render gratis (servicios se
  duermen). Perfecto para confirmar el circuito.
- **24/7 real (~$14/mes):** subir `mindos-api` y `mindos-ai` a **Starter**
  (~$7 c/u). La base puede seguir gratis en Neon un buen tiempo; si crece, Neon
  cobra por uso. La cola gratis de Render suele bastar al principio.

## Notas
- **Voz:** diferida → no hace falta almacenamiento de audio (S3/R2) todavía.
- **Portabilidad (ADR-015):** Neon es Postgres estándar; migrar a Render, AWS,
  Supabase o un servidor propio es una exportación/importación normal (solo se
  necesita que el destino tenga pgvector). Sin amarre.
- **SSL:** tanto Prisma como asyncpg respetan el `?sslmode=require` de la cadena
  de Neon — consérvalo en las tres URLs.
- Esta guía no pudo probarse desde el entorno de desarrollo (sin acceso a
  Render/Neon); afinamos los detalles en el primer deploy (deuda D-011).
