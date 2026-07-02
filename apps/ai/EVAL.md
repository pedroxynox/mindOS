# Arnés de evaluación de comprensión (F2) — Guía

Esta guía explica cómo ejecutar el **examen de calidad de comprensión** que
de-riesga **R-001** (el riesgo #1: ¿entiende bien la IA?) **antes** de construir
el pipeline completo (diseño `../../.kiro/specs/comprehension/design.md` §13).

Es una **PoC aislada**: solo extracción + evaluación. **No** hay base de datos,
ni cola, ni pgvector, ni worker. Todo corre en `apps/ai` (Python).

## Qué hay aquí

```
apps/ai/app/
├── providers/
│   ├── base.py            # Contrato AIProvider (complete/embed/transcribe) + Usage/Completion/Embedding
│   ├── fake_provider.py   # Provider determinista, sin red ni coste (heurístico)
│   ├── openai_provider.py # Provider real (usa OPENAI_API_KEY)
│   └── factory.py         # build_provider(settings): 'fake' (def.) | 'openai'
├── understanding/
│   ├── text_utils.py      # normalización de etiquetas (para comparar gold vs predicción)
│   └── extract.py         # extract_entities(text, provider) -> Extraction (JSON tipado, validado)
└── eval/
    ├── dataset/           # eval set versionado (casos + gold labels) + README de formato
    ├── loader.py          # carga y valida los casos
    ├── metrics.py         # precisión/recall/F1, precisión de tareas, alucinación, coste, p95 (funciones puras)
    └── run_eval.py        # runner: corre extracción, agrega métricas, imprime reporte, aplica la puerta
```

## Requisitos

- Python 3.11+
- Instalar dependencias de desarrollo:

```bash
cd apps/ai
pip install -e ".[dev]"
```

## 1) Correr el examen OFFLINE (FakeProvider, sin coste)

Es el modo por defecto. No necesita clave ni red. Es 100 % reproducible.

```bash
cd apps/ai
python -m app.eval.run_eval
```

Imprime el reporte (ver más abajo). El `FakeProvider` es un extractor
**heurístico** (detecta tareas por verbos imperativos/palabras clave, personas
por mayúsculas, temas por un léxico, etc.). No es la calidad final: sirve para
ejercitar el arnés y dar una **línea base** con sentido, con coste = 0.

## 2) Correr el examen con un LLM REAL (OpenAIProvider)

Aquí es donde se obtiene el **veredicto de calidad real** de R-001.

```bash
cd apps/ai
export OPENAI_API_KEY="sk-..."          # tu clave
python -m app.eval.run_eval --provider openai
```

- Si no hay `OPENAI_API_KEY`, el provider `openai` falla con un mensaje claro;
  por eso el modo por defecto es `fake`.
- Modelo por defecto: `gpt-4o-mini` (configurable con `OPENAI_MODEL`), embeddings
  `text-embedding-3-small` (`OPENAI_EMBEDDING_MODEL`). El coste se estima y se
  reporta por captura.

## 3) Modo "puerta" (gate) para CI

Con `--gate`, el runner devuelve **código de salida ≠ 0** si no se superan los
umbrales. Sirve para conectar el examen a CI cuando el eval set madure.

```bash
python -m app.eval.run_eval --gate               # offline
python -m app.eval.run_eval --provider openai --gate
```

## Cómo leer el reporte

```
  Aggregate metrics (micro-averaged)
    entities   P=0.950  R=0.927  F1=0.938  (tp=38 fp=2 fn=3)
    tasks      P=0.875  R=0.700  F1=0.778  (tp=7 fp=1 fn=3)
    connections P=1.000  R=0.714  F1=0.833
    hallucination rate : 0.050
    mean cost / capture: $0.000000
    latency p95        : 0.37 ms
```

| Métrica | Qué significa |
|---------|---------------|
| **entities P/R/F1** | Precisión, recall y F1 de las **entidades** extraídas (incluye tareas como nodo `task`), comparando por **tipo + etiqueta normalizada** contra el gold. F1 es el balance principal. |
| **tasks P/R/F1** | Igual, pero **solo** sobre tareas. Nos interesa sobre todo la **precisión** (no inventar acciones que no existen). |
| **connections P/R/F1** | Calidad de las aristas propuestas (`assigned_to`, `mentions`, `relates_to`). |
| **hallucination rate** | Proporción de entidades propuestas **sin respaldo** en el gold (`FP / total propuestas`). Es una **cota superior** de "cuánto inventa". Cuanto más baja, mejor. |
| **mean cost / capture** | Coste medio en USD por captura (viabilidad económica, #02). Con `fake` es 0. |
| **latency p95** | Latencia del percentil 95 del paso de extracción (viabilidad operativa). |

El bloque **Per-case** muestra F1 de entidades, precisión de tareas y alucinación
por caso, útil para localizar dónde falla la comprensión.

## La puerta de aceptación (umbrales)

```
  Acceptance gate (PROVISIONAL — pending product sign-off)
    F1 entities        >= 0.80
    task precision     >= 0.85
    hallucination      <= 0.05
    mean cost/capture  <= $0.0100
```

> **Importante:** estos umbrales son **PROVISIONALES** (diseño §13.2) y están
> **pendientes de ratificar por el dueño de producto**. Se leen desde la
> configuración (`Settings` / variables `EVAL_*` en `.env`), así que se pueden
> ajustar sin tocar código.

- **Si se supera la puerta:** procede el pipeline completo (§8) y se **fija la
  dimensión de embedding y el proveedor** con datos (cierra parte de D-008).
- **Si no se supera:** se itera **solo** sobre prompts / estrategia de extracción
  / elección de modelo (todo detrás de `AIProvider`, coste acotado) **antes** de
  invertir en migraciones, worker y cola. No construimos sobre un motor que no
  entiende bien.

## Añadir o editar casos del eval set

Ver `app/eval/dataset/README.md` para el formato exacto. En resumen: crea un
`case-NN-....json` con `text` y sus `gold` labels (verdad anotada a mano). El
runner lo recoge automáticamente. El gold es **verdad**: no se ajusta para que un
proveedor concreto puntúe mejor.

## Calidad del código (lo que corre en CI, job `ai`)

```bash
cd apps/ai
ruff check .
mypy app
pytest
```
