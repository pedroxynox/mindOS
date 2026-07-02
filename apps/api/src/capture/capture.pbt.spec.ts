import { BadRequestException, NotFoundException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import * as fc from 'fast-check';
import { randomUUID } from 'node:crypto';
import { PrismaRlsService } from '../prisma/prisma-rls.service';
import { BlobStorageService } from './blob-storage.service';
import { CaptureService } from './capture.service';
import { CaptureType, CreateCaptureDto } from './dto/create-capture.dto';
import { IdempotencyService } from './idempotency.service';
import { UnderstandingQueuePort } from './understanding.queue.port';

/**
 * Property-based tests for CaptureService (task 6.6).
 * Feature: capture-engine, Property 5 (temporal coherence) and
 * Property 1 (owner-only read). Persistence is an in-memory double whose
 * per-user scoping emulates RLS — no database required.
 */

interface StoredNode {
  id: string;
  userId: string;
  type: string;
  status: 'raw';
  createdAt: Date;
  occurredAt: Date | null;
}

/**
 * Build a CaptureService over an in-memory store. `rls.withUser(uid, ...)`
 * hands the work a tx whose reads are scoped to `uid`, mirroring how RLS makes
 * only the context user's rows visible.
 */
function buildHarness(): CaptureService {
  const store: StoredNode[] = [];

  const makeTx = (contextUserId: string): Prisma.TransactionClient => {
    const visible = (): StoredNode[] =>
      store.filter((n) => n.userId === contextUserId);
    const fakeTx = {
      node: {
        create: (args: {
          data: { userId: string; occurredAt: Date | null };
        }): Promise<StoredNode> => {
          const node: StoredNode = {
            id: randomUUID(),
            userId: args.data.userId,
            type: 'capture',
            status: 'raw',
            createdAt: new Date(),
            occurredAt: args.data.occurredAt ?? null,
          };
          store.push(node);
          return Promise.resolve(node);
        },
        findFirst: (args: {
          where: { id: string; type: string };
        }): Promise<StoredNode | null> =>
          Promise.resolve(
            visible().find(
              (n) => n.id === args.where.id && n.type === args.where.type,
            ) ?? null,
          ),
        findMany: (args: {
          where: { status?: string };
          take: number;
          cursor?: { id: string };
          skip?: number;
        }): Promise<StoredNode[]> => {
          let rows = visible().filter((n) => n.type === 'capture');
          if (args.where.status) {
            rows = rows.filter((n) => n.status === args.where.status);
          }
          rows = rows.sort((a, b) => {
            const t = b.createdAt.getTime() - a.createdAt.getTime();
            return t !== 0 ? t : a.id < b.id ? 1 : -1;
          });
          if (args.cursor) {
            const idx = rows.findIndex((n) => n.id === args.cursor?.id);
            if (idx >= 0) {
              rows = rows.slice(idx + (args.skip ?? 0));
            }
          }
          return Promise.resolve(rows.slice(0, args.take));
        },
      },
    };
    return fakeTx as unknown as Prisma.TransactionClient;
  };

  const rls = {
    withUser: <T>(
      userId: string,
      work: (tx: Prisma.TransactionClient) => Promise<T>,
    ): Promise<T> => work(makeTx(userId)),
  } as unknown as PrismaRlsService;

  const idempotency = {
    lookup: () => Promise.resolve(null),
    store: () => Promise.resolve(),
    hashPayload: () => 'hash',
  } as unknown as IdempotencyService;
  const blobs = {
    assertOwnedAndExists: () => Promise.resolve(),
  } as unknown as BlobStorageService;
  const queue = {
    enqueueUnderstanding: () => Promise.resolve(),
  } as unknown as UnderstandingQueuePort;

  return new CaptureService(rls, idempotency, blobs, queue);
}

describe('CaptureService (PBT)', () => {
  // Feature: capture-engine, Property 5
  // Validates: Requirements 8.1, 8.2
  it('Property 5: occurred_at (when present) is never after created_at; future values are rejected', async () => {
    await fc.assert(
      fc.asyncProperty(
        fc.boolean(),
        fc.integer({ min: 10, max: 10_000_000 }),
        async (future, secs) => {
          const service = buildHarness();
          const occurred = future
            ? new Date(Date.now() + secs * 1000)
            : new Date(Date.now() - secs * 1000);
          const dto: CreateCaptureDto = {
            type: CaptureType.text,
            content: 'temporal check',
            occurred_at: occurred.toISOString(),
          };

          if (future) {
            await expect(
              service.create(randomUUID(), randomUUID(), dto),
            ).rejects.toBeInstanceOf(BadRequestException);
          } else {
            const res = await service.create(randomUUID(), randomUUID(), dto);
            expect(res.occurred_at).not.toBeNull();
            expect(
              new Date(res.occurred_at as string).getTime(),
            ).toBeLessThanOrEqual(new Date(res.created_at).getTime());
          }
        },
      ),
      { numRuns: 100 },
    );
  });

  // Feature: capture-engine, Property 1
  // Validates: Requirements 4.1, 4.2, 4.3, 7.1, 7.2
  it('Property 1: a capture is readable/listable by its owner and invisible (404) to others', async () => {
    // Text captures require non-empty content: the service rejects
    // whitespace-only payloads (design §7/§13). Property 1 is about owner-only
    // *visibility*, so the generator must stay inside the valid input space and
    // yield content with at least one non-whitespace character — otherwise the
    // capture is never created. Surrounding whitespace is still allowed (only
    // fully-blank content is invalid), so we keep broad coverage.
    const nonBlankContent = fc
      .string({ minLength: 1, maxLength: 100 })
      .filter((s) => s.trim().length > 0);

    await fc.assert(
      fc.asyncProperty(nonBlankContent, async (content) => {
        const service = buildHarness();
        const owner = randomUUID();
        const other = randomUUID();

        const created = await service.create(owner, randomUUID(), {
          type: CaptureType.text,
          content,
        });

        // Owner can read it.
        const read = await service.findOne(owner, created.capture_id);
        expect(read.capture_id).toBe(created.capture_id);

        // A non-owner gets 404 (no content, no existence leak).
        await expect(
          service.findOne(other, created.capture_id),
        ).rejects.toBeInstanceOf(NotFoundException);

        // Listing is owner-scoped.
        const ownerList = await service.list(owner, { limit: 100 });
        expect(
          ownerList.data.some((c) => c.capture_id === created.capture_id),
        ).toBe(true);

        const otherList = await service.list(other, { limit: 100 });
        expect(
          otherList.data.some((c) => c.capture_id === created.capture_id),
        ).toBe(false);
      }),
      {
        numRuns: 100,
        // Regression: content that is non-blank but padded with whitespace must
        // still be accepted (the CI counterexample was fully-blank " ", which
        // is now correctly outside the generated input space).
        examples: [['x'], [' x '], ['a\nb']],
      },
    );
  });
});
