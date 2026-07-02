# ADR-005 — Búsqueda semántica con pgvector (no una vector DB dedicada, aún)

> **Architecture Decision Record.** Extraído del [TAD #02](../technical-architecture.md)
> (§5), donde estaba embebido como "ADR-05". Numeración normalizada a 3 dígitos
> (`ADR-005`) durante la consolidación de ADRs (deuda [D-004](../../000_SYSTEM/012_RISK_AND_DEBT_REGISTER.md)).
>
> ➕ Confirmado por [ADR-012](./ADR-012-canonical-stack.md) (D2/D3): `pgvector` es
> requisito de primera clase y vector store inicial.

| Metadato | Valor |
|----------|-------|
| Estado | 🟠 Decisión de CTO, sujeta a veto |
| Fecha | 2026-07-01 |
| Autor | CTO |
| Origen | #02 §5 (embebido) |

---

## Contexto

Mantener un solo almacén operativo en el MVP evita sincronizar datos entre
Postgres y una vector DB externa. pgvector es suficiente hasta escalas
considerables.

## Decisión

Los embeddings y la búsqueda semántica (RAG) usan la extensión **pgvector** sobre
el mismo Postgres.

## Consecuencias

- **Punto de reevaluación:** ante millones de vectores por consulta con latencia
  crítica, migrar a una vector DB dedicada (Qdrant / Weaviate / Pinecone). La capa
  de recuperación se abstrae para permitir el cambio.

## Alternativas consideradas

- **Vector DB dedicada desde el día uno.** Descartada por complejidad prematura y
  costo de sincronización; queda como puerta de dos vías si la escala lo exige.
