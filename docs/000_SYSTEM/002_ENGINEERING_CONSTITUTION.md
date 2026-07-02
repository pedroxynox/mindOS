# 002 — Engineering Constitution

| Metadato | Valor |
|----------|-------|
| Versión | 1.0 |
| Estado | 🟢 Vigente |
| Ámbito | Principios inmutables que rigen toda ingeniería de mindOS |
| Depende de | [001](./001_CPTO_CHARTER.md); cadena #02, #03, #05, #07 |
| Última actualización | 2026-07-02 |

Este documento contiene **únicamente principios** — las leyes y su porqué. **No contiene reglas concretas**: esas viven en [007_CODE_QUALITY](./007_CODE_QUALITY.md). Un principio dice *qué* y *por qué*; una regla dice *cómo*. Estos principios solo se enmiendan mediante **ADR + aprobación del founder**.

## Calidad
1. **Nunca programar antes de diseñar; nunca diseñar antes de comprender el problema.** 🟢 El código sin diseño es deuda garantizada; el diseño sin comprensión resuelve el problema equivocado. (Fundamento: filosofía de la cadena, #05.)
2. **Corrección antes que velocidad; velocidad antes que perfección.** 🟢 Entregamos código correcto y simple; el pulido prematuro compite con el aprendizaje. (Ref: #05.)

## Escalabilidad
3. **Simplicidad operativa hoy, puntos de extensión para mañana.** 🟢 Ni sobre-ingeniería prematura ni pintarse en una esquina: diseñamos fronteras que permitan extraer y crecer cuando el dato lo justifique. (Ref: principio rector del #02.)
4. **El grafo del usuario crece durante años: el rendimiento se diseña para grafos densos y longevos.** 🟢 Las decisiones de datos asumen crecimiento monotónico por usuario. (Ref: #02, #03.)

## Mantenibilidad
5. **Fronteras explícitas entre contextos acotados.** 🟢 Identity, Capture, Knowledge Graph, AI Understanding, Proactivity y Query/Retrieval se comunican por interfaces claras; extraer un servicio debe ser mecánico, no una reescritura. (Ref: #02 §4.)
6. **Todo acceso a LLM vive tras la capa `AIProvider` (anti lock-in).** 🟢 El mercado de modelos cambia cada trimestre; la lógica de dominio nunca se acopla a un proveedor. (Ref: #02 ADR-07, ADR-09.)

## Seguridad
7. **Privacidad como requisito de entrada: aislamiento por usuario + RLS.** 🟢 Ningún dato cruza fronteras de usuario; el aislamiento no es una feature, es una precondición. (Ref: #07, #03.)
8. **La IA propone, el usuario confirma.** 🟢 Las inferencias automáticas nunca se aplican como verdad irreversible sin control del usuario. (Ref: #01, #02 flujos.)

## Arquitectura
9. **La captura cruda es sagrada y nunca se pierde.** 🟢 La captura se persiste antes de cualquier procesamiento; es el activo irremplazable del usuario. (Ref: #02 §6, #03.)
10. **El fallo del pipeline de IA nunca pierde la captura.** 🟢 La comprensión es asíncrona, idempotente y reintentable; su fallo degrada funcionalidad, jamás datos. (Ref: #02 §7, #06.)

## Testing
11. **La confianza se gana con pruebas, no con optimismo.** 🟢 Toda lógica de dominio se prueba; la lógica central se prueba con propiedades (PBT) además de ejemplos. (Ref: #05, #07.)

## Performance
12. **El camino de captura es síncrono y mínimo; todo lo caro es asíncrono.** 🟢 La captura responde en presupuesto estricto (p95 objetivo del #06); el coste de LLM/BD nunca bloquea al usuario. (Ref: #02 §6, #06.)

## Documentación
13. **Nada sin trazabilidad.** 🟢 Toda decisión relevante deja un ADR o una entrada en [012](./012_RISK_AND_DEBT_REGISTER.md); el conocimiento vive en el repo, no en el chat. (Ref: [003](./003_DECISION_FRAMEWORK.md), #05.)
14. **La deuda no registrada está prohibida.** 🟢 La deuda técnica es crédito consciente: se anota con su interés y su plan, o no se contrae. (Ref: [001](./001_CPTO_CHARTER.md) §8, [012](./012_RISK_AND_DEBT_REGISTER.md).)

## Historial de versiones
| Versión | Fecha | Cambios |
|---------|-------|---------|
| 1.0 | 2026-07-02 | Constitución inicial: 14 principios inmutables. |
