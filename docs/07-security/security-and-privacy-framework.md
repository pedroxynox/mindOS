# mindOS — Security & Privacy Framework

> **Documento #07 de la cadena documental.**
> Deriva de todos los documentos anteriores; toca especialmente
> [Vision (#00)](../00-foundation/vision-and-problem-statement.md) (principio de
> producto #5), [Data Model (#03)](../03-data/data-architecture-and-domain-model.md),
> [API (#04)](../04-api/api-design-specification.md) e
> [Infra (#06)](../06-infrastructure/infrastructure-and-deployment-strategy.md).
> Define **cómo protegemos los datos más íntimos del usuario y qué políticas de
> privacidad y cumplimiento aplicamos.**

| Metadato | Valor |
|----------|-------|
| Versión | 0.1 (borrador para revisión) |
| Estado | 🟡 En revisión |
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

Este documento contiene **3 decisiones que requieren tu input explícito**
(marcadas 🔴), porque tienen implicaciones de negocio, marca y presupuesto que
no debe tomar el CTO en solitario.

---

## 1. Decisiones que requieren tu input (🔴)

| # | Decisión | Por qué te toca a ti |
|---|----------|----------------------|
| **P1** | **Proveedor de LLM** y su postura de privacidad | Afecta costo, calidad y la promesa de privacidad de marca. |
| **P2** | **Alcance de cumplimiento inicial** (GDPR / CCPA / otros) | Depende de en qué mercados/geografías lanzas primero. |
| **P3** | **Autenticación: construir vs. comprar** | Trade-off entre control, costo y riesgo de seguridad. |

Las presento con recomendación de CTO en las secciones 3, 8 y 4 respectivamente.
El resto del framework (cifrado, controles de acceso, manejo de incidentes) son
decisiones técnicas que sí asumo yo.

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

> **Tu decisión (P1):** ¿te parece aceptable esta postura (LLM externo con
> garantías contractuales) o quieres endurecerla ya? La recomendación es
> aceptarla para el MVP.

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

> **Tu decisión (P3):** ¿comprar (recomendado) o construir la autenticación?

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

## 8. 🔴 P2 — Privacidad y cumplimiento normativo

**El alcance depende de dónde lances primero.** Marcos principales:
- **GDPR** (Unión Europea): el estándar más estricto; exige base legal,
  minimización, derechos del titular, DPA con procesadores, notificación de
  brechas.
- **CCPA/CPRA** (California): derechos de acceso, borrado y opt-out.
- Otros según mercado.

**Recomendación de CTO:** **diseñar cumpliendo GDPR desde el inicio**, aunque no
lances en la UE de inmediato. Razón: GDPR es el superconjunto más estricto;
cumplirlo hace que cumplir los demás sea trivial, y evita un rediseño costoso
cuando quieras expandirte a Europa. Las capacidades ya diseñadas (export,
borrado, trazabilidad, consentimiento, minimización) cubren la mayor parte.

**Elementos de cumplimiento a formalizar (con asesoría legal, no solo técnica):**
- Política de privacidad y términos de servicio claros.
- Base legal del procesamiento (consentimiento).
- DPA con cada subprocesador (incluido el proveedor de LLM, P1).
- Proceso de notificación de brechas.
- Registro de actividades de tratamiento.

> **Nota:** el cumplimiento legal formal requiere **asesoría jurídica
> profesional**. Este documento cubre la arquitectura técnica que lo habilita,
> no sustituye el consejo legal.
>
> **Tu decisión (P2):** ¿en qué mercado(s) lanzas primero? ¿Adoptamos GDPR como
> estándar base desde ya (recomendado)?

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

## 12. Resumen de decisiones pendientes de tu input

| # | Decisión | Recomendación CTO |
|---|----------|-------------------|
| **P1** | Proveedor de LLM + privacidad | Proveedor enterprise con *no-training* + DPA. Aceptar para MVP. |
| **P2** | Alcance de cumplimiento + mercado inicial | Adoptar GDPR como base desde el día uno. |
| **P3** | Auth: construir vs. comprar | Comprar (proveedor gestionado). |

> No marco este documento como listo para aprobar hasta que decidas P1, P2 y P3.

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
