import { BadRequestException, NotFoundException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { randomUUID } from 'node:crypto';
import { PrismaRlsService } from '../prisma/prisma-rls.service';
import { BlobStorageService } from './blob-storage.service';
import { CaptureService } from './capture.service';
import { CaptureType, CreateCaptureDto } from './dto/create-capture.dto';
import { IdempotencyService } from './idempotency.service';
import { CaptureResponse } from './capture.mapper';
import { UnderstandingQueuePort } from './understanding.queue.port';

/**
 * Unit tests for CaptureService (task 6.5): persist-before-enqueue ordering,
 * idempotent replay, voice blob validation ordering, temporal coherence and the
 * 202 response shape. Dependencies are lightweight doubles (no DB / S3 / Redis).
 */
const USER_ID = '11111111-1111-1111-1111-111111111111';
const KEY = 'idem-key-1';

interface Harness {
  service: CaptureService;
  order: string[];
  idempotency: { lookup: jest.Mock; store: jest.Mock; hashPayload: jest.Mock };
  blobs: { assertOwnedAndExists: jest.Mock; presignUpload: jest.Mock };
  queue: { enqueueUnderstanding: jest.Mock };
}

function buildHarness(): Harness {
  const order: string[] = [];

  const rls = {
    withUser: async <T>(
      _userId: string,
      work: (tx: Prisma.TransactionClient) => Promise<T>,
    ): Promise<T> => {
      order.push('persist');
      const tx = {
        node: {
          create: (args: { data: { occurredAt: Date | null } }) =>
            Promise.resolve({
              id: randomUUID(),
              status: 'raw',
              createdAt: new Date(),
              occurredAt: args.data.occurredAt ?? null,
            }),
        },
      } as unknown as Prisma.TransactionClient;
      return work(tx);
    },
  } as unknown as PrismaRlsService;

  const idempotency = {
    lookup: jest.fn().mockResolvedValue(null),
    store: jest.fn().mockResolvedValue(undefined),
    hashPayload: jest.fn().mockReturnValue('hash'),
  };
  const blobs = {
    assertOwnedAndExists: jest.fn().mockImplementation(() => {
      order.push('blob-check');
      return Promise.resolve();
    }),
    presignUpload: jest.fn(),
  };
  const queue = {
    enqueueUnderstanding: jest.fn().mockImplementation(() => {
      order.push('enqueue');
      return Promise.resolve();
    }),
  };

  const service = new CaptureService(
    rls,
    idempotency as unknown as IdempotencyService,
    blobs as unknown as BlobStorageService,
    queue as unknown as UnderstandingQueuePort,
  );

  return { service, order, idempotency, blobs, queue };
}

function textDto(content = 'a thought'): CreateCaptureDto {
  return { type: CaptureType.text, content };
}

describe('CaptureService', () => {
  it('persists the capture before enqueuing the understanding job', async () => {
    const h = buildHarness();
    await h.service.create(USER_ID, KEY, textDto());
    expect(h.order).toEqual(['persist', 'enqueue']);
  });

  it('returns a 202-shaped response for a new text capture', async () => {
    const h = buildHarness();
    const res = await h.service.create(USER_ID, KEY, textDto());
    expect(res).toEqual<CaptureResponse>({
      capture_id: expect.any(String),
      status: 'raw',
      created_at: expect.any(String),
      occurred_at: null,
    });
    expect(() => new Date(res.created_at).toISOString()).not.toThrow();
  });

  it('returns the prior response on an idempotent replay without persisting', async () => {
    const h = buildHarness();
    const prior: CaptureResponse = {
      capture_id: 'prior-id',
      status: 'raw',
      created_at: new Date().toISOString(),
      occurred_at: null,
    };
    h.idempotency.lookup.mockResolvedValueOnce(prior);

    const res = await h.service.create(USER_ID, KEY, textDto());
    expect(res).toBe(prior);
    expect(h.order).toEqual([]);
    expect(h.queue.enqueueUnderstanding).not.toHaveBeenCalled();
  });

  it('validates the voice blob before persisting', async () => {
    const h = buildHarness();
    const dto: CreateCaptureDto = {
      type: CaptureType.voice,
      audio_ref: `audio/${USER_ID}/x.m4a`,
    };
    await h.service.create(USER_ID, KEY, dto);
    expect(h.blobs.assertOwnedAndExists).toHaveBeenCalledWith(
      USER_ID,
      dto.audio_ref,
    );
    expect(h.order).toEqual(['blob-check', 'persist', 'enqueue']);
  });

  it('rejects a text capture with empty content (400)', async () => {
    const h = buildHarness();
    await expect(
      h.service.create(USER_ID, KEY, {
        type: CaptureType.text,
        content: '   ',
      }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('rejects an occurred_at in the future (400)', async () => {
    const h = buildHarness();
    const future = new Date(Date.now() + 3_600_000).toISOString();
    await expect(
      h.service.create(USER_ID, KEY, {
        type: CaptureType.text,
        content: 'x',
        occurred_at: future,
      }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('still returns 202 when the enqueue fails (capture already safe)', async () => {
    const h = buildHarness();
    h.queue.enqueueUnderstanding.mockRejectedValueOnce(new Error('redis down'));
    const res = await h.service.create(USER_ID, KEY, textDto());
    expect(res.status).toBe('raw');
    expect(h.order).toEqual(['persist']);
  });

  it('maps a missing capture to 404 on findOne', async () => {
    const rls = {
      withUser: async <T>(
        _userId: string,
        work: (tx: Prisma.TransactionClient) => Promise<T>,
      ): Promise<T> =>
        work({
          node: { findFirst: () => Promise.resolve(null) },
        } as unknown as Prisma.TransactionClient),
    } as unknown as PrismaRlsService;
    const service = new CaptureService(
      rls,
      { lookup: jest.fn() } as unknown as IdempotencyService,
      {} as unknown as BlobStorageService,
      { enqueueUnderstanding: jest.fn() } as unknown as UnderstandingQueuePort,
    );
    await expect(service.findOne(USER_ID, randomUUID())).rejects.toBeInstanceOf(
      NotFoundException,
    );
  });
});
