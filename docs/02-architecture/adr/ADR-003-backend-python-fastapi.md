# ADR-003 — Backend: Python + FastAPI para el núcleo de IA

> **Architecture Decision Record.** Extraído del [TAD #02](../technical-architecture.md)
> (§5), donde estaba embebido como "ADR-03". Numeración normalizada a 3 dígitos
> (`ADR-003`) durante la consolidación de ADRs (deuda [D-004](../../000_SYSTEM/012_RISK_AND_DEBT_REGISTER.md)).
>
> ⚠️ **SUPERADO PARCIALMENTE por [ADR-010](./ADR-010-final-stack-and-two-backends.md)
> (2026-07-01):** el backend de negocio pasa a **NestJS (TypeScript)**; Python +
> FastAPI se mantiene, pero acotado al **servicio de IA** (comprensión, embeddings,
> RAG).

| Metadato | Valor |
|----------|-------|
| Estado | 🟠 Decisión de CTO — superada parcialmente por ADR-010 |
| Fecha | 2026-07-01 |
| Autor | CTO |
| Origen | #02 §5 (embebido) |

---

## Contexto

El diferenciador de mindOS *es* la IA. El ecosistema de Python para orquestación
de LLMs, embeddings, procesamiento de lenguaje y herramientas de ML no tiene
rival. Poner el núcleo donde vive el ecosistema de IA reduce fricción en el
componente más crítico.

## Decisión

El backend principal se escribe en **Python** con **FastAPI**. FastAPI aporta
rendimiento async, tipado vía type hints + Pydantic, y validación de contratos
sólida.

## Consecuencias

- **Trade-off aceptado:** Python es menos performante que Go en CPU puro. Se
  mitiga con procesamiento async y extrayendo trabajo pesado a workers. Para
  nuestras cargas (I/O hacia LLMs y BD), no es el cuello de botella.

## Alternativas consideradas

- **TypeScript/Node (full-stack unificado):** tentador por compartir lenguaje con
  el frontend, pero el ecosistema de IA es más pobre y acabaríamos llamando a
  servicios Python de todas formas.
- **Go:** excelente rendimiento y concurrencia, pero ecosistema de IA inmaduro y
  mayor verbosidad para iterar rápido en la capa de comprensión.
