# mindOS — Vision & Problem Statement

> **Documento fundacional del proyecto.**
> Este es el documento #00 de la cadena documental. Todos los documentos
> posteriores (PRD, arquitectura, modelo de datos, roadmap) derivan de aquí.

| Metadato | Valor |
|----------|-------|
| Versión | 0.1 (borrador para revisión) |
| Estado | 🟡 En revisión |
| Autor | Founder + CTO |
| Última actualización | 2026-07-01 |

---

## 0. Propósito de este documento

Este documento define, con precisión, **qué problema resuelve mindOS, para
quién, y por qué es fundamentalmente distinto de todo lo existente.**

No define features (eso es el PRD). No define tecnología (eso es la
arquitectura). Define la hipótesis central del producto sobre la que se
construirá todo lo demás. Si esta hipótesis está mal, todo lo que venga
después heredará el error.

---

## 1. Problema central

Las personas toman cientos de decisiones cada día, la mayoría sin el contexto
suficiente para tomarlas bien. Su información relevante —lo que saben, lo que
deben hacer, con quién se comprometieron, qué aprendieron, qué les importa—
está dispersa entre decenas de aplicaciones, conversaciones, documentos y su
propia memoria.

Ninguna herramienta existente conecta **lo que sabes**, con **lo que
necesitas**, con **lo que deberías hacer ahora**.

El resultado es una carga cognitiva permanente: recordar, organizar, priorizar
y decidir sin descanso. Esa carga produce:

- Decisiones de menor calidad.
- Oportunidades perdidas.
- Olvidos y compromisos incumplidos.
- Procrastinación y estrés.
- La sensación crónica de no tener el control de la propia vida.

### Evidencia del problema

- **Teoría de carga cognitiva** (Sweller): la memoria de trabajo humana tiene
  capacidad limitada; sobrecargarla degrada el rendimiento y la toma de
  decisiones.
- **Fatiga de decisión** (Baumeister): la calidad de las decisiones se
  deteriora tras una secuencia prolongada de decisiones.
- **Fragmentación de herramientas**: el knowledge worker promedio alterna
  entre múltiples aplicaciones al día para gestionar trabajo y vida personal,
  sin una capa que unifique el contexto entre ellas.

### Por qué las soluciones actuales son insuficientes

Las herramientas actuales (gestores de notas, tareas, calendarios, apps de
finanzas) son **contenedores pasivos**. Almacenan lo que el usuario decide
guardar, donde el usuario decide guardarlo, y solo devuelven lo que el usuario
recuerda buscar. Trasladan el trabajo cognitivo de vuelta al usuario en lugar
de asumirlo.

### Formulación del problema

> mindOS resuelve la fragmentación del contexto personal construyendo una capa
> de inteligencia que unifica la información del usuario, comprende su contexto
> completo y le ayuda a tomar mejores decisiones con menos esfuerzo mental.

> **Nota de posicionamiento:** evitamos deliberadamente la metáfora saturada de
> "segundo cerebro" como eje de marketing. El concepto guía internamente el
> diseño, pero el posicionamiento externo es el de una **capa de inteligencia
> personal** —un concepto técnicamente implementable y verificable— que
> evoluciona hasta convertirse en un verdadero sistema operativo personal.

---

## 2. Usuario objetivo

### Perfil primario

Knowledge worker de **28-40 años** con ingresos medios-altos, en roles que
exigen gestión de información compleja: founders, consultores, product
managers, ingenieros senior, creadores de contenido, investigadores.

### Contexto de uso

- Gestiona 3-5 proyectos simultáneos (profesionales y personales).
- Usa entre 5 y 12 aplicaciones diariamente.
- Dedica entre 30 y 60 minutos al día a "administrar" su sistema: revisar
  tareas, organizar notas, actualizar calendarios.

### Momento de dolor principal

El **inicio del día** o la **transición entre proyectos** — cuando necesita
reunir contexto disperso para decidir qué hacer ahora. Es en ese momento donde
mindOS debe demostrar su valor primero.

### Willingness-to-pay

15-30 USD/mes. Ya paga por herramientas de productividad (Notion, Todoist,
Superhuman y similares).

### Perfil psicográfico

**Optimizador compulsivo.** Prueba herramientas nuevas constantemente. Siente
frustración porque ninguna "lo conecta todo". Le atrae la promesa de la IA
pero ha sido decepcionado por implementaciones superficiales.

### Distinción clave: quién usa vs. quién paga

Diseñamos para el segmento que **usa y paga** desde el día uno (el profesional
de 30-40 con ingresos altos), no para el que solo usa sin pagar. El modelo de
negocio se ancla en este perfil.

### Expansión futura (no es el foco inicial)

Estudiantes avanzados, equipos pequeños, y verticales profesionales (legal,
médico, consultoría) son mercados de expansión posteriores. **No** se diseña
para ellos en la fase inicial.

---

## 3. Visión del producto

> **Visión a 10 años:** mindOS es el sistema operativo personal con IA más
> inteligente del mundo — una capa de inteligencia que comprende, recuerda,
> organiza, conecta y actúa por el usuario, evolucionando con él a lo largo de
> toda su vida.

### Qué es mindOS

Un **motor de contexto e inteligencia personal**: un núcleo agnóstico a
dispositivo que construye y mantiene un modelo vivo del usuario, y le sirve la
información y las decisiones correctas en el momento correcto.

### Qué NO es mindOS

- **No** es una app de tareas.
- **No** es una app de notas.
- **No** es una agenda o calendario.
- **No** es un chatbot con una base de datos detrás.
- **No** es un clon de Notion con IA añadida.
- **No** es un contenedor pasivo de información.

---

## 4. Principios de producto (no negociables)

1. **El cerebro es el producto, no la interfaz.** El activo central es el
   modelo de contexto del usuario, no ninguna pantalla ni modalidad.
2. **Reducir carga cognitiva, siempre.** Toda decisión de diseño se evalúa por
   cuánta carga mental elimina del usuario. Si añade carga, se descarta.
3. **Proactivo por defecto, no reactivo.** mindOS ofrece antes de que se le
   pregunte. La consulta manual es el último recurso, no el primero.
4. **El contexto se conecta solo.** El usuario no organiza manualmente (sin
   folders obligatorios, sin tags manuales). El sistema conecta.
5. **La privacidad es un derecho, no una función.** El modelo de datos más
   íntimo de una persona exige el estándar de privacidad más alto. No es
   negociable ni monetizable a costa del usuario.

---

## 5. Diferenciación fundamental

Las herramientas existentes son **contenedores pasivos**. mindOS invierte esa
dinámica mediante tres pilares verificables:

### Pilar 1 — Memoria contextual persistente
mindOS recuerda todo lo que el usuario le comparte y lo conecta automáticamente
en un grafo de conocimiento personal. Sin folders, sin tags manuales, sin
"¿dónde guardé esto?".

### Pilar 2 — Comprensión relacional
mindOS no almacena datos aislados. Comprende relaciones: *"esta tarea está
conectada con este proyecto, que depende de esta persona, con quien tienes una
reunión pendiente el jueves"*.

### Pilar 3 — Proactividad contextual
mindOS no espera preguntas. Entrega la información correcta en el momento
correcto según el contexto actual del usuario (hora, ubicación, calendario,
proyecto activo, estado declarado).

### Moat (barrera defensiva)

- **Moat de switching cost:** el grafo de conocimiento personal se vuelve más
  valioso con cada interacción. Tras 90 días de uso, mindOS comprende al
  usuario mejor que cualquier alternativa recién instalada. El costo de cambio
  es el conocimiento acumulado, no el formato de los datos.
- **Moat de datos (network effect indirecto):** con escala y respetando la
  privacidad, los patrones agregados mejoran la comprensión contextual para
  usuarios con perfiles similares.

---

## 6. Estrategia de plataforma — Core-first

mindOS **no se diseña alrededor de un dispositivo ni de una modalidad.** Se
diseña alrededor de un núcleo.

### Arquitectura conceptual

```
                    ┌──────────────────────────────┐
                    │          NÚCLEO (Core)        │
                    │   Motor de Contexto e IA      │
                    │   - Grafo de conocimiento     │
                    │   - Motor de comprensión      │
                    │   - Motor de proactividad     │
                    │                               │
                    │  *** El sistema operativo     │
                    │      real vive aquí ***       │
                    │  Agnóstico a dispositivo y    │
                    │  modalidad                    │
                    └──────────────────────────────┘
                                   │
              ┌────────────────────┼────────────────────┐
              ▼                    ▼                    ▼
      ┌──────────────┐    ┌──────────────┐    ┌──────────────┐
      │  SUPERFICIE  │    │  SUPERFICIE  │    │  SUPERFICIE  │
      │    Móvil     │    │  Escritorio  │    │   Ambient    │
      │              │    │              │    │ voz/wearable/│
      │ Captura +    │    │ Análisis +   │    │  API/auto    │
      │ consulta     │    │ creación     │    │              │
      │ rápida       │    │ profunda     │    │ Captura      │
      │              │    │              │    │ pasiva       │
      └──────────────┘    └──────────────┘    └──────────────┘
              │                    │                    │
              └────────────────────┼────────────────────┘
                                   ▼
              ┌────────────────────────────────────────┐
              │      MODALIDADES (transversales)         │
              │  - Conversacional (texto)                │
              │  - Voz                                   │
              │  - Manipulación directa (GUI)            │
              │  - Comandos                              │
              │  Disponibles en TODAS las superficies    │
              │  según convenga a la tarea               │
              └────────────────────────────────────────┘
```

### Principio rector

> No construimos para un dispositivo ni para una modalidad. Construimos un
> cerebro. Las **superficies** son ventanas hacia ese cerebro; las
> **modalidades** son puertas de entrada. El cerebro es el producto.

### Superficies (adaptativas)

- **Móvil** — captura instantánea y consulta rápida. Siempre presente.
- **Escritorio** — exploración, análisis y creación profunda. Espacio para
  navegar el grafo.
- **Ambient** — voz, wearables, API e integraciones. Captura pasiva y acceso
  sin fricción.

### Modalidades (transversales)

Conversacional, voz, GUI y comandos están disponibles en todas las
superficies. mindOS ofrece o selecciona la modalidad óptima según la tarea.

> **Corrección de concepto clave:** la conversación **no** es el sistema
> operativo. Es una modalidad de entrada/salida de bajo ancho de banda,
> excelente para captura y consultas puntuales, pero inadecuada como interfaz
> única para exploración compleja, comparación de opciones o vista panorámica.
> El sistema operativo real es el núcleo de contexto.

### Consecuencia pragmática (adelanto para el roadmap)

Aunque la visión es multi-superficie, **no se construyen las tres superficies a
la vez.** Secuencia inicial:

1. **Núcleo primero** — el motor de contexto. Sin esto, nada tiene sentido.
2. **Una superficie primaria para el MVP** — probablemente captura móvil + una
   interfaz web (visual + conversacional) que demuestre el bucle completo:
   **capturar → comprender → recuperar valor.**

Esto se formalizará en el Roadmap Técnico (documento #08).

---

## 7. Métricas de éxito

### North Star Metric (hipótesis inicial)
**Decisiones asistidas con valor percibido por semana** por usuario activo:
cuántas veces por semana mindOS entregó información o una recomendación que el
usuario reconoció como útil en el momento.

> Se refinará al construir el PRD. La intención es medir *valor entregado*, no
> *actividad* (evitar métricas de vanidad como "notas creadas").

### Métricas proxy para fases tempranas
- **Retención D30 / D90** — ¿el usuario sigue tras el punto donde el grafo se
  vuelve valioso?
- **Densidad del grafo de contexto** — nodos y relaciones por usuario a lo
  largo del tiempo (proxy del moat de switching cost).
- **Tasa de aceptación de sugerencias proactivas** — % de sugerencias que el
  usuario acepta o marca como útiles.
- **Tiempo diario ahorrado en "administración"** — reducción del tiempo que el
  usuario dedica a organizar manualmente su información.

### Señal de que resolvimos el problema
El usuario reporta menor carga mental y mayor confianza en sus decisiones, y su
retención a largo plazo lo confirma con comportamiento, no solo con encuestas.

---

## 8. Restricciones y supuestos

### Supuestos de mercado
- Existe un segmento dispuesto a pagar 15-30 USD/mes por una capa de
  inteligencia personal, distinta de las herramientas de organización actuales.
- La confianza y la privacidad son requisitos de entrada, no diferenciadores
  opcionales, dado el nivel de intimidad de los datos.

### Restricciones técnicas conocidas
- La comprensión contextual depende de modelos de IA cuyo costo, latencia y
  fiabilidad deben gestionarse deliberadamente.
- El grafo de conocimiento personal debe escalar por usuario y mantener
  rendimiento de consulta a medida que crece durante años.
- La proactividad exige procesamiento de contexto en tiempo real con un balance
  cuidadoso entre utilidad e intrusión.

### Restricciones de recursos
- Se prioriza construir el núcleo correctamente sobre lanzar múltiples
  superficies rápido.
- El MVP se enfoca en una sola superficie primaria para validar el bucle de
  valor antes de expandir.

---

## 9. Preguntas abiertas (a resolver en documentos posteriores)

1. ¿Cuál es exactamente la superficie primaria del MVP? (Roadmap #08)
2. ¿Qué fuentes de datos integramos primero para poblar el grafo? (PRD #01)
3. ¿Modelo de IA propio, de terceros, o híbrido? (Arquitectura #02)
4. ¿Cuál es la definición precisa del North Star Metric? (PRD #01)
5. ¿Qué garantías de privacidad concretas ofrecemos y cómo las verificamos?
   (Security & Privacy Framework #07)

---

## Historial de versiones

| Versión | Fecha | Autor | Cambios |
|---------|-------|-------|---------|
| 0.1 | 2026-07-01 | Founder + CTO | Borrador inicial para revisión. Consolida problema, usuario, visión, diferenciación y estrategia de plataforma Core-first. |
