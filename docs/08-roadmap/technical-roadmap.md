# mindOS — Roadmap Técnico

> **Documento #08 de la cadena documental.** El último de la fundación.
> Integra todo lo anterior (#00–#07) en una **secuencia de construcción por
> fases**. Responde: *¿qué construimos primero, segundo, tercero, y por qué?*

> **⚠️ Revisado por [ADR-010](../02-architecture/adr/ADR-010-final-stack-and-two-backends.md) (2026-07-01).** El stack y las fases F0–F1 se actualizan a **mobile-first con dos backends** (NestJS de negocio + Python/FastAPI de IA) y **auth JWT propia**. Las menciones originales a "FastAPI único", "frontend React", "PWA" y "auth vía proveedor gestionado" quedan superadas por ese ADR. La Definición de Hecho de F0 se refina en [ADR-011](../02-architecture/adr/ADR-011-f0-definition-of-done-and-infra.md) (aceptado).

| Metadato | Valor |
|----------|-------|
| Versión | 0.3 |
| Estado | 🟢 Aprobado |
| Autor | CTO |
| Depende de | #00–#07 (toda la cadena) |
| Última actualización | 2026-07-02 |

---

## 0. Propósito y filosofía

Este roadmap traduce la fundación documental en acción. No es un calendario con
fechas rígidas (las fechas mienten); es una **secuencia de hitos verificables**
donde cada fase entrega valor demostrable y reduce el riesgo más grande
pendiente.

> **Principio rector:** construir en el orden que **maximiza aprendizaje y
> minimiza riesgo**, no en el orden que parece más fácil. Primero lo que puede
> matar el proyecto; después lo que lo pule.

### Reglas del roadmap
1. Cada fase termina en algo **demostrable y probado**, no en "código a medias".
2. No se empieza una fase sin cerrar la anterior (salvo trabajo explícitamente
   paralelo).
3. El bucle de valor del PRD (**capturar → comprender → recuperar valor**) es la
   estrella polar: cada fase acerca a completarlo o pulirlo.
4. Nada de código sin que su documentación base esté aprobada (ya lo está: #00–#07).

---

## 1. Vista general de fases

| Fase | Nombre | Objetivo | Resultado demostrable |
|------|--------|----------|-----------------------|
| **F0** | Cimientos técnicos | Esqueleto del proyecto ejecutable | "Hello world" end-to-end desplegado |
| **F1** | Captura + persistencia | El usuario captura y no se pierde nada | Capturar texto/voz → se guarda como nodo |
| **F2** | Comprensión (el cerebro) | La IA extrae y conecta | Una captura genera entidades conectadas en el grafo |
| **F3** | Recuperación de valor | Cerrar el bucle | Daily Briefing + consulta contextual funcionando |
| **F4** | Cuenta, privacidad y pulido | Listo para usuarios reales | Auth, export/borrado, feedback, endurecimiento |
| **F5** | Beta cerrada | Validar con usuarios reales | Métricas de activación/retención reales |

> F0→F3 construyen el bucle de valor completo. F4 lo hace seguro y usable. F5 lo
> pone frente a usuarios para validar la hipótesis del #00.

---

## 2. Detalle por fase

### F0 — Cimientos técnicos
**Objetivo:** que exista un esqueleto ejecutable y desplegable, sin lógica de
producto todavía. Elimina el riesgo de integración temprano.

- Monorepo con la estructura del #05 (backend, frontend, docs).
- Backend de negocio **NestJS** mínimo (healthcheck) + servicio de IA **Python/FastAPI** mínimo (healthcheck) + app móvil **Flutter** mínima (pantalla de salud). *[Actualizado por ADR-010]*
- PostgreSQL (+pgvector) y Redis levantados vía Docker Compose (local).
- CI (lint, tipos, tests) + CD a staging (#06) funcionando con un endpoint trivial.
- IaC inicial (#06) para staging.
- Base de **autenticación propia (JWT en NestJS)** en su forma más básica. *[Actualizado por ADR-010]*

**Hecho cuando (revisado por ADR-011, aceptado):** (1) CI verde en api/ai/mobile; (2) build y publicación de imágenes de contenedor de api y ai vía CI; (3) despliegue continuo a UN único entorno de staging (host/PaaS de contenedores simple, sin Kubernetes); (4) IaC mínima y declarativa de ese entorno. La infraestructura pesada (Kubernetes, prod aislado, IaC completa, observabilidad avanzada) se difiere a una fase pre-beta.

> *Estado real hoy: (1) cumplido; (2)(3)(4) pendientes. F0 ≈70%.*

**Riesgo que elimina:** integración de infraestructura y pipeline (el "no
compila en prod" tardío).

---

### F1 — Captura + persistencia
**Objetivo:** implementar el primer tercio del bucle de valor. Sagrado y rápido.

- `POST /v1/captures` (texto y voz transcrita) con `Idempotency-Key` (#04).
- Persistencia del nodo `Capture` (`status=raw`) en el modelo del #03.
- Autenticación real de usuarios (**registro/login/refresh con JWT propia en NestJS**, #07/ADR-010). *[Parcialmente implementada; pendiente de endurecer]*
- Superficie: pantalla de captura en la **app móvil Flutter** (#02/ADR-010).
- Aislamiento por usuario + RLS (#03) verificado.

**Hecho cuando:** un usuario autenticado captura por texto y voz desde la **app móvil**, y la captura persiste de forma aislada y segura, respondiendo en p95 <
300 ms (SLO #06).

**Riesgo que elimina:** que la captura sin fricción (requisito central del PRD)
no sea realmente fluida.

---

### F2 — Comprensión (el cerebro / la IP)
**Objetivo:** el corazón de mindOS. La captura cruda se convierte en conocimiento
conectado. **Es la fase de mayor riesgo y mayor valor.**

- Cola de trabajos + workers async (#02 §6, #06).
- Capa `AIProvider` (ADR-07) integrada con el LLM externo elegido (P1, #07).
- Pipeline de comprensión: extracción de entidades → tipado de nodos →
  embeddings (pgvector) → linking (aristas) → resolución temporal (#03 §7-9).
- Resolución de entidades simple (#03 §8).
- Minimización de datos hacia el LLM (ADR-09, #07).
- `GET /nodes/{id}/connections` y feedback loop `PATCH /edges/{id}` (#04, FR-2.4).
- Eval set de calidad de extracción/linking en CI (#05 §6.1).

**Hecho cuando:** una captura como *"Reunión con Ana el jueves para el pitch; me
debe el deck"* genera automáticamente las entidades conectadas del ejemplo del
#03 §13, con calidad medida por el eval set por encima del umbral de aceptación
(#01 §9), y el usuario puede corregir conexiones.

**Riesgo que elimina:** el más grande de todos — que la comprensión no sea lo
bastante buena para que el producto "entienda". Si aquí falla, se itera antes de
seguir.

---

### F3 — Recuperación de valor (cerrar el bucle)
**Objetivo:** completar el bucle. El usuario recibe valor de vuelta.

- `GET /v1/briefing`: Daily Briefing con priorización temporal (FR-3.1/3.4).
- `POST /v1/query` con streaming SSE + citas de fuentes (FR-3.2/3.3, #04).
- RAG combinando búsqueda semántica + travesía de grafo (#03 §10).
- `POST /v1/feedback` (FR-3.5) — instrumentación de la North Star Metric (#01 §8).
- Superficie: vista de briefing + interfaz de consulta.

**Hecho cuando:** el usuario abre mindOS y recibe un briefing útil, pregunta
*"¿qué tengo pendiente con Ana?"* y obtiene una respuesta correcta que cita sus
fuentes del grafo, sin alucinar. **El bucle de valor del PRD queda cerrado.**

**Riesgo que elimina:** que el valor entregado no sea percibido como útil (se
mide con feedback real).

---

### F4 — Cuenta, privacidad y pulido
**Objetivo:** convertir un prototipo funcional en un producto seguro y usable por
extraños.

- Export total del grafo (FR-X.3) y borrado total de cuenta (FR-X.4), #07.
- Consentimiento explícito de procesamiento por IA en onboarding (#07).
- MFA para operaciones sensibles (#07 §4).
- Observabilidad completa: métricas, trazas, alertas, y **costo de LLM por
  usuario** (#06).
- Endurecimiento de seguridad (revisión del modelo de amenazas #07 §2).
- Pulido de UX del bucle completo; manejo de errores y estados de carga.
- Onboarding que lleva al usuario a su primer momento de valor rápido (#01 §6).

**Hecho cuando:** un usuario externo puede registrarse, usar el bucle completo,
gestionar y exportar/borrar sus datos, y el sistema es observable y seguro según
los estándares de #06/#07.

**Riesgo que elimina:** riesgos legales/de confianza y de abandono por fricción.

---

### F5 — Beta cerrada
**Objetivo:** validar la hipótesis del #00 con usuarios reales del perfil objetivo.

- Lanzamiento a un grupo reducido de "Optimizadores" (perfil #01) en
  Brasil/Latinoamérica (P2, #07).
- Medición de: **activación** (completar el bucle en 7 días), **retención D30**,
  **densidad del grafo**, **tasa de aceptación de sugerencias** y la **North
  Star** (interacciones de valor/semana) — todo del #01 §8.
- Ciclo de feedback rápido; iteración sobre calidad de comprensión y utilidad
  del briefing.

**Hecho cuando:** hay datos reales suficientes para decidir con evidencia si el
producto resuelve el problema (y por tanto si se invierte en crecer).

**Riesgo que elimina:** el riesgo final y mayor — construir algo que nadie
quiere. Aquí se valida o se pivota.

---

## 3. Qué NO está en este roadmap (y cuándo llega)

Coherente con los non-goals del PRD (#01 §7) y las fases V2+ del producto:

| Elemento | Fase futura |
|----------|-------------|
| Exploración visual del grafo | V2 (post-validación) |
| Integraciones (email, mensajería, más calendarios) | V2/V3 |
| Recordatorios proactivos y acciones con confirmación | V2 |
| Módulos de dominio de vida (finanzas, salud) | V4 |
| App nativa iOS/Android | Cuando los datos de uso lo justifiquen |
| Colaboración / multiusuario | Post-MVP |
| Modelos de IA propios | Cuando el grafo dé ventaja de entrenamiento (ADR-09) |
| Daily Briefing *push* (vs. pull) | Cuando se defina la arquitectura de notificaciones |

---

## 4. Dependencias críticas entre fases

```
F0 (cimientos)
   └─► F1 (captura) ──► F2 (comprensión) ──► F3 (valor) ──► F4 (pulido) ──► F5 (beta)
                              │
                              └─ mayor riesgo técnico: si la calidad de
                                 comprensión no alcanza el umbral, se itera
                                 aquí antes de invertir en F3+
```

- **F2 es el punto de no retorno del riesgo técnico.** Conviene una prueba de
  concepto temprana de la comprensión (aislada) incluso durante F1, para no
  descubrir tarde que el enfoque no rinde.
- F4 puede solaparse parcialmente con F3 (privacidad/observabilidad se van
  incorporando, no se dejan todas al final).

---

## 5. Definición de éxito de la fase de MVP (F0–F5)

El MVP es un éxito si, al final de F5:
1. El bucle de valor funciona de forma fiable (F1–F3).
2. La comprensión supera el umbral de calidad definido (#01 §9).
3. Los usuarios de la beta muestran **activación y retención** por encima de un
   mínimo que justifique seguir invirtiendo (umbrales a fijar con los primeros
   datos).
4. El producto cumple los estándares de seguridad y privacidad del #07.

> Si (3) no se cumple, la decisión correcta no es "construir más features", sino
> **entender por qué** y ajustar producto o hipótesis. El roadmap sirve al
> aprendizaje, no al revés.

---

## 6. Siguiente paso inmediato (tras aprobar este documento)

Con la fundación documental completa (#00–#08 aprobados), el siguiente paso es
**iniciar F0**: crear el esqueleto del monorepo y el pipeline CI/CD.

> Este es el punto donde, por primera vez, escribimos código de producción — y
> lo hacemos sobre una base de ingeniería de nivel profesional.

---

## 7. Preguntas abiertas

1. ¿Se hace una PoC aislada de comprensión (F2) en paralelo a F1 para de-riesgar
   antes? (Recomendación del CTO: sí.)
2. Umbrales concretos de activación/retención para declarar éxito de la beta →
   se fijan con los primeros datos reales.
3. Tamaño y criterios de selección del grupo de beta cerrada (F5).

---

## Historial de versiones

| Versión | Fecha | Autor | Cambios |
|---------|-------|-------|---------|
| 0.1 | 2026-07-01 | CTO | Borrador inicial. Secuencia de fases F0–F5 orientada a riesgo y aprendizaje, con resultados demostrables, dependencias críticas, qué queda fuera del MVP, definición de éxito y siguiente paso (iniciar F0). |
| 0.2 | 2026-07-02 | CPTO | Cabecera de supersesión (ADR-010). Corrección de deriva en F0/F1 (stack de dos backends, auth JWT propia, superficie Flutter). Nota de refinamiento de la DoD de F0 (ADR-011). |
| 0.3 | 2026-07-02 | CPTO | DoD de F0 actualizada por ADR-011 (aceptado): CD mínimo + diferimiento de infra pesada. |
