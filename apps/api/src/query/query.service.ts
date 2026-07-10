import {
  Injectable,
  Logger,
  ServiceUnavailableException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import {
  AiQueryPayload,
  QueryResponse,
  toQueryResponse,
} from './query.mapper';

/**
 * Bridges the authenticated `POST /v1/query` to the AI service's internal RAG
 * endpoint. The end user is already authenticated by the JwtAuthGuard; this
 * service forwards the resolved `userId` plus the question over a shared-secret
 * channel, so the AI service is never exposed publicly.
 *
 * A generous timeout absorbs the free-tier cold start of the AI service.
 */
@Injectable()
export class QueryService {
  private readonly logger = new Logger(QueryService.name);

  constructor(private readonly config: ConfigService) {}

  async ask(userId: string, question: string): Promise<QueryResponse> {
    const baseUrl =
      this.config.get<string>('AI_SERVICE_URL') ?? 'http://localhost:8000';
    const secret = this.config.get<string>('QUERY_INTERNAL_SECRET');

    if (!secret) {
      this.logger.error('QUERY_INTERNAL_SECRET is not set; query is disabled.');
      throw new ServiceUnavailableException({
        code: 'query_unavailable',
        message: 'La búsqueda inteligente no está disponible por ahora.',
      });
    }

    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 90_000);

    let res: Response;
    try {
      res = await fetch(`${baseUrl}/internal/query`, {
        method: 'POST',
        headers: {
          'content-type': 'application/json',
          'x-internal-token': secret,
        },
        body: JSON.stringify({ user_id: userId, question }),
        signal: controller.signal,
      });
    } catch (err) {
      this.logger.warn(`AI service unreachable: ${String(err)}`);
      throw new ServiceUnavailableException({
        code: 'query_unavailable',
        message:
          'El asistente no está disponible ahora mismo. Inténtalo de nuevo en unos segundos.',
      });
    } finally {
      clearTimeout(timeout);
    }

    if (!res.ok) {
      this.logger.warn(`AI query returned ${res.status}`);
      throw new ServiceUnavailableException({
        code: 'query_unavailable',
        message:
          'No pude generar una respuesta ahora mismo. Inténtalo de nuevo en unos segundos.',
      });
    }

    const payload = (await res.json()) as AiQueryPayload;
    return toQueryResponse(payload);
  }
}
