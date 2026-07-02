# Eval set — formato de los casos (F2, de-riesgo R-001)

Cada archivo `case-*.json` es **un caso** del conjunto de evaluación, con sus
**etiquetas gold** (verdad anotada a mano). El conjunto se versiona con el
código (design §13.1). Los casos se cargan y validan con
`app/eval/loader.py` (`load_dataset`), ordenados por `id` para reproducibilidad.

## Esquema de un caso

```json
{
  "id": "case-01",                     // identificador único y estable
  "language": "es",                    // "es" | "en" | "mixed"
  "description": "…",                  // qué representa el caso (para humanos)
  "text": "…",                         // el texto de la captura a analizar
  "gold": {                            // extracción correcta anotada a mano
    "entities":    [ { "type": "...", "label": "..." } ],
    "tasks":       [ { "label": "..." } ],
    "connections": [ { "type": "...", "source": "...", "target": "..." } ]
  }
}
```

### Tipos permitidos (taxonomía v1, design §4.1)

- `entities[].type`: `person` | `project` | `event` | `topic` | `note`
  (las **tareas** van en su propio campo `tasks`, pero cuentan como nodo
  `task` en las métricas de entidades).
- `connections[].type`: `mentions` | `assigned_to` | `relates_to`
  (`derived_from` es procedencia que se añade al escribir el grafo, no se
  anota aquí).

### Reglas de anotación

- **Gold = verdad**, independiente de cualquier proveedor. No se ajusta para
  que un provider concreto puntúe mejor.
- Los `label` se comparan **normalizados** (minúsculas, sin acentos, sin
  puntuación de bordes): "Reunión" ≡ "reunion". Ver
  `app/understanding/text_utils.normalize_label`.
- En `connections` de tipo `assigned_to`, `source` es la etiqueta de la tarea
  y `target` la persona responsable. Deben coincidir textualmente con las
  etiquetas anotadas en `tasks`/`entities`.
- Incluir casos **con y sin tareas**, en **español e inglés**, y algún caso
  **ambiguo** (intención tentativa, recordatorios) para estresar precisión y
  recall.

Para añadir un caso: crea `case-NN-....json` siguiendo el esquema. El runner lo
recoge automáticamente.
