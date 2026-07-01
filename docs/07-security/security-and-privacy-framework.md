# mindOS — Security & Privacy Framework

> **Documento #07 de la cadena documental.**
> Deriva de todos los documentos anteriores; toca especialmente
> [Vision (#00)](../00-foundation/vision-and-problem-statement.md) (principio de
> producto #5), [Data Model (#03)](../03-data/data-architecture-and-domain-model.md),
> [API (#04)](../04-api/api-design-specification.md) e
> [Infra (#06)](../06-infrastructure/infrastructure-and-deployment-strategy.md).
> Define **cómo protegemos los datos más íntimos del usuario y qué políticas de
> privacidad y cumplimiento aplicamos.**
>
> ⚠️ **REVISADO por [ADR-010](../02-architecture/adr/ADR-010-final-stack-and-two-backends.md)
> (2026-07-01):** la decisión P3 cambió de **comprar** auth gestionada a
> **construir** autenticación JWT propia en NestJS. Los controles de seguridad
> de este documento (hashing fuerte, tokens de vida corta + refresh, rate
> limiting, protección contra fuerza bruta, MFA para operaciones sensibles) se
> mantienen como requisitos obligatorios de esa implementación propia.

| Metadato | Valor |
|----------|-------|
| Versión | 0.1 (borrador para revisión) |
| Estado | 🟢 Aprobado |
| Autor | CTO |
| Depende de | #00–#06 |
| Última actualización | 2026-07-01 |

---

## 0. Propósito y postura

mindOS almacena el modelo más íntimo que existe de una persona: su vida,
trabajo, relaciones y decisiones. La confianza no es una feature: es la
condición para que el producto exista (principio de producto #5, #00).

> **Postura de seguridad:** tratamos cada dato del usuario como si fuera
> confidencial de máxima sensibilidad, por defecto y sin excepciones. La
> seguridad y la privacidad se diseñan desde el inicio (*security & privacy by
> design*), no se añaden después.

Este documento contiene **3 decisiones que requirieron tu input explícito**
(marcadas 🔴). **Las tres han sido decididas** (ver §1). Este documento ya
refleja esas decisiones y está listo para aprobación.

## 0.1 Decisiones tomadas (resumen)

| # | Decisión | Resolución |
|---|----------|-----------|
| **P1** | Proveedor de LLM + privacidad | ✅ Aceptado: LLM externo con compromiso contractual de *no-training* + DPA. La IA externa **procesa y olvida**; mindOS es quien guarda los datos del usuario. |
| **P2** | Mercado inicial + cumplimiento | ✅ Lanzamiento en **Brasil y Latinoamérica**. **GDPR como estándar base** (cubre además la **LGPD** brasileña). Residencia de datos en región de las Américas. |
| **P3** | Autenticación build vs. buy | ✅ **Comprar** un proveedor de identidad gestionado, empezando con su **plan gratuito**. |

---

## 1. Decisiones que requerían tu input (🔴 → ✅ resueltas)

| # | Decisión | Resolución | Sección |
|---|----------|-----------|---------|
| **P1** | **Proveedor de LLM** y su postura de privacidad | ✅ Aceptada la recomendación (no-training + DPA). | §3 |
| **P2** | **Alcance de cumplimiento** + mercado inicial | ✅ Brasil/Latinoamérica; GDPR base (+ LGPD). | §8 |
| **P3** | **Autenticación: construir vs. comprar** | ✅ Comprar (plan gratuito inicial). | §4 |

El resto del framework (cifrado, controles de acceso, manejo de incidentes) son
decisiones técnicas que asume el CTO.

---

## 2. Modelo de amenazas (resumen)

| Amenaza | Vector | Mitigación principal |
|---------|--------|----------------------|
| Fuga de datos entre usuarios | Bug de aplicación | Aislamiento por `user_id` + **RLS** en BD (#03). |
| Acceso no autorizado | Credenciales robadas / sesión | Auth robusta, tokens de vida corta, MFA (§4). |
| Exposición en tránsito | Interceptación de red | TLS obligatorio en todo (§5). |
| Exposición en reposo | Acceso al almacenamiento | Cifrado en reposo (§5). |
| Fuga vía LLM externo | Datos enviados a terceros | Minimización + contrato + (futuro) modelos propios (§3). |
| Secretos filtrados | Claves en repo/logs | Gestor de secretos + escaneo en CI (#05/#06). |
| Amenaza interna | Acceso de empleados | Mínimo privilegio + auditoría de accesos (§6). |
| Pérdida de datos | Fallo de infraestructura | Backups probados + DR (#06). |

---

## 3. 🔴 P1 — Proveedor de LLM y privacidad de datos

**Contexto:** por ADR-09, el MVP usa un LLM externo. Enviar los datos del
usuario a un tercero es el mayor riesgo de privacidad del producto.

**Requisitos innegociables para cualquier proveedor elegido:**
- Compromiso contractual de **no entrenar** con nuestros datos (endpoints
  enterprise/API con *zero data retention* o retención mínima acordada).
- **No** uso de los datos para ningún fin más allá de servir la respuesta.
- Cumplimiento (SOC 2 / ISO 27001) y acuerdo de procesamiento de datos (DPA).
- Preferencia por **residencia de datos** controlable (región).

**Mitigaciones técnicas que aplicamos independientemente del proveedor:**
- **Minimización:** al LLM se envía solo el fragmento necesario para cada
  operación, nunca el grafo completo (#03 §12).
- **Redacción/anonimización** de PII evidente cuando sea posible antes del envío.
- Registro de qué se envía (metadato, no contenido) para auditoría.

**Recomendación de CTO:** elegir un proveedor de primer nivel con oferta
enterprise que garantice *no-training* y DPA sólido. Esto cumple el requisito de
privacidad para el MVP sin el costo de modelos propios, y mantiene la puerta a
migrar a modelos propios (ADR-09) como evolución de marca.

> **Decisión (P1): ✅ ACEPTADA.** Se adopta la postura de LLM externo con
> garantías contractuales (*no-training* + DPA) para el MVP, con la puerta
> abierta a modelos propios (ADR-09) como evolución futura.

---

## 4. 🔴 P3 — Autenticación e identidad

**Opciones:**
- **Comprar (recomendado para MVP):** proveedor de identidad gestionado
  (p. ej. Auth0/Clerk/Cognito). Delega el manejo seguro de contraseñas, MFA,
  recuperación y flujos sociales a especialistas.
- **Construir:** control total, sin costo de licencia, pero asumes todo el
  riesgo de seguridad de autenticación (el área donde los errores son más
  caros).

**Recomendación de CTO: comprar.** La autenticación es un problema resuelto y
peligroso de reinventar. Un proveedor gestionado reduce riesgo y acelera el MVP.
La capa de identidad (#02) abstrae el proveedor, así que migrar después es
viable.

**Controles independientes del proveedor:**
- Tokens de acceso de **vida corta** + refresh (#04).
- **MFA** disponible; obligatorio para operaciones sensibles (borrado de cuenta).
- Contraseñas: nunca en claro; hashing fuerte (a cargo del proveedor).
- Protección contra fuerza bruta y *credential stuffing* (rate limiting, #04).

> **Decisión (P3): ✅ COMPRAR.** Se usará un proveedor de identidad gestionado,
> empezando con su **plan gratuito** (cubre las etapas iniciales sin costo; el
> gasto llega solo cuando hay volumen de usuarios que lo justifica). Provider
> concreto (Auth0 / Clerk / Cognito u otro) se elige en implementación.

---

## 5. Cifrado

| Estado | Control |
|--------|---------|
| **En tránsito** | TLS 1.2+ en todas las conexiones (cliente↔API, API↔BD, API↔LLM). Sin excepciones. |
| **En reposo** | Cifrado a nivel de disco/almacenamiento gestionado (BD, backups, object storage). |
| **Secretos** | Gestor de secretos del proveedor; rotación periódica; nunca en repo ni logs. |
| **Datos ultra-sensibles (futuro)** | Evaluar cifrado a nivel de campo para categorías especiales (salud, finanzas — V4 del PRD). |

> **Nota honesta:** el cifrado *end-to-end* real (donde ni nosotros podemos leer
> los datos) es incompatible con que la IA los procese en servidor. No lo
> prometemos en el MVP. Si se convierte en requisito de marca, es un rediseño
> mayor (procesamiento en cliente / modelos locales) que se evalúa por separado.

---

## 6. Control de acceso y amenaza interna

- **Mínimo privilegio:** cada componente y persona accede solo a lo que necesita.
- **Acceso de empleados a datos de producción:** restringido, auditado y
  justificado. Por defecto, ningún ingeniero accede a datos reales de usuarios.
- **Auditoría:** registro de accesos administrativos a datos sensibles (quién,
  cuándo, por qué).
- **Entornos separados:** datos reales solo en producción; dev/staging usan datos
  sintéticos o anonimizados (#06 §1).

---

## 7. Derechos del usuario sobre sus datos

Implementados como funcionalidad de producto (no solo política):

| Derecho | Implementación | Referencia |
|---------|----------------|-----------|
| **Acceso/portabilidad** | Exportación completa del grafo en formato abierto. | FR-X.3, API #04 |
| **Borrado ("derecho al olvido")** | Borrado permanente en cascada de todo el grafo + purga de backups según política. | FR-X.4, #03 §12 |
| **Rectificación** | El usuario corrige nodos/conexiones (feedback loop). | FR-2.4 |
| **Transparencia** | Trazabilidad de procedencia de cada dato; citas de fuentes en respuestas. | FR-X.5, FR-3.3 |
| **Consentimiento** | Consentimiento explícito para el procesamiento por IA en el onboarding. | §8 |

---

## 8. 🔴 P2 — Privacidad y cumplimiento normativo  ✅ RESUELTO

**Mercado inicial decidido: Brasil y Latinoamérica (países de América).**

Marcos aplicables al mercado objetivo:
- **LGPD** (Brasil, *Lei Geral de Proteção de Dados*): ley de privacidad
  brasileña, muy alineada con GDPR (derechos del titular, base legal,
  minimización, notificación de brechas).
- **GDPR** (Unión Europea): el estándar más estricto; lo adoptamos como base
  aunque no lancemos en la UE de inmediato.
- Leyes nacionales de otros países de la región (México LFPDPPP, Argentina,
  Colombia, Chile, etc.), en su mayoría cubiertas al cumplir GDPR/LGPD.

**Decisión (P2): ✅ GDPR como estándar base desde el día uno.** Razón: GDPR es
el superconjunto más estricto; cumplirlo satisface simultáneamente la **LGPD
brasileña** y las leyes del resto de Latinoamérica, y evita un rediseño costoso
al expandirse. Las capacidades ya diseñadas (export, borrado, trazabilidad,
consentimiento, minimización) cubren la mayor parte.

**Residencia de datos:** región de despliegue en **las Américas** (p. ej. una
región cloud en Brasil/São Paulo o EE. UU. según latencia y costo, #06),
cercana al mercado objetivo para rendimiento y cumplimiento local.

**Elementos de cumplimiento a formalizar (con asesoría legal, no solo técnica):**
- Política de privacidad y términos de servicio claros (en portugués y español).
- Base legal del procesamiento (consentimiento).
- DPA con cada subprocesador (incluido el proveedor de LLM, P1).
- Proceso de notificación de brechas (plazos LGPD/GDPR).
- Registro de actividades de tratamiento.

> **Nota:** el cumplimiento legal formal requiere **asesoría jurídica
> profesional** (idealmente con especialización en LGPD y GDPR). Este documento
> cubre la arquitectura técnica que lo habilita, no sustituye el consejo legal.

---

## 9. Retención de datos

- **Datos activos:** se conservan mientras la cuenta esté activa (el valor del
  producto *es* la memoria a largo plazo, #00).
- **Nodos fríos:** archivado (#03 §11), no borrado — la memoria histórica es un
  activo del usuario.
- **Tras borrado de cuenta:** purga de datos productivos inmediata; purga de
  backups en un plazo definido (p. ej. ≤ 30 días) documentado al usuario.
- **Logs:** sin PII sensible; retención acotada (p. ej. 30-90 días) según
  necesidad operativa (#06).

> Política concreta de plazos → se afina con la decisión de cumplimiento (P2) y
> asesoría legal.

---

## 10. Gestión de incidentes

- **Detección:** alertas de seguridad (accesos anómalos, picos de error, fugas
  de secretos) integradas en la observabilidad (#06).
- **Respuesta:** procedimiento definido de contención, evaluación, notificación
  y post-mortem. Sin culpa individual; foco en corregir el sistema.
- **Notificación:** a usuarios y autoridades según obligación legal (GDPR: 72h
  para ciertas brechas).
- **Post-mortem:** documentado, con acciones correctivas rastreables.

---

## 11. Seguridad en el ciclo de desarrollo

Refuerza lo definido en #05/#06:
- Escaneo de secretos y dependencias en CI (gate obligatorio).
- Revisión de código con la seguridad como prioridad 2 (#05 §5).
- Validación estricta de entradas (Pydantic).
- Principio de mínima exposición de datos al LLM en cada cambio.
- Actualización oportuna de dependencias con vulnerabilidades.

---

## 12. Resumen de decisiones (✅ resueltas)

| # | Decisión | Resolución |
|---|----------|-----------|
| **P1** | Proveedor de LLM + privacidad | ✅ Proveedor externo con *no-training* + DPA. La IA procesa y olvida; mindOS guarda los datos. |
| **P2** | Cumplimiento + mercado inicial | ✅ Brasil/Latinoamérica; GDPR base (cubre LGPD); residencia en las Américas. |
| **P3** | Auth: construir vs. comprar | ✅ Comprar proveedor gestionado, plan gratuito inicial. |

> Con P1, P2 y P3 resueltas, este documento queda **listo para aprobación**.

---

## 13. Preguntas abiertas (para implementación)

1. Proveedor de LLM concreto (depende de P1).
2. Proveedor de identidad concreto (depende de P3).
3. Regiones de despliegue y residencia de datos (depende de P2 y #06).
4. Plazos exactos de retención y purga de backups (depende de P2 + legal).

---

## Historial de versiones

| Versión | Fecha | Autor | Cambios |
|---------|-------|-------|---------|
| 0.1 | 2026-07-01 | CTO | Borrador inicial. Postura de seguridad/privacidad by design, modelo de amenazas, tres decisiones que requieren input del founder (proveedor LLM, cumplimiento, auth), cifrado, control de acceso, derechos del usuario, cumplimiento (GDPR by default), retención, gestión de incidentes y seguridad en el ciclo de desarrollo. |
| 0.2 | 2026-07-01 | Founder + CTO | Resueltas P1 (LLM externo con no-training + DPA), P2 (mercado Brasil/Latinoamérica; GDPR base cubriendo LGPD; residencia en las Américas) y P3 (comprar auth gestionada, plan gratuito). Documento listo para aprobación. |
