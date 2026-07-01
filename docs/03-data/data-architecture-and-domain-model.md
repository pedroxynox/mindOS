# mindOS — Data Architecture & Domain Model

> **Documento #03 de la cadena documental.**
> Deriva del [TAD (#02)](../02-architecture/technical-architecture.md),
> del [PRD (#01)](../01-product/prd.md) y del [Vision (#00)](../00-foundation/vision-and-problem-statement.md).
> Define **el modelo de información central**: qué recuerda mindOS, cómo se
> estructura y cómo se conecta. No define los contratos de API (eso es #04).

| Metadato | Valor |
|----------|-------|
| Versión | 0.1 (borrador para revisión) |
| Estado | 🟡 En revisión |
| Autor | CTO |
| Depende de | #00 Vision, #01 PRD, #02 TAD |
| Última actualización | 2026-07-01 |

---

## 0. Propósito

Este es el plano del **cerebro** de mindOS. El grafo de conocimiento personal
es la IP defendible del producto (ADR-09): el modelo vivo del usuario que
ningún competidor puede copiar. Este documento define su estructura.

Todo lo demás —captura, comprensión, proactividad, consultas— existe para
**poblar, enriquecer y consultar este grafo.**

---

## 1. Principios de diseño del modelo

1. **Todo es un nodo; las conexiones son ciudadanos de primera clase.** El valor
   no está en los datos aislados, sino en las relaciones entre ellos (Pilar 2).
2. **La captura cruda nunca se pierde.** Cada dato estructurado deriva de una
   captura original que se preserva íntegra (trazabilidad + recuperación ante
   fallos del pipeline de IA, ADR-02).
3. **La IA propone; el usuario confirma.** Toda entidad o conexión derivada por
   IA lleva un nivel de confianza y puede ser corregida (FR-2.4).
4. **El grafo es temporal.** Cada nodo y arista tiene tiempo. La memoria del
   usuario tiene historia, no solo estado presente.
5. **Aislamiento absoluto por usuario.** Ningún dato cruza fronteras de usuario
   (RLS, ADR-04). `user_id` es obligatorio en toda entidad.
6. **Diseñado para durar 10 años por usuario.** Estructura, índices y estrategia
   de crecimiento pensados para grafos densos y longevos.

---

## 2. Modelo conceptual: grafo de propiedades (property graph)

mindOS se modela como un **property graph**: nodos tipados con atributos, unidos
por aristas tipadas y direccionales, también con atributos.

```
   (Person: "Ana")
        ▲
        │ ASSIGNED_TO
        │
   (Task: "Ana debe enviar el deck") ──BELONGS_TO──► (Project: "Pitch inversión")
        │                                                     ▲
        │ DERIVED_FROM                                        │ ABOUT
        ▼                                                     │
   (Capture: "Reunión con Ana el jueves...")           (Event: "Reunión jueves")
        │                                                     │
        └──────────────── DERIVED_FROM ──────────────────────┘
```

> **Nota de implementación (del ADR-04):** este grafo NO se almacena en una base
> de grafos nativa en el MVP. Se materializa en PostgreSQL con tablas de nodos y
> aristas. El modelo conceptual es un grafo; la implementación física es
> relacional. La sección 6 detalla el mapeo.

---

## 3. Catálogo de tipos de nodo

Alineado con FR-2.3 del PRD. Notación: **[MVP]** obligatorio; **[V2]** posterior.

| Tipo de nodo | Qué representa | Fase |
|--------------|----------------|------|
| **Capture** | La entrada cruda original del usuario (texto/voz transcrita). Ancla de trazabilidad. | [MVP] |
| **Note** | Una idea, pensamiento o fragmento de conocimiento atómico. | [MVP] |
| **Task** | Algo accionable, con estado y (opcional) fecha límite. | [MVP] |
| **Person** | Alguien relevante en la vida del usuario. | [MVP] |
| **Project** | Un cuerpo de trabajo que agrupa tareas, notas y personas. | [MVP] |
| **Event** | Un compromiso temporal (reunión, cita). | [MVP] |
| **Decision** | Una elección tomada o pendiente, con su contexto. | [MVP] |
| **Topic** | Tejido conectivo temático (une nodos por tema, sin jerarquía rígida). | [MVP] |
| **Place** | Una ubicación relevante. | [V2] |
| **Resource** | Un archivo, enlace o documento adjunto. | [V2] |
| **Goal** | Un objetivo de alto nivel del usuario. | [V2] |

> **Por qué `Topic` en lugar de carpetas/tags manuales:** el principio de
> producto es "el contexto se conecta solo" (FR-1.4). `Topic` es un nodo que la
> IA crea y conecta automáticamente, no una etiqueta que el usuario administra.

---

## 4. Catálogo de tipos de arista (relaciones)

Las aristas son direccionales y tipadas. Cada una tiene semántica precisa.

| Tipo de arista | Origen → Destino | Significado | Fase |
|----------------|------------------|-------------|------|
| **DERIVED_FROM** | cualquier nodo → Capture | Este nodo fue extraído de esa captura cruda (provenance). | [MVP] |
| **MENTIONS** | Note/Capture → Person/Project/Topic | La nota menciona a esta entidad. | [MVP] |
| **BELONGS_TO** | Task/Note → Project | Pertenece a un proyecto. | [MVP] |
| **ASSIGNED_TO** | Task → Person | La tarea es responsabilidad de esa persona. | [MVP] |
| **INVOLVES** | Event → Person | La persona participa en el evento. | [MVP] |
| **ABOUT** | cualquier nodo → Topic | Trata sobre este tema. | [MVP] |
| **SCHEDULED_FOR** | Task/Event → (tiempo) | Tiene un momento asociado (ver modelo temporal §9). | [MVP] |
| **DEPENDS_ON** | Task → Task | Dependencia entre tareas. | [MVP] |
| **RELATES_TO** | cualquier ↔ cualquier | Relación semántica genérica (fallback). | [MVP] |
| **DECIDED_IN** | Decision → Event | La decisión se tomó en ese evento. | [V2] |
| **LOCATED_AT** | Event → Place | Ocurre en un lugar. | [V2] |

### Atributos de toda arista
- `confidence` (0-1): certeza de la IA sobre la relación.
- `origin`: `ai` \| `user` \| `integration`.
- `user_confirmed` (bool): el usuario validó la conexión (FR-2.4).
- `created_at`.

> La distinción `origin` + `user_confirmed` es clave para el feedback loop: las
> conexiones que el usuario confirma o corrige son señal de entrenamiento futuro
> para los modelos propios (ADR-09).

---

## 5. Atributos comunes de todo nodo

| Campo | Tipo | Descripción |
|-------|------|-------------|
| `id` | UUID | Identificador único global. |
| `user_id` | UUID | Dueño. Obligatorio. Base del aislamiento (RLS). |
| `type` | enum | Tipo de nodo (§3). |
| `title` | text | Título corto legible. |
| `body` | text | Contenido (para Note/Capture). |
| `attributes` | JSONB | Atributos específicos del tipo (flexibilidad sin migraciones). |
| `status` | enum | `raw` \| `understood` \| `archived` (estado del pipeline, ADR-02). |
| `origin` | enum | `manual_text` \| `voice` \| `calendar_sync`. |
| `confidence` | float | Certeza si el nodo fue derivado por IA. |
| `embedding` | vector | Representación semántica (pgvector, para RAG). |
| `occurred_at` | timestamptz | Cuándo ocurrió el hecho (modelo temporal, §9). |
| `created_at` | timestamptz | Cuándo se registró en mindOS. |
| `updated_at` | timestamptz | Última modificación. |
| `deleted_at` | timestamptz | Soft delete (null = activo). |

> **`attributes` JSONB** permite que cada tipo tenga campos propios (ej. `Task`:
> `due_date`, `status`, `priority`; `Person`: `role`, `relationship`) sin
> multiplicar tablas ni frenar la iteración temprana.

---

## 6. Mapeo físico a PostgreSQL

Implementación del grafo en relacional (ADR-04). **DDL ilustrativo, no final**
—el esquema definitivo vive en las migraciones de implementación.

```sql
-- Tabla de nodos (todos los tipos, discriminados por 'type')
CREATE TABLE nodes (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      UUID NOT NULL,
    type         TEXT NOT NULL,          -- 'capture','note','task','person',...
    title        TEXT,
    body         TEXT,
    attributes   JSONB NOT NULL DEFAULT '{}',
    status       TEXT NOT NULL DEFAULT 'raw',
    origin       TEXT NOT NULL,
    confidence   REAL,
    embedding    VECTOR(1536),           -- dimensión según el modelo de embeddings
    occurred_at  TIMESTAMPTZ,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at   TIMESTAMPTZ
);

-- Tabla de aristas (lista de adyacencia tipada y direccional)
CREATE TABLE edges (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id        UUID NOT NULL,
    type           TEXT NOT NULL,        -- 'derived_from','mentions','belongs_to',...
    source_node_id UUID NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
    target_node_id UUID NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
    confidence     REAL,
    origin         TEXT NOT NULL,        -- 'ai','user','integration'
    user_confirmed BOOLEAN NOT NULL DEFAULT FALSE,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at     TIMESTAMPTZ
);
```

### Índices esenciales

```sql
-- Recuperación por usuario + tipo (patrón de acceso dominante)
CREATE INDEX idx_nodes_user_type ON nodes (user_id, type) WHERE deleted_at IS NULL;
-- Búsqueda dentro de atributos flexibles
CREATE INDEX idx_nodes_attributes ON nodes USING GIN (attributes);
-- Travesía de grafo: aristas salientes y entrantes por usuario
CREATE INDEX idx_edges_source ON edges (user_id, source_node_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_edges_target ON edges (user_id, target_node_id) WHERE deleted_at IS NULL;
-- Búsqueda semántica (vector) — HNSW para consultas de baja latencia
CREATE INDEX idx_nodes_embedding ON nodes USING hnsw (embedding vector_cosine_ops);
```

### Aislamiento por usuario (Row-Level Security)

```sql
ALTER TABLE nodes ENABLE ROW LEVEL SECURITY;
ALTER TABLE edges ENABLE ROW LEVEL SECURITY;

CREATE POLICY nodes_isolation ON nodes
    USING (user_id = current_setting('app.current_user_id')::UUID);
CREATE POLICY edges_isolation ON edges
    USING (user_id = current_setting('app.current_user_id')::UUID);
```

> RLS es una **segunda línea de defensa**: aunque la capa de aplicación siempre
> filtra por `user_id`, la base de datos garantiza el aislamiento incluso ante
> un bug de aplicación.

---

## 7. El ciclo de vida del dato: de captura a comprensión

Materializa los flujos 1 y 2 del TAD a nivel de datos:

```
1. Usuario captura texto/voz
        │
        ▼
2. Se crea un nodo Capture (status='raw', origin='manual_text'|'voice')
   → la captura cruda ya está a salvo, pase lo que pase después
        │  (evento CaptureCreated → cola)
        ▼
3. Worker de AI Understanding procesa la captura:
   a. Extrae entidades (Person, Task, Event, Project, Decision...)
   b. Crea/actualiza nodos para cada entidad (confidence < 1, origin='ai')
   c. Crea aristas DERIVED_FROM hacia la Capture (provenance)
   d. Crea aristas semánticas (MENTIONS, ASSIGNED_TO, BELONGS_TO...)
   e. Genera embeddings (nodo + entidades)
   f. Resuelve referencias temporales ("jueves" → fecha, §9)
        │
        ▼
4. Capture.status = 'understood'; la superficie refleja las conexiones
        │
        ▼
5. El usuario puede confirmar/corregir conexiones (FR-2.4)
   → edges.user_confirmed = true / se ajustan
```

---

## 8. Resolución de entidades (entity resolution)

Cuando una captura menciona "Ana", ¿es la misma `Person` de antes o una nueva?

- **MVP:** resolución simple por coincidencia de nombre normalizado + similitud
  de embedding dentro del grafo del usuario. Si hay match de alta confianza, se
  reutiliza el nodo; si no, se crea uno nuevo.
- **V2 (FR-2.6):** deduplicación robusta, fusión de nodos propuesta al usuario,
  desambiguación ("¿esta Ana es Ana García o Ana López?").

> Sin resolución de entidades, el grafo se fragmenta (múltiples "Ana"
> desconectadas) y se pierde el valor de Pilar 2. Es crítico hacerlo bien
> incluso en su forma simple del MVP.

---

## 9. Modelo temporal

El grafo distingue **dos tiempos** por nodo:
- `occurred_at`: cuándo sucede/sucedió el hecho (la reunión es el jueves).
- `created_at`: cuándo mindOS lo supo (lo capturaste el lunes).

Esta distinción es esencial para:
- El **Daily Briefing** (FR-3.1/3.4): prioriza por `occurred_at` (qué viene hoy).
- La resolución de referencias relativas (FR-2.5): "el jueves" se ancla a la
  fecha de la captura y se resuelve a un `occurred_at` absoluto.
- La memoria histórica: "¿qué decidí sobre X el mes pasado?".

---

## 10. Estrategia de embeddings (búsqueda semántica)

- Cada `Capture`, `Note` y entidad relevante recibe un `embedding` (pgvector).
- La recuperación contextual (RAG, flujo 4 del TAD) combina **dos señales**:
  1. **Semántica:** vecinos más cercanos por similitud de embedding.
  2. **Estructural:** travesía de grafo de 1-2 saltos desde los nodos candidatos.
- La combinación (semántica + estructural) es lo que diferencia a mindOS de un
  simple "chat con tus notas": no solo encuentra texto parecido, sino que sigue
  las **relaciones**.
- La dimensión del vector y el modelo de embeddings se fijan con la elección del
  proveedor de IA (queda como dependencia de #07 / implementación).

---

## 11. Escalabilidad y rendimiento (horizonte 10 años)

| Preocupación | Estrategia |
|--------------|-----------|
| Crecimiento del grafo por usuario | Particionado de `nodes`/`edges` por `user_id` (o por rango) cuando el volumen lo exija. |
| Nodos "fríos" (memoria antigua) | `status='archived'` + posible archivado a almacenamiento más barato, manteniéndolos consultables. |
| Latencia de búsqueda vectorial | Índice HNSW; migración a vector DB dedicada si escala lo requiere (ADR-05). |
| Fan-out excesivo de aristas | Límites y poda de relaciones `RELATES_TO` de baja confianza; consolidación en `Topic`. |
| Consultas de grafo profundas (V2+) | Puerta abierta a base de grafos nativa para ese subdominio (ADR-04). |
| Lecturas intensivas (Daily Briefing) | Réplicas de lectura + caché en Redis de briefings/consultas frecuentes. |

> **Recordatorio del principio rector (#02):** no implementamos particionado ni
> archivado el día uno. Diseñamos el modelo para que introducirlos después sea
> una evolución, no una reescritura.

---

## 12. Privacidad a nivel de datos

Cumple los requisitos transversales del PRD (FR-X.2 a FR-X.5):

- **Exportación total (FR-X.3):** todo el grafo de un usuario (nodos + aristas +
  capturas) es exportable a un formato abierto. El modelo uniforme nodos/aristas
  facilita un export completo y portable.
- **Borrado total (FR-X.4):** eliminar un usuario borra en cascada todos sus
  nodos y aristas (`ON DELETE CASCADE` + limpieza de embeddings y backups según
  política de #07).
- **Trazabilidad (FR-X.5):** `origin` + aristas `DERIVED_FROM` permiten rastrear
  la procedencia de cualquier dato hasta su captura original.
- **Minimización hacia el LLM (ADR-09):** solo se envían al LLM externo los
  fragmentos necesarios para cada operación, no el grafo completo.

---

## 13. Ejemplo completo (Journey A del PRD)

Captura del usuario:
> *"Reunión con Ana el jueves para revisar el pitch de inversión; me debe el
> deck actualizado."*

Grafo resultante tras la comprensión:

```
Capture(raw)  "Reunión con Ana el jueves..."  occurred_at=lunes
   ├─ DERIVED_FROM ◄── Person("Ana")
   ├─ DERIVED_FROM ◄── Event("Reunión revisión pitch")   occurred_at=jueves
   ├─ DERIVED_FROM ◄── Project("Pitch de inversión")
   └─ DERIVED_FROM ◄── Task("Ana debe enviar el deck")   status=pending

Relaciones semánticas:
   Event("Reunión...")      ──INVOLVES──►    Person("Ana")
   Event("Reunión...")      ──ABOUT──►       Project("Pitch de inversión")
   Task("deck")             ──ASSIGNED_TO──► Person("Ana")
   Task("deck")             ──BELONGS_TO──►  Project("Pitch de inversión")
```

Cuando el usuario pregunta *"¿qué tengo pendiente con Ana?"* (Journey C):
recuperación combina la búsqueda vectorial ("pendiente", "Ana") con la travesía
`Person(Ana) ◄─ASSIGNED_TO─ Task(pending)` → responde: *"Ana te debe el deck
actualizado del pitch de inversión, para la reunión del jueves."*

---

## 14. Preguntas abiertas (para #04, #07 e implementación)

1. Dimensión exacta del vector de embedding → depende del proveedor (#07).
2. ¿Se versiona el historial de cambios de un nodo (event sourcing ligero) o solo
   `updated_at`? → decisión de implementación con impacto en "memoria histórica".
3. Umbral de confianza para auto-confirmar conexiones vs. pedir validación al
   usuario → requiere datos empíricos (relacionado con criterio de aceptación #01).
4. Política de retención/archivado de nodos fríos → se detalla en #07 (Data
   Retention).

---

## Historial de versiones

| Versión | Fecha | Autor | Cambios |
|---------|-------|-------|---------|
| 0.1 | 2026-07-01 | CTO | Borrador inicial. Modelo de property graph, catálogo de nodos y aristas, atributos, mapeo físico a PostgreSQL (DDL ilustrativo + índices + RLS), ciclo de vida del dato, resolución de entidades, modelo temporal, embeddings, escalabilidad, privacidad a nivel de datos y ejemplo completo. |
