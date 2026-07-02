# ADR-011 — Definición de Hecho de F0 y estrategia de infraestructura

> **Architecture Decision Record.** Refina la Definición de Hecho de la fase **F0**
> definida en [Roadmap #08](../../08-roadmap/technical-roadmap.md) y se apoya en
> [Infra #06](../../06-infrastructure/infrastructure-and-deployment-strategy.md) y [ADR-010](./ADR-010-final-stack-and-two-backends.md).

| Metadato | Valor |
|----------|-------|
| Estado | 🟠 Propuesto (pendiente de decisión del founder) |
| Fecha | 2026-07-02 |
| Autor | CPTO |
| Depende de | ADR-010, #06, #08 |
| Afecta | #08 (Definición de Hecho de F0); riesgo R-003 (012) |

---

## Contexto

F0 se venía tratando como "terminada", pero su Definición de Hecho en el #08 exige
*"un commit a `main` despliega automáticamente a staging"* con CI/CD verde e **IaC**.
El estado real verificado en el repo es:

- ✅ CI verde en las 3 apps (api/ai/mobile): lint + tipos + tests + build.
- ✅ `docker-compose` local (postgres+pgvector, redis, api, ai).
- ❌ Sin despliegue continuo (CD), sin entorno de staging, sin IaC.

Por tanto F0 está ≈70% y la señal de "F0 hecho" era falsa (riesgo **R-003**). Hay
que decidir cómo cerrarla. Opciones:

- **(A) Construir CD + IaC completos ahora** para cumplir la DoD tal cual está.
- **(B) Eliminar el CD de la DoD** y quedarnos solo con `docker-compose` local.
- **(C) Vía intermedia:** CD mínimo + diferir la infraestructura pesada.

## Decisión (propuesta)

Se adopta **(C)**. Se redefine la Definición de Hecho de F0:

**F0 se considera Hecho cuando:**
1. CI verde en `api`/`ai`/`mobile` (ya cumplido).
2. Build y publicación de imágenes de contenedor de `api` y `ai` en un registry vía CI.
3. Despliegue continuo de esas imágenes a **UN único entorno de staging** sobre un
   host/PaaS de contenedores simple (**sin Kubernetes**).
4. **IaC mínima y declarativa** que describa SOLO ese entorno de staging.

**Se difiere explícitamente** a una fase de infraestructura pre-beta (solapada con
F4, antes de F5): Kubernetes, entorno de producción aislado, auto-scaling, IaC
completa y observabilidad avanzada.

`docker-compose` se mantiene como entorno de desarrollo local canónico.

## Justificación

Coherente con el principio **"riesgo primero"** del propio #08 y con la
**simplicidad operativa** del #02. El mayor riesgo del proyecto es la calidad de
comprensión (F2), no el pipeline de despliegue. Construir K8s + IaC completa hoy es
sobre-ingeniería antes de validar el producto. Pero eliminar el CD por completo
reintroduciría el riesgo de integración tardía que F0 debía eliminar. El mínimo
(2)(3)(4) preserva ese valor a bajo coste.

## Consecuencias

**Positivas**
- F0 se cierra con un criterio realista y de bajo coste.
- Se mantiene un despliegue reproducible y automatizado desde temprano.
- El esfuerzo se concentra en F1/F2 (el valor y el riesgo reales).

**Negativas (aceptadas conscientemente)**
- Staging único, sin producción aislada, hasta la fase de infraestructura pre-beta.
- Deuda de infraestructura consciente y registrada, a pagar antes de F5.

**Si se rechaza y se elige (A)**
- Se retrasa el inicio de F1 para construir infraestructura que todavía no aporta
  valor de producto.

## Estado y siguiente paso

**PROPUESTO.** Cambia la DoD de F0, por lo que requiere aprobación del founder
(decisión Founder+CPTO según 001/003). Al aprobarse: pasa a 🟢 Aceptado, se
actualiza la sección F0 del #08 y se cierra R-003 en el registro (012).

## Nota de numeración

Este ADR usa el patrón de 3 dígitos de ADR-010 por consistencia con el único ADR
individual existente. La migración a cero-padding de 4 dígitos (ADR-0010, ADR-0011…)
y de los ADR-01..09 embebidos en #02 está registrada como deuda **D-004** (012).

## Historial de versiones

| Versión | Fecha | Autor | Cambios |
|---------|-------|-------|---------|
| 1.0 | 2026-07-02 | CPTO | Propuesta inicial: DoD mínima de F0 + diferimiento de infra pesada. |
