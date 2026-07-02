import { ConflictException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import * as fc from 'fast-check';
import { randomUUID } from 'node:crypto';
import { PrismaRlsService } from '../prisma/prisma-rls.service';
import { CreateCaptureDto, CaptureType } from './dto/create-capture.dto';
import { IdempotencyService } from './idempotency.service';

/**
 * Property-based tests for IdempotencyService (task 5.2).
 * Feature: capture-engine, Property 3 (idempotency of creation) and
 * Property 4 (inconsistent key reuse). Persistence is an in-memory double —
 * no database required.
 */

interface IdemRow {
  userId: string;
  key: string;
  captureId: string;
  requestHash: string;
}

interface NodeRow {
  id: string;
  status: 'raw';
  createdAt: Date;
  occurredAt: Date | null;
}

/**
 * In-memory harness emulating the `(user_id, key)` uniqueness and the node/
 * idempotency tables, with a PrismaRlsService double that just runs `work`.
 */
function buildHarness(): {
  service: IdempotencyService;
  tx: Prisma.TransactionClient;
  idemRows: Map<string, IdemRow>;
  nodes: Map<string, NodeRow>;
} {
  const idemRows = new Map<string, IdemRow>();
  const nodes = new Map<string, NodeRow>();
  const compositeKey = (userId: string, key: string): string =>
    `${userId}\u0000${key}`;

  const fakeTx = {
    idempotencyKey: {
      findUnique: (args: {
        where: { uq_idempotency_user_key: { userId: string; key: string } };
      }): Promise<IdemRow | null> => {
        const { userId, key } = args.where.uq_idempotency_user_key;
        return Promise.resolve(idemRows.get(compositeKey(userId, key)) ?? null);
      },
      create: (args: { data: IdemRow }): Promise<IdemRow> => {
        const ck = compositeKey(args.data.userId, args.data.key);
        if (idemRows.has(ck)) {
          // Emulate the Postgres unique-violation the DB would raise.
          return Promise.reject(new Error('unique constraint violation'));
        }
        idemRows.set(ck, args.data);
        return Promise.resolve(args.data);
      },
    },
    node: {
      findUnique: (args: { where: { id: string } }): Promise<NodeRow | null> =>
        Promise.resolve(nodes.get(args.where.id) ?? null),
    },
  };

  const tx = fakeTx as unknown as Prisma.TransactionClient;
  const rls = {
    withUser: <T>(
      _userId: string,
      work: (t: Prisma.TransactionClient) => Promise<T>,
    ): Promise<T> => work(tx),
  } as unknown as PrismaRlsService;

  return { service: new IdempotencyService(rls), tx, idemRows, nodes };
}

/** Arbitrary for a text/voice capture payload. */
const dtoArb: fc.Arbitrary<CreateCaptureDto> = fc.record({
  type: fc.constantFrom(CaptureType.text, CaptureType.voice),
  content: fc.string({ minLength: 1, maxLength: 200 }),
});

/** Persist a fake capture node and return its id. */
function seedCapture(nodes: Map<string, NodeRow>): string {
  const id = randomUUID();
  nodes.set(id, { id, status: 'raw', createdAt: new Date(), occurredAt: null });
  return id;
}

describe('IdempotencyService (PBT)', () => {
  // Feature: capture-engine, Property 3
  // Validates: Requirements 3.1, 3.4
  it('Property 3: same key + same payload yields the same capture_id and a single row', async () => {
    await fc.assert(
      fc.asyncProperty(
        fc.uuid(),
        fc.string({ minLength: 1, maxLength: 40 }),
        dtoArb,
        async (userId, key, dto) => {
          const { service, tx, idemRows, nodes } = buildHarness();

          // New key -> null (caller proceeds to create).
          expect(await service.lookup(userId, key, dto)).toBeNull();

          // Simulate the capture + idempotency store (one transaction).
          const captureId = seedCapture(nodes);
          await service.store(tx, { userId, key, captureId, dto });

          // Replays return the same capture_id...
          const first = await service.lookup(userId, key, dto);
          const second = await service.lookup(userId, key, dto);
          expect(first?.capture_id).toBe(captureId);
          expect(second?.capture_id).toBe(captureId);

          // ...and exactly one idempotency row exists for (userId, key).
          const rows = [...idemRows.values()].filter(
            (r) => r.userId === userId && r.key === key,
          );
          expect(rows).toHaveLength(1);
        },
      ),
      { numRuns: 100 },
    );
  });

  // Feature: capture-engine, Property 4
  // Validates: Requirements 3.2, 3.4
  it('Property 4: same key + different payload throws 409 and leaves the original intact', async () => {
    await fc.assert(
      fc.asyncProperty(
        fc.uuid(),
        fc.string({ minLength: 1, maxLength: 40 }),
        dtoArb,
        fc.string({ minLength: 1, maxLength: 200 }),
        async (userId, key, dtoA, extra) => {
          const { service, tx, nodes } = buildHarness();
          // Guarantee a different payload (and therefore a different hash).
          const dtoB: CreateCaptureDto = {
            ...dtoA,
            content: `${dtoA.content ?? ''}${extra}#`,
          };
          fc.pre(service.hashPayload(dtoA) !== service.hashPayload(dtoB));

          const captureId = seedCapture(nodes);
          await service.store(tx, { userId, key, captureId, dto: dtoA });

          // Reusing the key with a different payload conflicts...
          await expect(
            service.lookup(userId, key, dtoB),
          ).rejects.toBeInstanceOf(ConflictException);
          // ...and the original capture is unchanged / still resolvable.
          const original = await service.lookup(userId, key, dtoA);
          expect(original?.capture_id).toBe(captureId);
        },
      ),
      { numRuns: 100 },
    );
  });
});
