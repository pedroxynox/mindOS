import { PayloadTooLargeException } from '@nestjs/common';
import { Readable } from 'node:stream';

/**
 * Collect a request's raw body (e.g. a voice note) with a hard size limit.
 *
 * Bodies over `limit` are drained but NOT buffered (so memory stays bounded and
 * the client still receives a clean 413 instead of a reset connection). A
 * declared `Content-Length` over the limit is rejected before reading.
 */
export function readRawBody(
  req: Readable & { headers?: Record<string, unknown> },
  limit: number,
): Promise<Buffer> {
  const declared = Number(req.headers?.['content-length']);
  if (Number.isFinite(declared) && declared > limit) {
    req.resume(); // drain and discard
    return Promise.reject(tooLarge(limit));
  }

  return new Promise((resolve, reject) => {
    const chunks: Buffer[] = [];
    let size = 0;
    let overflow = false;
    req.on('data', (chunk: Buffer) => {
      size += chunk.length;
      if (size > limit) {
        overflow = true;
        chunks.length = 0;
        return;
      }
      chunks.push(chunk);
    });
    req.on('end', () =>
      overflow ? reject(tooLarge(limit)) : resolve(Buffer.concat(chunks)),
    );
    req.on('error', reject);
  });
}

function tooLarge(limit: number): PayloadTooLargeException {
  return new PayloadTooLargeException({
    code: 'audio_too_large',
    message: `La nota de voz supera el máximo de ${Math.round(limit / (1024 * 1024))} MB.`,
  });
}
