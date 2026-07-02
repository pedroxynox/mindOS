# Guía de testing de integración — mindOS F1 (cierre de R-006)

Esta guía explica, paso a paso, cómo ejecutar la **validación de integración real**
de la fase F1 (capture-engine) contra servicios de verdad (PostgreSQL con RLS y
rol no-owner, Redis y MinIO) y cómo correr los tests de la app móvil (Flutter).

Los tests unitarios y de propiedades (PBT con `fast-check`) se ejecutan siempre
con `npm test`. Los tests de **integración** están detrás de un interruptor de
entorno (`RUN_INTEGRATION=1`), de modo que el `npm test` normal los **salta** y
CI no necesita infraestructura. Requieren Docker, que **no** está disponible en
el sandbox donde se preparó este arnés: la ejecución real queda para un entorno
con Docker + Flutter.

---

## 0. Requisitos previos

- Docker + Docker Compose.
- Node.js y dependencias del API instaladas (`cd apps/api && npm ci`).
- Para la parte móvil: SDK de Flutter (Dart `>=3.5.0 <4.0.0`).

---

## 1. Levantar los servicios de prueba

Desde la raíz del repositorio:

```bash
docker compose -f infra/docker-compose.test.yml up -d
```

Esto arranca:

| Servicio        | Imagen                  | Puerto host | Para qué |
|-----------------|-------------------------|-------------|----------|
| `postgres-test` | `pgvector/pgvector:pg16`| 5432        | Grafo `nodes`/`edges` + RLS fail-closed |
| `redis-test`    | `redis:7-alpine`        | 6379        | Handoff BullMQ + reconciliación |
| `minio-test`    | `minio/minio`           | 9000 / 9001 | Blobs de audio (S3-compatible) |
| `minio-setup`   | `minio/mc`              | (one-shot)  | Crea el bucket `mindos-audio` y termina |

Notas:

- Los puertos coinciden con los valores por defecto de `apps/api/.env.example`
  (5432 / 6379 / 9000), así los specs funcionan sin configuración extra.
- **No** levantes a la vez el stack de desarrollo (`infra/docker-compose.yml`) y
  el de test: usan los mismos puertos. Detén uno antes de arrancar el otro.
- El **rol de aplicación no-owner** `mindos_app` (NOSUPERUSER / NOBYPASSRLS) se
  provisiona de dos formas complementarias e idempotentes:
  1. `infra/postgres-init/01-app-role.sql` lo crea al inicializar el cluster.
  2. La migración RLS (`20260702010100_rls_fail_closed`) lo (re)crea con
     `IF NOT EXISTS` y le concede los `GRANT` mínimos sobre las tablas del grafo.
- El bucket inicial `mindos-audio` (variable `S3_BUCKET`) lo crea el contenedor
  one-shot `minio-setup` automáticamente.

Comprueba que todo esté sano:

```bash
docker compose -f infra/docker-compose.test.yml ps
```

---

## 2. Aplicar las migraciones (como rol OWNER / de migración)

Las migraciones (DDL: `CREATE TABLE`, `ENABLE/FORCE ROW LEVEL SECURITY`,
`CREATE POLICY`, `GRANT`) deben ejecutarse con el rol **owner** `mindos`, NO con
el rol de aplicación. Usa `MIGRATION_DATABASE_URL`:

```bash
cd apps/api
DATABASE_URL="postgresql://mindos:mindos@localhost:5432/mindos?schema=public" \
  npm run migrate:test
```

`migrate:test` ejecuta `prisma migrate deploy` (aplica todas las migraciones sin
generar nuevas). Tras esto existen las tablas, las políticas RLS y el rol
`mindos_app` con sus permisos.

---

## 3. Fijar las variables de entorno y ejecutar la integración

La app (y por tanto los tests que instancian `PrismaService`) se conecta como el
rol **no-owner** `mindos_app` vía `DATABASE_URL`. Esto es imprescindible: `FORCE
ROW LEVEL SECURITY` no aplica al owner ni a superusuarios, así que solo con una
conexión no-owner se observa el aislamiento real (P1 / P8).

```bash
cd apps/api

export DATABASE_URL="postgresql://mindos_app:mindos_app@localhost:5432/mindos?schema=public"
export REDIS_HOST="localhost"
export REDIS_PORT="6379"
export S3_ENDPOINT="http://localhost:9000"
export S3_REGION="us-east-1"
export S3_BUCKET="mindos-audio"
export S3_ACCESS_KEY_ID="minioadmin"
export S3_SECRET_ACCESS_KEY="minioadmin"
export S3_FORCE_PATH_STYLE="true"

npm run test:integration
```

`test:integration` equivale a `RUN_INTEGRATION=1 jest`. El interruptor
`RUN_INTEGRATION=1` activa los `describe` de los `*.integration.spec.ts`
(sin él, `npm test` los salta).

Para ejecutar solo una suite:

```bash
RUN_INTEGRATION=1 npm test -- prisma-rls.rls.integration
RUN_INTEGRATION=1 npm test -- blob-storage.minio
RUN_INTEGRATION=1 npm test -- understanding.queue.redis
RUN_INTEGRATION=1 npm test -- reconciliation.service.integration
RUN_INTEGRATION=1 npm test -- blob-janitor.minio
```

### Qué propiedad valida cada test

| Spec | Servicios | Propiedades / Requisitos |
|------|-----------|--------------------------|
| `src/prisma/prisma-rls.rls.integration.spec.ts` | Postgres (rol no-owner) | **P1** aislamiento por dueño (RLS) y **P8** fail-closed sin contexto de usuario · R4.2/R4.3/R4.5 |
| `src/capture/reconciliation.service.integration.spec.ts` | Postgres + Redis | **P2** la captura nunca se pierde: re-encola una captura `raw` estancada exactamente una vez · R5.2/R5.3/R5.4 |
| `src/capture/understanding.queue.redis.integration.spec.ts` | Redis | **P7** idempotencia del handoff: dedup por `jobId = capture_id` y `removeOnFail:false` · R9.2/R9.3 |
| `src/capture/blob-storage.minio.integration.spec.ts` | MinIO | **P6** el audio nunca entra en Postgres: round-trip presign→upload→verificación de propiedad · R2.1/R2.3/R2.5 |
| `src/capture/blob-janitor.minio.integration.spec.ts` | MinIO + Postgres | Janitor de huérfanos: purga un blob no referenciado y conserva uno referenciado · R2.1/R2.4 |

> Nota sobre el janitor: la elegibilidad depende del TTL (edad del objeto). Para
> una aserción determinista sobre la purga conviene pre-envejecer el objeto o
> usar un reloj falso; el test comprueba que el objeto referenciado siempre se
> conserva.

---

## 4. Bajar el stack

```bash
docker compose -f infra/docker-compose.test.yml down -v
```

El flag `-v` elimina también los volúmenes (estado de Postgres/MinIO), dejando un
entorno limpio para la siguiente corrida.

---

## 5. Tests de la app móvil (Flutter)

Los tests de Flutter no necesitan Docker (usan SQLite en memoria vía Drift):

```bash
cd apps/mobile
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter test
```

`build_runner` genera el código de Drift (`app_database.g.dart`) necesario antes
de compilar los tests. Cubren el repositorio de captura offline-first y el
`SyncService` (outbox / drenado al recuperar conectividad), apoyando la
no-pérdida de capturas desde el cliente.

---

## Resumen del flujo

```bash
# 1) Infra
docker compose -f infra/docker-compose.test.yml up -d
# 2) Migraciones (owner)
cd apps/api && DATABASE_URL="postgresql://mindos:mindos@localhost:5432/mindos?schema=public" npm run migrate:test
# 3) Integración (rol no-owner + env)
export DATABASE_URL="postgresql://mindos_app:mindos_app@localhost:5432/mindos?schema=public"
export REDIS_HOST=localhost REDIS_PORT=6379
export S3_ENDPOINT=http://localhost:9000 S3_BUCKET=mindos-audio S3_ACCESS_KEY_ID=minioadmin S3_SECRET_ACCESS_KEY=minioadmin S3_FORCE_PATH_STYLE=true
npm run test:integration
# 4) Limpieza
docker compose -f infra/docker-compose.test.yml down -v
# 5) Móvil
cd ../mobile && flutter pub get && dart run build_runner build --delete-conflicting-outputs && flutter test
```
