# Cómo ejecutar el examen de la IA (paso a paso)

Esta guía es para cualquier persona, **sin conocimientos técnicos** y **sin usar
la terminal**. Todo se hace desde el navegador, haciendo clic.

El "examen" comprueba si la IA de mindOS **entiende bien** los textos (extrae
tareas, personas, temas, etc.). Al final verás una tabla con notas y un
veredicto de **pasa / no pasa**.

> ¿Tienes prisa y solo quieres ver cómo funciona el botón? Salta al final:
> **"Probar sin clave"**. No mide la calidad real, pero no cuesta nada.

---

## Paso 1 · Conseguir una clave de OpenAI

La clave es como una contraseña que permite a la IA usar el motor de OpenAI.

1. Entra en **https://platform.openai.com/api-keys**
2. Inicia sesión (o crea una cuenta).
3. Pulsa el botón para crear una clave nueva (**Create new secret key**).
4. Copia la clave. Empieza por `sk-...`. **Guárdala**, porque solo se muestra una vez.

> **¿Cuesta dinero?** Sí, es un servicio de pago, pero para este examen es
> **muy barato** (son solo unos pocos textos de prueba, del orden de céntimos).
> Aun así, revisa los precios en tu cuenta de OpenAI antes de empezar.

---

## Paso 2 · Guardar la clave en el repositorio (una sola vez)

La clave se guarda **cifrada** dentro de GitHub. Nadie más puede verla, ni
siquiera aparece en los registros del examen.

1. En la página del repositorio en GitHub, pulsa la pestaña **Settings**
   (Ajustes, arriba del todo).
2. En el menú de la izquierda, abre **Secrets and variables** y pulsa **Actions**.
3. Pulsa el botón verde **New repository secret**.
4. En el campo **Name** escribe **exactamente** (respeta mayúsculas):

   ```
   OPENAI_API_KEY
   ```

5. En el campo **Secret** pega la clave que copiaste en el Paso 1.
6. Pulsa **Add secret**.

Ya está. Solo hay que hacer esto una vez (o cuando cambies de clave).

---

## Paso 3 · Ejecutar el examen

1. En el repositorio, pulsa la pestaña **Actions** (arriba).
2. En la lista de la izquierda, elige el workflow **"F2 comprehension eval"**.
3. A la derecha aparece un botón **Run workflow**. Púlsalo.
4. Se abre un pequeño formulario:
   - **provider**: déjalo en **openai** (es la calidad real).
   - **gate**: déjalo **desactivado** (false) la primera vez. Si lo activas, el
     examen se marca en rojo cuando no llega a la nota mínima.
5. Pulsa el botón verde **Run workflow**.

Espera un momento (normalmente uno o dos minutos). Verás que aparece una nueva
ejecución en la lista, primero con un círculo amarillo (en curso) y luego con un
check verde (terminada) o una cruz roja (falló).

---

## Paso 4 · Ver el resultado

1. Haz clic en la ejecución que acaba de aparecer en la lista.
2. En la parte de arriba verás la sección **Summary** (Resumen).
3. Ahí aparece el **reporte completo**: la tabla de métricas, el coste y el
   **veredicto** (`GATE PASSED` = pasa, `GATE FAILED` = no pasa).

No necesitas mirar los "logs" ni entender de código: todo lo importante está en
el Summary.

---

## Qué significan las métricas (resumen rápido)

| Métrica | Qué mide | Listón (mínimo para pasar) |
|---------|----------|-----------------------------|
| **F1 entities** | Cómo de bien identifica las cosas del texto (tareas, personas, temas). Cuanto más cerca de 1, mejor. | **≥ 0,80** |
| **task precision** | De las tareas que propone, cuántas son de verdad (no inventadas). | **≥ 0,85** |
| **hallucination** | Cuánto "se inventa" cosas que no están en el texto. Cuanto más bajo, mejor. | **≤ 0,05** |
| **mean cost/capture** | Cuánto cuesta de media analizar un texto (en dólares). | **≤ $0,01** |

En dos líneas: las tres primeras miden **si entiende bien y no inventa**, y la
última mide **si es barato**. El veredicto final (**pasa / no pasa**) resume si
se cumplen todos los mínimos a la vez.

> Los mínimos son **provisionales**: están pendientes de confirmación por el
> responsable del producto y pueden ajustarse más adelante.

---

## Probar sin clave (opcional)

Si aún no tienes clave o solo quieres ver el botón funcionando:

1. Sigue el **Paso 3**, pero en **provider** elige **fake**.
2. Ejecuta y mira el **Summary** igual que en el **Paso 4**.

El modo **fake** es una **línea base** offline: no usa OpenAI, no cuesta nada y
es 100 % reproducible. **No refleja la calidad real** de la IA; solo sirve para
comprobar que el examen se ejecuta y para tener una referencia básica.
