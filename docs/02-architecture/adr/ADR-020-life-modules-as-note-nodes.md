# ADR-020 — Tareas, Crecimiento y Finanzas adelantados sobre el grafo (nodos `note` con `attributes.kind`)

> **Architecture Decision Record. REGISTRO RETROACTIVO.** La decisión se tomó en
> código el 2026-07-10 (commits `a97846d` y `14de5ab`, directos a `main`) sin ADR
> ni actualización de 009/012. Este ADR la documenta tal como está construida
> para que sea recuperable y revisable (D-017).

| Metadato | Valor |
|----------|-------|
| Estado | 🟠 Aceptado (retroactivo), sujeto a veto del founder |
| Fecha | 2026-10-27 (decisión en código: 2026-07-10) |
| Autor | CPTO |
| Relacionado | [ADR-004](./ADR-004-postgresql-source-of-truth.md) (Postgres como verdad), [#03](../../03-data/data-architecture-and-domain-model.md) §3 y §5, [#08](../../08-roadmap/technical-roadmap.md) §3 y §3.1 |

---

## Contexto

El roadmap dejaba los "módulos de dominio de vida" (finanzas, salud) para V4, y
el PRD (#01) declara como non-goal del MVP "no gestiona finanzas". Con F3 a
medias, el founder quiso que la app fuera útil a diario además de "entender":
tareas con prioridad, metas, hábitos, reflexiones y un control simple de gastos.
Se construyeron rápido y sin migraciones.

## Decisión

1. **Tareas manuales** = nodos `type='task'`, los mismos que crea la IA. Origen
   `manual_text`, estado en `attributes`: `done`, `done_at`, `priority`
   (`high|medium|low`, por defecto `medium`), `due_at` y `area`. Las tareas
   extraídas por la IA (`origin='ai'`) usan el mismo contrato.
2. **Crecimiento y Finanzas** = nodos `type='note'` diferenciados por
   `attributes.kind`, **sin tablas nuevas**:

| `kind` | Atributos | Endpoints |
|--------|-----------|-----------|
| `goal` | `progress` 0..100, `done`, `target_date`, `area` | `/v1/growth/goals` |
| `habit` | `cadence` (`daily`\|`weekly`), `log` (fechas `YYYY-MM-DD`), `area` | `/v1/growth/habits`, `/v1/growth/habits/:id/check` |
| `reflection` | `mood`; el texto va en `body` | `/v1/growth/reflections` |
| `expense` | `amount`, `currency`, `category`; la nota va en `body` | `/v1/finance/expenses`, `/v1/finance/summary` |

3. Toda lectura y escritura pasa por `PrismaRlsService.withUser`, con el mismo
   aislamiento por usuario que el resto del grafo.
4. Los `note` con `kind` **no cuentan** en `GET /v1/graph/summary`, que excluye
   `note`, y no los genera la IA.

## Consecuencias

- **A favor:**
  - Cero migraciones y RLS heredado.
  - Los elementos ya viven en el grafo, así que en el futuro la IA podrá
    conectarlos (por ejemplo, una meta con sus tareas o un gasto con un
    proyecto).
- **En contra:**
  - Sin integridad a nivel de base de datos: no hay tipos, ni `CHECK`, ni
    índices dedicados para `amount` o `log`.
  - Consultas por `attributes->>'kind'` sobre una tabla que crece.
  - `note` pierde su significado original del #03 ("idea atómica") porque pasa
    a mezclar conceptos.
  - Deuda asociada: D-013 (UTC), D-014 (moneda) y D-015 (rachas semanales).
- **Contradice** el non-goal "no gestiona finanzas" del PRD y la ficha V4 del
  roadmap. Ambos se anotan como revisados por este ADR.

## Criterios de salida (cuándo migrar a tablas propias)

Migrar `expense` y `habit` a tablas dedicadas cuando ocurra cualquiera de estas
condiciones:
- se necesiten agregaciones pesadas (por categoría, mes o moneda) o informes;
- la IA tenga que **crear** gastos o hábitos desde las capturas
  (ficha #08 §3.1);
- el volumen de `note` con `kind` degrade las consultas del grafo.

## Alternativas consideradas

- **(a) Tablas propias desde el inicio** (`expenses`, `habits`, `goals`). Más
  correctas, pero exigen migración, RLS y políticas nuevas. Se rechazó por
  velocidad.
- **(b) Nuevos valores del enum `NodeType`** (`goal`, `habit`, `expense`).
  Requiere migración del enum e impacta la extracción de la IA y el gate del
  eval. Se rechazó.
- **(c) No adelantar los módulos** y respetar el roadmap (cerrar primero F3 y
  F4). Era la opción conservadora; el founder priorizó la utilidad diaria.
