# mindOS — Product Requirements Document (PRD)

> **Documento #01 de la cadena documental.**
> Deriva del [Vision & Problem Statement (#00)](../00-foundation/vision-and-problem-statement.md).
> Define **QUÉ debe hacer el producto**. No define *cómo* se construye (eso es
> el Technical Architecture Document #02).

| Metadato | Valor |
|----------|-------|
| Versión | 0.1 (borrador para revisión) |
| Estado | 🟡 En revisión |
| Autor | Founder + CTO |
| Depende de | #00 Vision & Problem Statement |
| Última actualización | 2026-07-01 |

---

## 0. Propósito y alcance de este documento

Este PRD define el comportamiento del producto para su **primera versión
completa y utilizable (MVP)**, y establece el marco de features que guiará las
fases posteriores.

Un PRD no es una lista de deseos. Es un instrumento de **enfoque**: define con
igual rigor lo que el producto **hará** y lo que **no hará** en esta fase.

### Principio de alcance
Construimos **un solo bucle de valor, completo y pulido**, antes de añadir
amplitud. Es preferible que mindOS haga una cosa de forma memorablemente buena
a que haga diez cosas de forma mediocre.

---

## 1. Decisiones de producto fundacionales (con estado)

Estas decisiones cierran preguntas abiertas del documento #00. Cada una está
marcada con su nivel de firmeza.

| # | Decisión | Valor | Firmeza |
|---|----------|-------|---------|
| D1 | Superficie primaria del MVP | Web app (desktop-primary, responsive) + captura móvil vía PWA | 🟠 Decisión de CTO, sujeta a veto |
| D2 | Bucle de valor del MVP | Capturar → Comprender → Recuperar valor | 🟢 Firme (deriva de #00) |
| D3 | Manifestación del valor | "Daily Briefing" proactivo + recuperación contextual | 🟠 Decisión de CTO, sujeta a veto |
| D4 | Fuentes de datos del MVP | Captura manual (texto + voz) + integración de calendario | 🟠 Decisión de CTO, sujeta a veto |
| D5 | Modalidad primaria del MVP | GUI + conversacional (texto); voz solo para captura | 🟠 Decisión de CTO, sujeta a veto |
| D6 | Modelo de IA | Terceros (LLM vía API) en MVP; evaluación de modelos propios post-MVP | 🟠 Decisión de CTO, se detalla en #02 |

> **Nota del CTO:** las decisiones 🟠 son las que más impactan el producto y el
> presupuesto. Si vetas alguna, se recalibra el MVP completo antes de avanzar a
> arquitectura.

---

## 2. El bucle de valor central

Todo el MVP existe para demostrar, de principio a fin, este bucle:

```
   ┌──────────────┐     ┌──────────────┐     ┌──────────────────┐
   │  1. CAPTURAR │ ──► │ 2. COMPRENDER│ ──► │ 3. RECUPERAR     │
   │              │     │              │     │    VALOR         │
   │ El usuario   │     │ mindOS       │     │ mindOS devuelve  │
   │ vuelca info  │     │ conecta la   │     │ lo correcto en   │
   │ sin fricción │     │ info al grafo│     │ el momento       │
   │              │     │ y la entiende│     │ correcto         │
   └──────────────┘     └──────────────┘     └──────────────────┘
          ▲                                            │
          └────────────────────────────────────────────┘
                    El valor recuperado motiva
                    más captura (bucle virtuoso)
```

Si este bucle no genera un momento de "esto me entiende" en la primera semana,
el producto ha fallado, independientemente de cuántas features tenga.

---

## 3. Personas (derivadas del usuario objetivo #00)

### Persona primaria — "El Optimizador"
- **Nombre de trabajo:** Alex, 34, Product Manager / consultor / founder.
- **Contexto:** 4 proyectos activos, 8-10 apps diarias, 45 min/día
  "administrando" su sistema.
- **Objetivo con mindOS:** empezar cada día sabiendo exactamente qué importa,
  sin reconstruir el contexto manualmente.
- **Frustración previa:** ha probado Notion, Todoist, Mem, Reflect. Ninguno
  "conecta todo" ni le ahorra la carga de decidir qué mirar.

### Persona secundaria (no es foco de diseño del MVP)
- Estudiante avanzado / investigador. Se atiende solo si no añade complejidad.

---

## 4. Requisitos funcionales por pilar

Los requisitos se organizan según los 3 pilares de diferenciación del #00.
Notación: **[MVP]** = obligatorio para la primera versión; **[V2]** = fase
posterior.

### Pilar 1 — Memoria contextual persistente (Captura + almacenamiento)

| ID | Requisito | Fase |
|----|-----------|------|
| FR-1.1 | El usuario puede capturar una nota de texto en menos de 3 segundos desde cualquier superficie. | [MVP] |
| FR-1.2 | El usuario puede capturar por voz (dictado) que se transcribe a texto. | [MVP] |
| FR-1.3 | Cada captura se almacena como un "nodo" en el grafo de conocimiento personal, con timestamp y origen. | [MVP] |
| FR-1.4 | El usuario NO está obligado a elegir carpeta, tag ni categoría al capturar. | [MVP] |
| FR-1.5 | El usuario puede capturar desde móvil (PWA) y ver la info reflejada en escritorio. | [MVP] |
| FR-1.6 | El usuario puede adjuntar archivos/imágenes a una captura. | [V2] |
| FR-1.7 | Captura pasiva desde integraciones (email, mensajería). | [V2] |

### Pilar 2 — Comprensión relacional (Procesamiento + conexión)

| ID | Requisito | Fase |
|----|-----------|------|
| FR-2.1 | mindOS extrae automáticamente entidades de cada captura (personas, proyectos, fechas, tareas, temas). | [MVP] |
| FR-2.2 | mindOS conecta automáticamente cada captura con nodos existentes relacionados. | [MVP] |
| FR-2.3 | mindOS distingue tipos de nodo: nota, tarea, persona, proyecto, evento, decisión. | [MVP] |
| FR-2.4 | El usuario puede ver y corregir las conexiones que mindOS propone (feedback loop). | [MVP] |
| FR-2.5 | mindOS resuelve referencias temporales ("mañana", "el jueves") a fechas concretas. | [MVP] |
| FR-2.6 | mindOS detecta duplicados y propone fusionar nodos. | [V2] |
| FR-2.7 | El usuario puede explorar el grafo visualmente. | [V2] |

### Pilar 3 — Proactividad contextual (Recuperación de valor)

| ID | Requisito | Fase |
|----|-----------|------|
| FR-3.1 | mindOS genera un "Daily Briefing": un resumen proactivo al inicio del día con lo que importa (tareas, eventos, compromisos, contexto relevante). | [MVP] |
| FR-3.2 | El usuario puede preguntar en lenguaje natural sobre su propia información ("¿qué tengo pendiente con Ana?"). | [MVP] |
| FR-3.3 | mindOS responde consultas usando exclusivamente el contexto del usuario (no alucina información externa como si fuera del usuario). | [MVP] |
| FR-3.4 | El Daily Briefing prioriza en función del contexto (fechas límite, eventos próximos, proyectos activos). | [MVP] |
| FR-3.5 | El usuario puede marcar una sugerencia como útil / no útil (señal para métricas y mejora). | [MVP] |
| FR-3.6 | mindOS envía recordatorios proactivos según contexto (no solo por hora fija). | [V2] |
| FR-3.7 | mindOS sugiere acciones ("¿quieres que agende esto?") y las ejecuta con confirmación. | [V2] |

---

## 5. Requisitos transversales

| ID | Requisito | Fase |
|----|-----------|------|
| FR-X.1 | Autenticación segura del usuario (registro / login). | [MVP] |
| FR-X.2 | Toda la información del usuario es privada por defecto y cifrada en tránsito y en reposo. | [MVP] |
| FR-X.3 | El usuario puede exportar todos sus datos (evitar lock-in; refuerza confianza). | [MVP] |
| FR-X.4 | El usuario puede eliminar permanentemente su cuenta y todos sus datos. | [MVP] |
| FR-X.5 | El sistema registra la procedencia de cada dato para trazabilidad. | [MVP] |

> **Nota del CTO sobre FR-X.3:** la exportación de datos parece contraintuitiva
> ("¿no aumenta el churn?"). Al contrario: reduce la barrera de entrada. El moat
> es el *conocimiento acumulado y las conexiones*, no el secuestro de datos. La
> confianza es requisito de entrada (principio de producto #5).

---

## 6. Recorridos de usuario clave (MVP)

### Journey A — Primera captura (activación)
1. Alex se registra y ve una pantalla de captura vacía con un prompt claro.
2. Escribe: *"Reunión con Ana el jueves para revisar el pitch de inversión;
   me debe el deck actualizado."*
3. mindOS confirma la captura y, en segundo plano, extrae: persona (Ana),
   evento (reunión, jueves), proyecto (pitch de inversión), tarea pendiente
   (Ana debe el deck).
4. Alex ve cómo mindOS conectó automáticamente esos elementos.
   **Momento clave de activación:** "no tuve que organizar nada y ya lo entendió".

### Journey B — Daily Briefing (valor recurrente)
1. Al inicio del día, Alex abre mindOS (o recibe el briefing).
2. mindOS presenta: eventos de hoy, tareas prioritarias, compromisos
   pendientes de personas, y contexto relevante de proyectos activos.
3. Alex sabe en 30 segundos qué importa hoy, sin haber reconstruido nada.
   **Momento clave de retención:** "esto me ahorró mi ritual de 45 minutos".

### Journey C — Consulta contextual
1. Antes de una reunión, Alex pregunta: *"¿qué tengo pendiente con Ana?"*
2. mindOS responde con los compromisos, el deck pendiente y la última
   interacción registrada.
   **Momento clave de confianza:** "me devolvió exactamente lo que necesitaba".

---

## 7. Fuera de alcance (Non-goals del MVP)

Documentar lo que NO haremos es tan importante como lo que sí. Para el MVP,
mindOS **no**:

- No gestiona finanzas.
- No es una app de notas con edición rica (documentos largos, wikis).
- No ofrece colaboración multiusuario ni compartición.
- No integra múltiples fuentes externas (solo calendario en MVP).
- No tiene app nativa iOS/Android (PWA en su lugar).
- No ejecuta acciones autónomas sin confirmación.
- No ofrece visualización de grafo (llega en V2).
- No soporta equipos ni espacios de trabajo compartidos.

> Cada uno de estos es un producto o una fase entera. Añadirlos al MVP
> garantizaría no terminar nada bien.

---

## 8. Métricas de éxito (refinadas desde #00)

### North Star Metric
**Interacciones de valor por usuario activo por semana (IVU/sem):**
número de veces por semana que el usuario (a) acepta/marca como útil una
sugerencia proactiva, o (b) obtiene una respuesta útil a una consulta
contextual.

> Refinamiento respecto al #00: es medible desde el día uno vía FR-3.5 y el log
> de consultas resueltas, y captura *valor entregado*, no actividad.

### Métrica de activación
% de usuarios nuevos que completan el bucle completo (captura → ver conexión
automática → recibir su primer Daily Briefing útil) en los primeros 7 días.

### Métricas de retención y moat
- **Retención D30 / D90.**
- **Densidad del grafo** (nodos + relaciones por usuario en el tiempo) — proxy
  del switching cost.
- **Tasa de aceptación de sugerencias proactivas** (de FR-3.5).

### Anti-métricas (lo que NO celebramos)
- Número de notas creadas (vanidad).
- Tiempo en la app (más tiempo administrando ≠ mejor; buscamos lo contrario).

---

## 9. Criterios de aceptación del MVP

El MVP se considera listo para usuarios reales cuando:

1. Un usuario puede capturar por texto y voz sin fricción (FR-1.1, FR-1.2).
2. mindOS extrae entidades y conecta nodos automáticamente con precisión
   aceptable (FR-2.1, FR-2.2) — umbral de calidad a definir con datos reales.
3. El Daily Briefing se genera y es percibido como útil por una mayoría de
   usuarios de prueba (FR-3.1, FR-3.4).
4. La consulta contextual devuelve respuestas correctas basadas solo en el
   contexto del usuario (FR-3.2, FR-3.3).
5. Los requisitos de privacidad y seguridad transversales están implementados
   (FR-X.1 a FR-X.5).

---

## 10. Fases posteriores (visión de producto, no compromiso)

> El detalle y la secuencia real se definen en el **Roadmap Técnico (#08)**.
> Esto es solo la dirección de crecimiento.

- **V2 — Profundidad:** exploración visual del grafo, captura con archivos,
  detección de duplicados, recordatorios proactivos, acciones con confirmación.
- **V3 — Amplitud:** más integraciones (email, mensajería, gestores de tareas),
  captura pasiva.
- **V4 — Dominios de vida:** finanzas, salud, relaciones — cada uno como módulo
  sobre el mismo núcleo.
- **V5 — Autonomía:** el sistema actúa proactivamente por el usuario dentro de
  límites definidos por él.

---

## 11. Preguntas abiertas (para resolver antes o durante #02)

1. ¿Qué proveedor de calendario integramos primero (Google, Microsoft)? — se
   confirmará según el mercado objetivo.
2. ¿Qué umbral de precisión de extracción/conexión (FR-2.1, FR-2.2) es
   aceptable para lanzar? — requiere datos empíricos.
3. ¿El Daily Briefing es push (notificación/email) o pull (al abrir)? — afecta
   la arquitectura de notificaciones (#02).
4. ¿Qué LLM/proveedor de IA concreto? — decisión de arquitectura (#02) según
   costo, latencia, privacidad.

---

## Historial de versiones

| Versión | Fecha | Autor | Cambios |
|---------|-------|-------|---------|
| 0.1 | 2026-07-01 | Founder + CTO | Borrador inicial. Define bucle de valor, decisiones fundacionales de MVP, requisitos funcionales por pilar, non-goals, métricas y criterios de aceptación. |
