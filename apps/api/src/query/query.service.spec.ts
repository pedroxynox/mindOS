import { ServiceUnavailableException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { QueryService } from './query.service';

/**
 * Unit tests for QueryService: fail-closed when the shared secret is missing,
 * the AI call forwards the resolved userId + secret, upstream failures surface
 * as ServiceUnavailable (never a 500), and a good response is mapped to the
 * client contract. `fetch` is stubbed (no network).
 */
const USER_ID = '11111111-1111-1111-1111-111111111111';

function configWith(values: Record<string, string | undefined>): ConfigService {
  return {
    get: (key: string) => values[key],
  } as unknown as ConfigService;
}

describe('QueryService.ask', () => {
  const realFetch = global.fetch;
  afterEach(() => {
    global.fetch = realFetch;
    jest.restoreAllMocks();
  });

  it('is fail-closed when the internal secret is not configured', async () => {
    const service = new QueryService(
      configWith({ AI_SERVICE_URL: 'http://ai' }),
    );
    await expect(service.ask(USER_ID, 'hola')).rejects.toBeInstanceOf(
      ServiceUnavailableException,
    );
  });

  it('forwards userId + secret and maps a successful response', async () => {
    const fetchMock = jest.fn().mockResolvedValue({
      ok: true,
      json: async () => ({
        answer: 'Tienes que llamar a Marcos [1].',
        sources: [
          { capture_id: 'c1', snippet: 'Llamar a Marcos' },
          { bad: 'ignored' },
        ],
      }),
    });
    global.fetch = fetchMock as unknown as typeof fetch;

    const service = new QueryService(
      configWith({
        AI_SERVICE_URL: 'http://ai',
        QUERY_INTERNAL_SECRET: 's3cret',
      }),
    );

    const result = await service.ask(USER_ID, '¿Qué tengo con Marcos?');

    expect(result.answer).toBe('Tienes que llamar a Marcos [1].');
    // Malformed source entries are dropped defensively.
    expect(result.sources).toEqual([
      { capture_id: 'c1', snippet: 'Llamar a Marcos' },
    ]);

    const [url, init] = fetchMock.mock.calls[0];
    expect(url).toBe('http://ai/internal/query');
    expect((init.headers as Record<string, string>)['x-internal-token']).toBe(
      's3cret',
    );
    expect(JSON.parse(init.body as string)).toEqual({
      user_id: USER_ID,
      question: '¿Qué tengo con Marcos?',
    });
  });

  it('surfaces an unreachable AI service as ServiceUnavailable', async () => {
    global.fetch = jest
      .fn()
      .mockRejectedValue(new Error('ECONNREFUSED')) as unknown as typeof fetch;
    const service = new QueryService(
      configWith({ AI_SERVICE_URL: 'http://ai', QUERY_INTERNAL_SECRET: 's' }),
    );
    await expect(service.ask(USER_ID, 'hola')).rejects.toBeInstanceOf(
      ServiceUnavailableException,
    );
  });

  it('surfaces an upstream error status as ServiceUnavailable', async () => {
    global.fetch = jest
      .fn()
      .mockResolvedValue({ ok: false, status: 502 }) as unknown as typeof fetch;
    const service = new QueryService(
      configWith({ AI_SERVICE_URL: 'http://ai', QUERY_INTERNAL_SECRET: 's' }),
    );
    await expect(service.ask(USER_ID, 'hola')).rejects.toBeInstanceOf(
      ServiceUnavailableException,
    );
  });
});
