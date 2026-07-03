# Guía de anotación del eval set (F2 — de-riesgo R-001)

Esta guía fija la **convención de anotación** del gold del examen de
comprensión. Su objetivo es que **todo el gold sea consistente y defendible**:
dos personas que anoten el mismo texto siguiendo estas reglas deben llegar al
mismo resultado. El gold es **verdad anotada a mano juzgando el TEXTO**, con
criterio independiente — **nunca** se ajusta para que un proveedor concreto
acierte (design §13.1, [EVAL.md](../../../EVAL.md)).

Estas reglas son **coherentes con el prompt de extracción** (`EXTRACTION_PROMPT_V3`
en `app/understanding/extract.py`): el gold y el prompt describen la misma
convención, para que el examen mida comprensión y no un desajuste de criterios.

> El formato exacto del archivo `case-*.json` (campos, tipos permitidos) está en
> [`README.md`](./README.md). Esta guía cubre el **criterio semántico**: qué se
> anota y cómo.

## Regla de oro: solo lo EXPLÍCITO

Anota únicamente lo que está **literalmente** en el texto. No infieras, no
completes patrones, no añadas conocimiento externo. **Ante la duda, OMITE**: un
ítem que falta es mucho mejor que uno inventado. Para cada ítem anotado debes
poder señalar la(s) palabra(s) del texto que lo justifican.

## Tipos de entidad

### `person` — humano con nombre propio
- Se anota **solo el nombre propio** de una persona (p. ej. `Marcos`, `Ana`,
  `Dr. Nguyen`).
- **NO** son persona: cargos o roles (`el jefe`, `el cliente`, `el dentista`),
  pronombres (`él`, `ellos`), referencias genéricas (`alguien`, `el equipo`,
  `the folks`), ni relaciones de parentesco sin nombre (`mamá`, `mi hermana`,
  `la abuela`). Si aparece el nombre propio junto a la relación, anota el nombre
  (`mi hermana Laura` → `Laura`).
- **Nombres propios que NO son humanos** (mascotas, marcas, empresas) **no** son
  `person`. Una mascota con nombre (`Toby, el perro`) se OMITE (no encaja en la
  taxonomía); una empresa/marca se OMITE salvo que sea un `project` del autor.

### `project` — iniciativa/producto con nombre, SOLO el nombre
- Se anota el **nombre propio** de la iniciativa, **sin** la palabra
  `proyecto`/`project`: `proyecto Aurora` → `Aurora`, `project Titan` → `Titan`.

### `event` — referencia temporal explícita
- Se anota solo cuando hay una **marca temporal concreta**: fecha (`15 de
  marzo`), día de la semana (`lunes`, `Friday`), hora de reloj (`3pm`, `9 de la
  mañana`), o expresiones temporales estándar (`mañana`/`tomorrow`, `hoy`,
  `la próxima semana`/`next week`).
- **NO** son evento: referencias vagas sin fecha/hora concreta (`antes del
  cierre`, `la fecha límite`, `pronto`/`soon`, `algún día`, `en algún momento`,
  `next sprint`), ni actividades genéricas.
- Una **reunión/cita/evento social** expresado como sustantivo común (`reunión`,
  `meeting`, `cita`, `congreso`, `cumpleaños`, `examen`, `demo`, `kickoff`,
  `standup`) se anota como **`topic`** (su núcleo temático), reservando `event`
  para la marca temporal asociada. Precedente: en case-06/case-11 `meeting` y
  `reunión` son `topic`, y el día/hora es el `event`.

### `topic` — materia/tema, núcleo canónico
- Se anota el **núcleo nominal canónico**: **minúscula, singular, sin artículos
  ni posesivos**. `el presupuesto` → `presupuesto`; `la salud` → `salud`;
  `the budgets` → `budget`.
- Un **tema compuesto se separa** en varios topics, un concepto por topic:
  `marketing budget` → `marketing` + `budget`; `the marketing plan` →
  `marketing` + `plan`; `financial model` → `financial` + `model`.
- **Materia vs. objeto físico:** los `topic` son **materia/asunto** (trabajo,
  finanzas, ideas): `informe`, `factura`, `contrato`, `presupuesto`, `diseño`,
  `salud`, `aumento`. Los **objetos físicos concretos** de un recado NO son
  topic (`leche`/`milk`, `huevos`/`eggs`, `pan`, `pilas`, `dinero`/`plata`);
  precedente: en case-10 `buy milk and eggs` no anota topics.
- Los **lugares** (`Madrid`, `la farmacia`) no encajan en la taxonomía y se
  OMITEN.

### `note` — reflexión/pensamiento de diario
- Pensamiento reflexivo que no es ninguno de los anteriores. En la práctica una
  reflexión suele aportar `topic`(s) (`salud`, `rutina`) y `tasks` vacío.

## `tasks` — acciones concretas que el autor pretende hacer
- Se anota cuando hay una **acción concreta a realizar**: imperativos, `hay
  que`, `tengo que`, `need to`, `TODO`, recordatorios, e **intenciones
  tentativas** (`quizás debería`, `should probably`, `might be worth`).
- La **etiqueta empieza en el VERBO de acción**, eliminando muletillas de apertura
  (`tengo que`, `hay que`, `need to`, `quizás debería`, `recordatorio:`,
  `acordate de`, `don't forget`) pero **conservando el resto de la cláusula**
  (objeto, persona, cuándo). Ej.: `Tengo que llamar a Ana mañana` →
  `llamar a Ana mañana`.
- **NO** son tarea: hechos pasados, opiniones, la descripción de un evento ya
  agendado (`reunión el martes` describe un evento, no una acción), ni **ideas
  vagas sin intención concreta** (`estaría bien... algún día`).

## `connections` — relaciones respaldadas por el texto
- `assigned_to`: `source` = etiqueta **exacta** de la tarea, `target` = la
  persona con la que se relaciona/responsable, cuando el texto la nombra.
- `mentions`: co-ocurrencia ligera entre dos etiquetas (p. ej. un evento y una
  persona presente).
- `relates_to`: vínculo semántico genérico.
- Solo se anota una conexión si **ambos extremos** son etiquetas ya anotadas. Las
  conexiones son **diagnósticas** (no entran en la puerta de aceptación); ante la
  duda, se omiten.

## Casos difíciles (deben existir en el set)
Para una medición robusta, el set incluye a propósito: textos **sin nada
accionable** (mide que NO se invente), **solo tareas**, **solo personas/eventos**,
casos **muy densos** (muchas entidades), **ambiguos** (intención tentativa), y
con **referencias vagas que DEBEN omitirse** (`el cliente`, `la fecha límite`,
`el jefe`, `mamá`).

## Normalización al comparar
Los `label` se comparan **normalizados y de forma justa** (minúsculas, sin
acentos, sin artículos/prefijo `proyecto`, plural plegado): `Reunión` ≡
`reunion`, `el presupuesto` ≡ `presupuesto`, `proyecto Aurora` ≡ `Aurora`. Ver
`app/understanding/text_utils.py` (`normalize_label`, `labels_match`). Aun así,
**anota el label en su forma canónica** según esta guía; no dependas del matcher
para arreglar una anotación descuidada.
