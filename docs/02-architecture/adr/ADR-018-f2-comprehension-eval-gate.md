# ADR-018 — Umbrales realistas del gate de calidad de comprensión (F2 / R-001)

> **Architecture Decision Record.** Ratifica los umbrales de aceptación del arnés
> de evaluación de F2 (diseño de comprensión §13.2), hasta ahora **provisionales**
> (`config.py`, "PROVISIONAL — pending product sign-off"). De-riesga [R-001](../../000_SYSTEM/012_RISK_AND_DEBT_REGISTER.md).

| Metadato | Valor |
|----------|-------|
| Estado | 🟢 Aceptado (decisión del founder/CPTO) |
| Fecha | 2026-07-09 |
| Autor | CPTO |
| Origen | Diseño de comprensión (F2) §13.2; [009 Current State](../../000_SYSTEM/009_CURRENT_STATE.md) |
| Supersede | Los umbrales **provisionales** de `config.py` (mismo fichero, ahora ratificados) |

---

## Contexto

El diseño de F2 exige superar un **gate de calidad** (eval set de 45 casos con
métricas y umbrales) **antes** de invertir en el motor de comprensión completo.
Los umbrales eran provisionales y "pendientes de aprobación de producto".

La medición estable más reciente (proveedor `groq`, 45 casos) da:

| Métrica | Valor | Umbral provisional | ¿Cumple? |
|---------|-------|--------------------|----------|
| F1 de entidades | **0.782** | ≥ 0.80 | ❌ (marginal, recall de *topics*) |
| Precisión de tareas | **0.930** | ≥ 0.85 | ✅ |
| Tasa de alucinación | **0.091** | ≤ 0.05 | ❌ vs 0.05; ✅ vs meta realista 0.10 |
| Coste medio/captura | **$0.000000** | ≤ $0.01 | ✅ |

El umbral de alucinación ≤0.05 se demostró **inalcanzable de forma estable** con
LLMs de nivel gratuito sin sacrificar recall; el founder ya había decidido iterar
hacia una **meta realista de ≤0.10** (manteniendo 0.05 como aspiración).

## Decisión

1. **Ratificar** los umbrales del gate con valores **realistas** (no se relaja el
   *gold set* ni la definición de las métricas — sólo se fija el listón honesto):

   ```
   F1_entidades         ≥ 0.80         (sin cambio: bar de calidad legítimo)
   Precisión_tareas      ≥ 0.85         (sin cambio)
   Tasa_alucinación      ≤ 0.10         (RATIFICADO realista; aspiración 0.05)
   Coste_medio/captura   ≤ $0.01        (sin cambio)
   ```

2. **Autorizar el inicio del motor de comprensión** (worker, `GraphWriter`,
   contexto RLS, `CostMeter`, migración pgvector) **en paralelo**, asumiendo el
   riesgo explícito de que **F1 de entidades está en 0.782** (justo por debajo del
   piso de 0.80). Fundamento: la **plomería de escritura** del motor (persistencia
   idempotente, provenance, aislamiento RLS, coste) es **ortogonal a la calidad de
   extracción** — es idéntica tanto si F1 es 0.78 como 0.83 — por lo que no se
   "construye sobre arena".

3. **Mantener abierta** la brecha de recall de *topics* como riesgo vivo (R-001)
   con un *fast-follow* de iteración de prompt, **sin** tocar umbrales ni gold para
   "aprobar".

## Estado

🟢 Aceptado. Decisión explícita del founder ("camino B": ratificar umbrales
realistas y arrancar el motor asumiendo el riesgo del F1 marginal).

## Consecuencias

- El motor de F2 se construye ya; su corrección (idempotencia, provenance,
  aislamiento, coste) se valida con tests offline y de integración, con
  independencia del número de calidad de extracción.
- La calidad de comprensión sigue siendo **R-001 abierto**: F1 de entidades 0.782
  queda por debajo del piso 0.80 y debe cerrarse con iteración de prompt.
- No se falsea el gate: los umbrales son honestos y públicos; el gap de F1 queda
  documentado, no escondido.

## Alternativas consideradas

- **Bloquear el motor hasta que F1 ≥ 0.80 (camino A).** Descartado por el founder:
  la plomería de escritura no depende de la calidad de extracción, y bloquearla no
  acelera cerrar el gap de recall. Se asume el riesgo de forma consciente.
- **Bajar el piso de F1 para "aprobar".** Rechazado: viola la norma de gobernanza
  "no relajar umbrales ni gold para aprobar". El piso de 0.80 se mantiene.
