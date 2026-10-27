import {
  INestApplication,
  ServiceUnavailableException,
  UnprocessableEntityException,
} from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { Prisma } from '@prisma/client';
import { randomUUID } from 'node:crypto';
import request from 'supertest';
import { PrismaRlsService } from '../prisma/prisma-rls.service';
import { createHttpHarness, TEST_USER_ID } from '../test/http-harness';
import { BlobStorageService } from './blob-storage.service';
import { CaptureController } from './capture.controller';
import { CaptureService } from './capture.service';
import { IdempotencyService } from './idempotency.service';
import { UnderstandingQueuePort } from './understanding.queue.port';
import { Transcript, VoiceTranscriber } from './voice-transcriber';

/**
 * Voice notes (ADR-021): the audio is transcribed and discarded, the transcript
 * becomes the capture body (origin `voice`) with its transcription cost, and
 * understanding is enqueued like for text. Idempotency covers the audio bytes,
 * so a replay never re-transcribes. Doubles only — no DB, no AI service.
 */
const USER_ID = '11111111-1111-1111-1111-111111111111';
const KEY = 'voice-key-1';
const AUDIO = Buffer.from('fake-webm-bytes');

function transcript(text: string): Transcript {
  return {
    text,
    provider: 'openai',
    model: 'gpt-transcribe',
    duration_s: 4.2,
    cost_usd: 0.000315,
  };
}

function harness(transcribe: jest.Mock) {
  const created: Record<string, unknown>[] = [];
  const usage: Record<string, unknown>[] = [];
  const rls = {
    withUser: async <T>(
      _u: string,
      work: (tx: Prisma.TransactionClient) => Promise<T>,
    ): Promise<T> =>
      work({
        node: {
          create: (args: { data: Record<string, unknown> }) => {
            created.push(args.data);
            return Promise.resolve({
              id: randomUUID(),
              status: 'raw',
              createdAt: new Date(),
              occurredAt: null,
              body: args.data.body,
              origin: args.data.origin,
            });
          },
        },
        llmUsage: {
          create: (args: { data: Record<string, unknown> }) => {
            usage.push(args.data);
            return Promise.resolve({});
          },
        },
      } as unknown as Prisma.TransactionClient),
  } as unknown as PrismaRlsService;
  const idempotency = {
    lookup: jest.fn().mockResolvedValue(null),
    store: jest.fn().mockResolvedValue(undefined),
  };
  const queue = {
    enqueueUnderstanding: jest.fn().mockResolvedValue(undefined),
  };
  const service = new CaptureService(
    rls,
    idempotency as unknown as IdempotencyService,
    {} as BlobStorageService,
    queue as unknown as UnderstandingQueuePort,
    { transcribe } as unknown as VoiceTranscriber,
  );
  return { service, created, usage, idempotency, queue };
}

describe('CaptureService.createVoice', () => {
  it('stores the transcript (never the audio), its cost, and enqueues', async () => {
    const transcribe = jest
      .fn()
      .mockResolvedValue(transcript(' Llamar a Marcos '));
    const h = harness(transcribe);

    const res = await h.service.createVoice(USER_ID, KEY, {
      audio: AUDIO,
      contentType: 'audio/webm;codecs=opus',
      durationMs: 4200,
    });

    expect(transcribe).toHaveBeenCalledWith(AUDIO, 'audio/webm', 4200);
    expect(res).toMatchObject({
      content: 'Llamar a Marcos',
      modality: 'voice',
      status: 'raw',
    });
    expect(h.created[0]).toMatchObject({
      origin: 'voice',
      body: 'Llamar a Marcos',
    });
    expect(JSON.stringify(h.created[0])).not.toContain('fake-webm-bytes');
    expect(h.usage[0]).toMatchObject({
      operation: 'transcribe',
      model: 'gpt-transcribe',
    });
    expect(h.queue.enqueueUnderstanding).toHaveBeenCalledTimes(1);
  });

  it('hashes the audio into the idempotency payload', async () => {
    const h = harness(jest.fn().mockResolvedValue(transcript('hola')));
    await h.service.createVoice(USER_ID, KEY, {
      audio: AUDIO,
      contentType: 'audio/webm',
    });
    const pseudo = h.idempotency.lookup.mock.calls[0][2];
    expect(pseudo.type).toBe('voice');
    expect(pseudo.content).toMatch(/^sha256:[0-9a-f]{64}$/);
  });

  it('returns the prior capture on a replay without re-transcribing', async () => {
    const transcribe = jest.fn();
    const h = harness(transcribe);
    const prior = {
      capture_id: 'c1',
      status: 'processed' as const,
      created_at: new Date().toISOString(),
      occurred_at: null,
      content: 'hola',
      modality: 'voice' as const,
    };
    h.idempotency.lookup.mockResolvedValueOnce(prior);

    const res = await h.service.createVoice(USER_ID, KEY, {
      audio: AUDIO,
      contentType: 'audio/webm',
    });

    expect(res).toBe(prior);
    expect(transcribe).not.toHaveBeenCalled();
  });

  it('rejects an empty transcript with 422 empty_transcript', async () => {
    const h = harness(jest.fn().mockResolvedValue(transcript('   ')));
    await expect(
      h.service.createVoice(USER_ID, KEY, {
        audio: AUDIO,
        contentType: 'audio/webm',
      }),
    ).rejects.toBeInstanceOf(UnprocessableEntityException);
    expect(h.created).toHaveLength(0);
  });

  it('propagates "transcription unavailable" so the client retries later', async () => {
    const h = harness(
      jest.fn().mockRejectedValue(new ServiceUnavailableException()),
    );
    await expect(
      h.service.createVoice(USER_ID, KEY, {
        audio: AUDIO,
        contentType: 'audio/mp4',
      }),
    ).rejects.toBeInstanceOf(ServiceUnavailableException);
    expect(h.created).toHaveLength(0);
  });
});

describe('POST /v1/captures/voice (HTTP)', () => {
  let app: INestApplication;
  const service = {
    createVoice: jest.fn().mockResolvedValue({
      capture_id: 'c1',
      status: 'raw',
      created_at: '2026-07-10T00:00:00.000Z',
      occurred_at: null,
      content: 'Llamar a Marcos',
      modality: 'voice',
    }),
  };

  beforeAll(async () => {
    app = await createHttpHarness(
      [CaptureController],
      [
        { provide: CaptureService, useValue: service },
        { provide: JwtService, useValue: {} },
      ],
    );
  });

  afterAll(async () => {
    await app.close();
  });

  beforeEach(() => service.createVoice.mockClear());

  it('accepts raw audio and passes metadata through', async () => {
    const clientId = randomUUID();
    const res = await request(app.getHttpServer())
      .post(`/v1/captures/voice?client_id=${clientId}&duration_ms=4200`)
      .set('Idempotency-Key', clientId)
      .set('Content-Type', 'audio/webm')
      .send(AUDIO);

    expect(res.status).toBe(202);
    expect(res.body.content).toBe('Llamar a Marcos');
    const [userId, key, upload] = service.createVoice.mock.calls[0];
    expect(userId).toBe(TEST_USER_ID);
    expect(key).toBe(clientId);
    expect(Buffer.compare(upload.audio, AUDIO)).toBe(0);
    expect(upload).toMatchObject({
      contentType: 'audio/webm',
      clientId,
      durationMs: 4200,
    });
  });

  it('requires an Idempotency-Key', async () => {
    const res = await request(app.getHttpServer())
      .post('/v1/captures/voice')
      .set('Content-Type', 'audio/webm')
      .send(AUDIO);
    expect(res.status).toBe(400);
    expect(service.createVoice).not.toHaveBeenCalled();
  });

  it('validates client_id and occurred_at', async () => {
    const bad = await request(app.getHttpServer())
      .post('/v1/captures/voice?client_id=nope')
      .set('Idempotency-Key', 'k')
      .set('Content-Type', 'audio/webm')
      .send(AUDIO);
    expect(bad.status).toBe(400);
    const badDate = await request(app.getHttpServer())
      .post('/v1/captures/voice?occurred_at=yesterday')
      .set('Idempotency-Key', 'k')
      .set('Content-Type', 'audio/webm')
      .send(AUDIO);
    expect(badDate.status).toBe(400);
  });

  it('rejects a voice note over 10 MB with 413', async () => {
    const res = await request(app.getHttpServer())
      .post('/v1/captures/voice')
      .set('Idempotency-Key', 'k')
      .set('Content-Type', 'audio/webm')
      .send(Buffer.alloc(10 * 1024 * 1024 + 1));
    expect(res.status).toBe(413);
    expect(service.createVoice).not.toHaveBeenCalled();
  });
});
