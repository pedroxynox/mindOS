# mindOS — Infrastructure & Deployment Strategy

> **Documento #06 de la cadena documental.**
> Deriva del [TAD (#02)](../02-architecture/technical-architecture.md) y de los
> [Engineering Standards (#05)](../05-engineering/engineering-standards-and-conventions.md).
> Define **dónde vive mindOS, cómo se despliega, cómo se observa y cómo se
> recupera ante fallos.** No define políticas de seguridad/privacidad de datos
> (eso es #07).

| Metadato | Valor |
|----------|-------|
| Versión | 0.1 (borrador para revisión) |
| Estado | 🟡 En revisión |
| Autor | CTO |
| Depende de | #02 TAD, #05 Engineering Standards |
| Última actualización | 2026-07-01 |

---

## 0. Propósito

Define la infraestructura que ejecuta mindOS y el proceso que lleva el código
desde un commit hasta producción de forma segura, repetible y observable.

> **Principio rector:** infraestructura **simple, reproducible y portable.**
> Empezamos con lo mínimo que sea profesional, no con lo máximo que sea posible.
> Cada pieza de complejidad debe ganarse su lugar.

---

## 1. Entornos

| Entorno | Propósito | Datos |
|---------|-----------|-------|
| **local** | Desarrollo en la máquina del ingeniero (Docker Compose). | Sintéticos. |
| **staging** | Réplica de producción para validación pre-release. | Sintéticos / anonimizados. |
| **production** | Usuarios reales. | Reales (sujetos a #07). |

- Paridad dev/prod: mismos contenedores en todos los entornos (evita el
  "en mi máquina funciona").
- `main` siempre desplegable (#05); cada merge a `main` es candidato a release.

---

## 2. Empaquetado y ejecución

### ADR-I1 — Contenedores (Docker) como unidad de despliegue
- **Decisión:** todo componente (API, workers, frontend) se empaqueta en
  imágenes Docker.
- **Estado:** 🟢 Firme.
- **Por qué:** portabilidad total (evita lock-in de proveedor, principio del
  #02), paridad entre entornos y base para escalar horizontalmente.

### Componentes desplegables (del #02)
```
┌────────────┐   ┌────────────┐   ┌──────────────┐   ┌───────────────┐
│  frontend  │   │  api       │   │ ai-workers   │   │ scheduler      │
│  (estático │   │ (FastAPI)  │   │ (async pipe- │   │ (briefings,    │
│   / PWA)   │   │            │   │  line #02 §6)│   │  jobs periód.) │
└────────────┘   └────────────┘   └──────────────┘   └───────────────┘
        │              │                 │                   │
        └──────────────┴─────────────────┴───────────────────┘
                                │
        ┌───────────────────────────────────────────┐
        │ PostgreSQL (+pgvector)   Redis   Object St. │
        └───────────────────────────────────────────┘
```

- **api**: stateless → escala horizontal detrás de un balanceador.
- **ai-workers**: consumen la cola (Redis); escalan según profundidad de cola.
- **scheduler**: dispara la generación de briefings y trabajos periódicos.
- **frontend**: assets estáticos servidos por CDN.

---

## 3. Elección de proveedor cloud

### ADR-I2 — Plataforma gestionada sobre un cloud mayor, con portabilidad
- **Decisión:** desplegar sobre un **proveedor cloud mayor** usando **servicios
  gestionados** (BD, colas, cómputo de contenedores), manteniendo portabilidad
  vía Docker + IaC. Recomendación inicial: **AWS** (madurez, PostgreSQL
  gestionado con soporte pgvector, ecosistema).
- **Estado:** 🟠 Decisión de CTO, sujeta a veto.
- **Por qué:** los servicios gestionados (BD, caché, secretos, logs) eliminan
  trabajo operativo que un equipo pequeño no puede permitirse. Un cloud mayor
  ofrece el camino de escalado a millones sin migrar de casa.
- **Alternativas consideradas:**
  - *PaaS simplificado (Render/Fly/Railway):* excelente velocidad inicial y
    menor curva; **punto de reevaluación válido** si se prioriza time-to-market
    extremo en el MVP. Trade-off: menos control y posible migración futura.
  - *Kubernetes propio desde el día uno:* rechazado. Sobre-ingeniería para el
    MVP; complejidad operativa enorme sin equipo de plataforma.
- **Regla anti-lock-in:** favorecer servicios estándar (PostgreSQL, Redis,
  almacenamiento S3-compatible) sobre servicios propietarios difíciles de
  migrar, salvo justificación clara.

### Servicios gestionados objetivo (MVP)
| Necesidad | Servicio gestionado |
|-----------|---------------------|
| Cómputo de contenedores | Servicio de contenedores gestionado (ej. ECS/Fargate o equivalente). |
| Base de datos | PostgreSQL gestionado con pgvector. |
| Caché + colas | Redis gestionado. |
| Object storage | Almacenamiento S3-compatible. |
| Secretos | Gestor de secretos del proveedor. |
| CDN | CDN del proveedor para el frontend. |

---

## 4. Infraestructura como código (IaC)

### ADR-I3 — Toda la infraestructura se define como código
- **Decisión:** la infraestructura se declara con **Terraform** (o equivalente),
  versionada en el repositorio. Nada se crea a mano en la consola del cloud.
- **Estado:** 🟢 Firme.
- **Por qué:** reproducibilidad, revisión por PR (igual que el código, #05),
  recuperación ante desastres y trazabilidad de cambios de infraestructura.

---

## 5. CI/CD

Automatización sobre GitHub Actions (#05 §1), en dos pipelines:

### 5.1 Integración Continua (CI) — en cada PR
```
push/PR → lint (Ruff/ESLint) → type-check (mypy/tsc) → tests (unit + integración)
        → eval-set de IA (regresión de calidad, #05 §6.1) → build de imágenes
        → escaneo de secretos y dependencias
```
Ningún PR se mergea si el pipeline falla (gate obligatorio, Definition of Done #05 §9).

### 5.2 Despliegue Continuo (CD) — al mergear a `main`
```
merge a main → build + push de imágenes versionadas → deploy a staging
             → smoke tests en staging → aprobación → deploy a production
```

### ADR-I4 — Estrategia de despliegue: rolling con health checks (MVP)
- **Decisión:** despliegues **rolling** con health checks; migraciones de BD
  compatibles hacia atrás (expand/contract).
- **Estado:** 🟠 Decisión de CTO, sujeta a veto.
- **Por qué:** cero downtime con complejidad razonable. Blue/green o canary se
  adoptan cuando el volumen de usuarios lo justifique.
- **Migraciones:** versionadas (Alembic para el backend Python), siempre
  compatibles hacia atrás para permitir rollback sin pérdida.

---

## 6. Observabilidad

Tres pilares, desde el día uno (no como añadido posterior):

| Pilar | Qué | Uso |
|-------|-----|-----|
| **Logs** | Estructurados en JSON, con `request_id`/`user_id`, **sin PII sensible** (#05 §7). | Depuración, auditoría (con límites de #07). |
| **Métricas** | Latencia de API, profundidad de cola, tasa de error, y **costo de LLM por usuario** (métrica de primera clase, #02 §7). | Salud del sistema y del negocio. |
| **Trazas** | Distribuidas, correlacionadas por `X-Request-Id` a través de api → cola → workers → LLM. | Diagnóstico de flujos async. |

### Alertas mínimas (MVP)
- Tasa de error de API por encima de umbral.
- Cola de comprensión atascada (capturas sin procesar > N minutos).
- Costo de LLM anómalo (protección contra fugas de gasto).
- Salud de BD (conexiones, replicación, almacenamiento).

### SLOs iniciales (hipótesis, se refinan con datos)
- Disponibilidad de API: 99.9%.
- Captura (`POST /captures`) p95 < 300 ms (camino síncrono, ADR-02).
- Comprensión completada p95 < 30 s desde la captura.

---

## 7. Fiabilidad, backups y recuperación

- **Backups de PostgreSQL:** automáticos, diarios, con point-in-time recovery.
  Backups probados (un backup no verificado no es un backup).
- **RPO/RTO objetivo (MVP):** RPO ≤ 24h, RTO ≤ 4h. Se endurecen con la escala.
- **Idempotencia y reintentos:** los workers reprocesan sin duplicar (ADR-02 +
  `Idempotency-Key` #04). La captura cruda persistida garantiza no perder datos
  ante fallo del pipeline.
- **Degradación elegante:** si el LLM externo no responde, la captura se acepta
  igual (queda `raw`) y la comprensión se reintenta; el producto no se cae por
  una dependencia externa.

---

## 8. Escalado (camino a millones, sin construirlo hoy)

| Palanca | Cuándo |
|---------|--------|
| Escalar `api` horizontalmente | Ante aumento de tráfico (stateless, trivial). |
| Escalar `ai-workers` por profundidad de cola | Ante picos de captura. |
| Réplicas de lectura de PostgreSQL | Cuando las lecturas (briefings/consultas) dominen. |
| Particionado por `user_id` (#03 §11) | Cuando el volumen por tabla lo exija. |
| Vector DB dedicada (ADR-05) | Cuando pgvector no dé la latencia requerida. |
| Extracción de `ai-workers` a servicio propio (#02 §4) | Cuando su escalado difiera del resto. |

> Coherente con el principio del #02: **diseñado para escalar, no
> sobre-construido para escalar.** Cada palanca se acciona con datos, no por
> anticipación.

---

## 9. Gestión de costos

- El **costo del LLM** es el gasto dominante variable (ADR-09). Se monitorea por
  usuario y se protege con alertas.
- Entornos no productivos se apagan/reducen fuera de uso.
- IaC permite dimensionar recursos con precisión y evitar sobreaprovisionamiento.

---

## 10. Preguntas abiertas (para #07 e implementación)

1. Proveedor cloud definitivo (AWS vs. PaaS simplificado) → decisión final antes
   del scaffolding, según prioridad time-to-market vs. control.
2. Región(es) de despliegue y residencia de datos → depende de #07 y del mercado
   objetivo (privacidad/compliance).
3. Estrategia de notificaciones para el Daily Briefing **push** (pregunta abierta
   heredada de #01/#04) → define si se añade un servicio de notificaciones.
4. Herramienta concreta de observabilidad (stack propio vs. gestionado) →
   implementación.

---

## Historial de versiones

| Versión | Fecha | Autor | Cambios |
|---------|-------|-------|---------|
| 0.1 | 2026-07-01 | CTO | Borrador inicial. Entornos, contenedores (ADR-I1), elección de cloud gestionado con portabilidad (ADR-I2), IaC (ADR-I3), CI/CD y estrategia de despliegue rolling (ADR-I4), observabilidad (logs/métricas/trazas + SLOs), fiabilidad/backups/recuperación, escalado y gestión de costos. |
