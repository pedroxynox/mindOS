# ADR-009 — Estrategia de IA: LLM externo ahora, IP en el motor de contexto, modelos propios especializados después

> **Architecture Decision Record.** Extraído del [TAD #02](../technical-architecture.md)
> (§5), donde estaba embebido como "ADR-09". Numeración normalizada a 3 dígitos
> (`ADR-009`) durante la consolidación de ADRs (deuda [D-004](../../000_SYSTEM/012_RISK_AND_DEBT_REGISTER.md)).

| Metadato | Valor |
|----------|-------|
| Estado | 🟢 Firme (decisión del founder + CTO, tomada explícitamente) |
| Fecha | 2026-07-01 |
| Autor | Founder + CTO |
| Origen | #02 §5 (embebido, añadido en v0.2 del #02) |

---

## Contexto

"IA propia y potente" no se logra construyendo un LLM propio (competir con
laboratorios de miles de millones es inviable y el LLM es un commodity que se
abarata cada mes). Se logra construyendo la capa que nadie puede copiar: el
modelo vivo del usuario. Analogía: no fabricamos las celdas de batería (el LLM);
construimos el vehículo completo (el motor de contexto).

## Decisión

El MVP usa el **LLM externo más capaz disponible** (vía la capa `AIProvider` del
[ADR-007](./ADR-007-aiprovider-abstraction.md)), con protecciones contractuales y
técnicas de privacidad. La inversión de ingeniería propia se concentra en el
**motor de contexto, el grafo de conocimiento y el sistema de memoria/recuperación**
— ahí vive la IP defendible de mindOS. Los modelos propios (fine-tuning o
auto-hospedaje) se adoptan **después**, de forma especializada, cuando el grafo de
datos del usuario ofrezca una ventaja de entrenamiento que un modelo genérico no
pueda replicar.

## Consecuencias

- **Puerta abierta:** la capa `AIProvider` ([ADR-007](./ADR-007-aiprovider-abstraction.md))
  permite migrar a modelos propios sin tocar la lógica de dominio, cuando el
  negocio lo justifique. La privacidad total pasa a ser una **promesa de evolución
  de marca**, no un requisito bloqueante del MVP.
- **Implicación para #07 (Security & Privacy):** aunque usemos un LLM externo, se
  aplican minimización de datos enviados, prohibición contractual de entrenamiento
  con datos del usuario, y evaluación de residencia de datos.

## Alternativas consideradas

- **Modelo propio / auto-hospedado desde el día uno** (la "Opción B" evaluada).
  Rechazada para el MVP porque: (1) dispara el costo de infraestructura de GPU
  antes de tener ingresos; (2) retrasa el lanzamiento 3-6 meses; (3) los modelos
  auto-hospedables hoy quedan por debajo de los frontera en razonamiento, atacando
  justo el diferenciador ("te entiende"); (4) exige talento de MLOps escaso y caro.
