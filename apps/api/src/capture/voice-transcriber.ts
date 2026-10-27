import {
  HttpException,
  Injectable,
  Logger,
  ServiceUnavailableException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

/** What the AI service returns for one voice note. */
export interface Transcript {
  text: string;
  provider: string;
  model: string;
  duration_s: number | null;
  cost_usd: number;
}

/** Port so the capture service can be tested without the AI service. */
export const VOICE_TRANSCRIBER = Symbol('VOICE_TRANSCRIBER');

export interface VoiceTranscriber {
  transcribe(
    audio: Buffer,
    contentType: string,
    durationMs?: number,
  ): Promise<Transcript>;
}

/**
 * Forwards a voice note to the AI service's internal speech-to-text endpoint
 * (ADR-021) over the shared-secret channel. The audio only ever lives in memory
 * for the duration of the request — it is never stored by the API either.
 */
@Injectable()
export class HttpVoiceTranscriber implements VoiceTranscriber {
  private readonly logger = new Logger(HttpVoiceTranscriber.name);

  constructor(private readonly config: ConfigService) {}

  async transcribe(
    audio: Buffer,
    contentType: string,
    durationMs?: number,
  ): Promise<Transcript> {
    const baseUrl =
      this.config.get<string>('AI_SERVICE_URL') ?? 'http://localhost:8000';
    const secret = this.config.get<string>('QUERY_INTERNAL_SECRET');
    if (!secret) {
      this.logger.error('QUERY_INTERNAL_SECRET is not set; voice is disabled.');
      throw this.unavailable();
    }

    const url = new URL('/internal/transcribe', baseUrl);
    if (durationMs && durationMs > 0) {
      url.searchParams.set('duration_ms', String(Math.round(durationMs)));
    }

    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 90_000);
    let res: Response;
    try {
      res = await fetch(url, {
        method: 'POST',
        headers: { 'content-type': contentType, 'x-internal-token': secret },
        body: new Uint8Array(audio),
        signal: controller.signal,
      });
    } catch (err) {
      this.logger.warn(
        `AI service unreachable for transcription: ${String(err)}`,
      );
      throw this.unavailable();
    } finally {
      clearTimeout(timeout);
    }

    if (res.status === 413 || res.status === 415 || res.status === 422) {
      // The audio itself is not acceptable: a terminal client error.
      throw new HttpException(
        {
          code: res.status === 415 ? 'unsupported_audio' : 'invalid_audio',
          message: 'No pude usar esa grabación. Intenta grabar de nuevo.',
        },
        res.status,
      );
    }
    if (!res.ok) {
      this.logger.warn(`AI transcription returned ${res.status}`);
      throw this.unavailable();
    }

    const body = (await res.json()) as Partial<Transcript>;
    return {
      text: typeof body.text === 'string' ? body.text : '',
      provider: typeof body.provider === 'string' ? body.provider : 'unknown',
      model: typeof body.model === 'string' ? body.model : 'unknown',
      duration_s: typeof body.duration_s === 'number' ? body.duration_s : null,
      cost_usd: typeof body.cost_usd === 'number' ? body.cost_usd : 0,
    };
  }

  private unavailable(): ServiceUnavailableException {
    return new ServiceUnavailableException({
      code: 'transcription_unavailable',
      message:
        'No pude transcribir tu nota ahora mismo. Se reintentará sola en unos segundos.',
    });
  }
}
