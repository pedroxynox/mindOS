# ADR-004 — PostgreSQL como sistema de verdad (incluido el grafo)

> **Architecture Decision Record.** Extraído del [TAD #02](../technical-architecture.md)
> (§5), donde estaba embebido como "ADR-04". Numeración normalizada a 3 dígitos
> (`ADR-004`) durante la consolidación de ADRs (deuda [D-004](../../000_SYSTEM/012_RISK_AND_DEBT_REGISTER.md)).
>
> ➕ Confirmado y complementado por [ADR-012](./ADR-012-canonical-stack.md).

| Metadato | Valor |
|----------|-------|
| Estado | 🟠 Decisión de CTO, sujeta a veto |
| Fecha | 2026-07-01 |
| Autor | CTO |
| Origen | #02 §5 (embebido) |

---

## Contexto

Postgres es robusto, operacionalmente simple, escala vertical y horizontalmente
(réplicas de lectura, particionado), y soporta aislamiento por usuario vía
Row-Level Security. Introducir una base de grafos nativa (Neo4j) desde el día uno
añade un sistema entero que operar, respaldar y monitorear, sin que la complejidad
de las travesías del MVP lo justifique.

## Decisión

**PostgreSQL** es el almacén principal. El grafo de conocimiento se modela con
tablas de **nodos** y **aristas** explícitas (más JSONB para atributos flexibles).

## Consecuencias

- **Trade-off aceptado:** travesías complejas en SQL son más verbosas. Aceptable
  para el alcance del MVP (conexiones de 1-2 saltos).
- **Punto de reevaluación:** si las consultas de grafo (recomendaciones
  multi-salto, análisis de relaciones complejas en V2+) degradan el rendimiento en
  Postgres, se migra ese subdominio a una base de grafos. El diseño de
  nodos/aristas mantiene esa puerta abierta.

## Alternativas consideradas

- **Neo4j / base de grafos nativa.** Superior para travesías profundas y
  multi-salto. Descartada para el MVP por el costo operativo de un sistema
  adicional; queda como punto de reevaluación para V2+.
