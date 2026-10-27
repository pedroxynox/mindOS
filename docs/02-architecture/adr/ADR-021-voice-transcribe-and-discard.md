# ADR-021 — Notas de voz: transcribir al recibir y descartar el audio

> **Architecture Decision Record.** Cierra la voz, diferida desde F1 y F2
> (diseño de comprensión §19). Sustituye, para el MVP, el camino "presign → S3
> → `audio_ref` → el worker descarga el blob" previsto en F1 §9 y ADR-012.

| Metadato | Valor |
|----------|-------|
| Estado | 🟢 Aceptado |
| Fecha | 2026-10-27 |
| Autor | CPTO |
| Relacionado | [ADR-012](./ADR-012-canonical-stack.md) (almacenamiento de objetos), [ADR-007](./ADR-007-aiprovider-abstraction.md) (`AIProvider`), [ADR-010](./ADR-010-final-stack-and-two-backends.md) |

---

## Contexto

F1 diseñó la voz así: la app pide una URL presignada, sube el audio a S3/R2 y
crea la captura con un `audio_ref`; después, el worker descarga el blob y lo
transcribe. Ese camino nunca se encendió en producción:

- Render no tiene `S3_*` configurado.
- Usarlo exige que el founder abra una cuenta de Cloudflare R2 con tarjeta.
- El worker tendría que descargar blobs. Además, en web la app no tenía forma de
  leer el audio (`file_reader_web` lanzaba una excepción).

La voz es lo que más falta en la captura y el founder pidió activarla ya, sin
pasar al plan de pago.

## Decisión

1. **Transcribir al recibir:** `POST /v1/captures/voice`, con el audio como
   cuerpo binario (`audio/*`, ≤ 10 MB), `Idempotency-Key` y metadatos en la URL.
   - La API reenvía el audio a la IA (`POST /internal/transcribe`, secreto
     interno).
   - La IA llama al proveedor de transcripción y devuelve el texto.
   - La API crea la captura con `origin=voice`, `body` = transcripción y
     `attributes.transcription{provider, model, duration_s}`, y registra el
     coste en `llm_usage` en la misma transacción RLS.
   - Después encola la comprensión igual que una captura de texto.
2. **El audio no se guarda en ningún servidor:** solo vive en memoria durante
   la petición. En el dispositivo queda en el outbox de Drift (schema v2:
   `audio_data`) hasta sincronizarse y luego se libera.
3. **Idempotencia** por `Idempotency-Key` con un hash que incluye el sha256 del
   audio: un reintento devuelve la captura original **sin volver a
   transcribir**, y no se paga dos veces.
4. **Errores:**
   - Si la transcripción no está disponible (IA dormida o proveedor caído): 503.
     La app reintenta con backoff y la nota sigue pendiente.
   - Si el audio está vacío, no es válido o no se entiende nada: 422/415/413. Es
     terminal y se muestra al usuario.
5. **Modelo:** `gpt-transcribe` de OpenAI, el recomendado para archivos
   (whisper-1 y gpt-4o-transcribe se retiran el 2027-02-26).
   - Pistas de idioma: `es`, `pt`, `en`.
   - Coste: unos $0.0045 por minuto.
   - Groq (`whisper-large-v3-turbo`) queda como alternativa barata.
   - Gemini no ofrece transcripción por esta vía.

## Consecuencias

- **A favor:**
  - Voz funcionando en web y móvil sin cuentas nuevas ni almacenamiento de pago.
  - **Privacidad:** "mindOS no guarda tu voz".
  - El worker no cambia: para él una nota de voz es texto.
- **En contra:**
  - No se puede re-transcribir más tarde con un modelo mejor, porque el audio ya
    no existe.
  - La API depende de forma síncrona de la IA. Con el plan gratis, una IA
    dormida retrasa la nota unos 30-60 s; el outbox lo absorbe.
- **Lo que se conserva:** `POST /v1/captures/audio-upload`, `BlobStorageService`
  y `BlobJanitor` siguen en el código, inactivos, por si un día se quiere
  conservar el audio (criterio de reactivación: re-transcripción o
  diarización).

## Alternativas consideradas

- **(a) Encender el camino S3/R2.** Exige cuenta y tarjeta en Cloudflare, más el
  lector de blobs en el worker. Además, almacenar voz agrava la privacidad. Se
  rechazó para el MVP.
- **(b) Transcribir en el dispositivo** (Web Speech API / `speech_to_text`). Es
  gratis, pero desigual entre navegadores (no funciona en Firefox), en Chrome
  envía el audio a Google y la calidad es inferior en es/pt. Se rechazó.
- **(c) Meter el audio en el job de Redis.** El plan gratis de Redis tiene
  ~25 MB y `noeviction`: unas pocas notas lo llenan. Se rechazó.
