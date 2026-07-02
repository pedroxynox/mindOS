# ADR-012 — Stack canónico confirmado (edge, almacenamiento de objetos y colas)

> **Architecture Decision Record.** Complementa y fija el stack definido en
> [ADR-010](./ADR-010-final-stack-and-two-backends.md), resolviendo ambigüedades y
> cerrando huecos detectados por el CPTO. Afecta a
> [#02 Arquitectura](../technical-architecture.md), [#03 Datos](../../03-data/data-architecture-and-domain-model.md) y
> [#06 Infraestructura](../../06-infrastructure/infrastructure-and-deployment-strategy.md).

| Metadato | Valor |
|----------|-------|
| Estado | 🟢 Aceptado |
| Fecha | 2026-07-02 |
| Autor | CPTO |
| Aprobado por | Founder |
| Depende de | ADR-010, ADR-011 |

---

## Contexto

El stack de ADR-010 (Flutter mobile-first · NestJS+Prisma+PostgreSQL+Redis · Python/FastAPI+LangGraph+LlamaIndex · LLMs intercambiables) está confirmado, pero quedaban ambigüedades (persistencia local, vector store) y huecos que la lista original no cubría (almacenamiento de blobs, colas asíncronas, edge). Este ADR los resuelve para que la verdad viva en el repo.

## Decisiones

**D1 — Persistencia local en móvil: Drift (SQLite).** Se descarta Isar. Razón: modelo relacional/grafo, migraciones robustas y mantenimiento estable; coherente con el PostgreSQL del servidor.

**D2 — PostgreSQL requiere la extensión `pgvector`** como requisito de primera clase (embeddings, #03). No es opcional.

**D3 — Vector store inicial: `pgvector`** dentro del mismo PostgreSQL. Migrar a un motor dedicado (Qdrant/Pinecone/Weaviate) solo si la escala lo exige (two-way-door). Prioriza simplicidad operativa (#02).

**D4 — Acceso a LLMs solo tras la capa `AIProvider`.** Ningún SDK de LLM se invoca fuera de esa abstracción. Es el seguro anti-lock-in (reafirma ADR-010 y #02).

**D5 — Edge/red: Cloudflare** con alcance **DNS + TLS + CDN + WAF + protección DDoS + rate limiting**. NO se usan Cloudflare Workers por ahora (evita lock-in de plataforma). Nginx permanece como reverse proxy en el *origin* (capa distinta). El rate limiting en el edge contribuye a mitigar R-002.

**D6 — Almacenamiento de objetos (blobs): API S3-compatible.** MinIO en desarrollo local (docker-compose) y Cloudflare R2 en staging/prod. Un único cliente S3, backend intercambiable — mismo patrón anti-lock-in que `AIProvider`. Las capturas de voz/imagen/archivo van aquí, nunca en PostgreSQL.

**D7 — Cola de trabajos asíncronos: BullMQ sobre Redis** (NestJS), para el pipeline de comprensión. Garantiza reintentos y que el fallo del pipeline nunca pierda la captura (#02).

**D8 — Infraestructura pesada diferida.** Kubernetes, prod aislado, IaC completa y observabilidad avanzada se difieren a pre-beta (ver [ADR-011](./ADR-011-f0-definition-of-done-and-infra.md)).

## Consecuencias

**Positivas**
- Stack sin ambigüedades ni huecos silenciosos; cada pieza justificada.
- Doble patrón anti-lock-in (LLM y storage) protege la portabilidad a 10 años.
- Complejidad operativa mínima hoy (un solo datastore para datos y vectores).

**Negativas (aceptadas)**
- Dependencia de Cloudflare a nivel de red (mitigada: solo edge, no lógica).
- `pgvector` puede quedarse corto a gran escala → migración futura registrada como posibilidad, no como deuda.

**Trabajo derivado (registrado en 012)**
- Diseñar la estrategia offline-first / sincronización Drift↔API (riesgo R-005).
- Añadir rastreo de errores (Sentry) y gestión de secretos (deuda D-005).

## Alternativas consideradas

- **Isar** (persistencia local): descartada por estabilidad de mantenimiento.
- **Vector store dedicado desde el día 1**: descartado por complejidad prematura.
- **Cloudflare Workers como plataforma de app**: descartado por lock-in prematuro.
- **Blobs en base de datos**: descartado (antipatrón; infla y ralentiza PostgreSQL).

## Nota de numeración
Patrón de 3 dígitos por consistencia con ADR-010/011; migración a 4 dígitos registrada como D-004.

## Historial de versiones
| Versión | Fecha | Autor | Cambios |
|---------|-------|-------|---------|
| 1.0 | 2026-07-02 | CPTO | Stack canónico confirmado; edge (Cloudflare), blobs (MinIO/R2), colas (BullMQ). |
