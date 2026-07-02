# 005 — Documentation Standard

| Metadato | Valor |
|----------|-------|
| Versión | 1.0 |
| Estado | 🟢 Vigente |
| Ámbito | Cómo se escribe, estructura y versiona TODA la documentación de mindOS |
| Depende de | [002](./002_ENGINEERING_CONSTITUTION.md), [003](./003_DECISION_FRAMEWORK.md) |
| Última actualización | 2026-07-02 |

## 1. Anatomía obligatoria de un documento
Todo documento (gobernanza y cadena de fundación) cumple:
1. **Título** en formato `# NNN — Título` (serie 000) o el título canónico de la cadena (#00–#08).
2. **Tabla de metadatos** al inicio, con al menos: `Versión`, `Estado`, `Ámbito` (o `Autor`), `Depende de`, `Última actualización`.
3. Cuerpo denso y claro: tablas, listas numeradas, sin relleno.
4. **Tabla de "Historial de versiones"** al pie: `| Versión | Fecha | Cambios |`.

## 2. Versionado semántico de documentos
- **MAYOR (x.0):** cambio que altera decisiones o invalida contenido previo.
- **MENOR (1.x):** añadidos o aclaraciones que no contradicen lo anterior.
- Cada cambio deja una fila en el historial con fecha y motivo. Un documento 🟢 nunca se edita sin registrar el cambio.

## 3. Nomenclatura
- **Cadena de fundación:** prefijo numérico `#00`–`#08` en carpetas `NN-nombre/`.
- **Serie de gobernanza:** prefijo `000`–`012` en `docs/000_SYSTEM/`.
- **ADRs:** archivos individuales `ADR-NNNN` con cero-padding en `docs/02-architecture/adr/` (ver [003](./003_DECISION_FRAMEWORK.md) §7).

## 4. Estados y firmeza
**Estados de documento:**
- **Borrador** — redactado, no validado.
- 🟢 **Aprobado / Vigente** — validado y en vigor.
- 🔴 **Superado** — reemplazado por un ADR o documento posterior (mantiene cabecera de aviso).

**Niveles de firmeza en el cuerpo** (para recomendaciones y decisiones):
- 🟢 firme · 🟠 opinión fuerte · ⚪️ tentativa.

## 5. Enlaces y trazabilidad
- Enlaces **relativos** entre documentos (`./`, `../`).
- Cada documento declara de qué depende en su fila **`Depende de`**.
- Para referencias a archivos del repo se usa la sintaxis `#[[file:ruta]]` cuando el destino es un archivo de código o recurso, y enlaces markdown relativos para documentos.

## 6. REGLA: cabecera de aviso al superseder 🟢
Cuando un ADR **supersede** total o parcialmente un documento, ese documento **DEBE** llevar, justo bajo su título, una cabecera de aviso que enlace al ADR y resuma qué quedó superado — tal como ya hacen [#01 PRD](../01-product/prd.md) y [#02 Technical Architecture](../02-architecture/technical-architecture.md) respecto de [ADR-010](../02-architecture/adr/ADR-010-final-stack-and-two-backends.md).

**ORDEN pendiente:** el [#08 Roadmap Técnico](../08-roadmap/technical-roadmap.md) está afectado por ADR-010 (aún describe "backend FastAPI + frontend React" en F0 y "auth vía proveedor gestionado" en F0/F1) pero **hoy no lleva la cabecera de aviso**. Se ordena aplicarla y corregir la deriva. Esto queda registrado como riesgo [R-004](./012_RISK_AND_DEBT_REGISTER.md).

Formato de la cabecera:
```markdown
> ⚠️ **REVISADO por [ADR-XXXX](ruta) (fecha):** resumen de qué decisiones
> de este documento quedan superadas. El resto sigue vigente.
```

## 7. Estilo
Nivel de referencia: Stripe / Linear / Notion. Denso, escaneables, orientado a decisión. Emojis solo con significado (estado/firmeza), nunca decorativos.

## Historial de versiones
| Versión | Fecha | Cambios |
|---------|-------|---------|
| 1.0 | 2026-07-02 | Estándar documental inicial + regla de cabecera de aviso y orden sobre #08. |
