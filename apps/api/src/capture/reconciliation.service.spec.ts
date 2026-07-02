import { ConfigService } from '@nestjs/config';
import { Prisma } from '@prisma/client';
import { randomUUID } from 'node:crypto';
import { PrismaService } from '../prisma/prisma.service';
import { PrismaRlsService } from '../prisma/prisma-rls.service';
import { ReconciliationService } from './reconciliation.service';
import {
  UnderstandingJobData,
  UnderstandingQueuePort,
} from './understanding.queue.port';

/**
 * Unit tests for the reconciliation sweep (task 9.1) over in-memory doubles.
 * `rls.withUser(uid, ...)` scopes reads to `uid`, mirroring RLS, so the sweep's
 * per-user isolation is exercised without a database. Verifies: only stale raw
 * captures are re-enqueued, fresh ones are skipped, and the batch budget caps a
 * run.
 */
interface FakeNode {
  id: string;
  userId: string;
  type: string;
  status: string;
  createdAt: Date;
}

const minutesAgo = (m: number): Date => new Date(Date.now() - m * 60_000);

function buildHarness(nodes: FakeNode[], batchLimit?: string) {
  const users = [...new Set(nodes.map((n) => n.userId))].map((id) => ({ id }));

  const prisma = {
    user: { findMany: () => Promise.resolve(users) },
  } as unknown as PrismaService;

  const rls = {
    withUser: <T>(
      userId: string,
      work: (tx: Prisma.TransactionClient) => Promise<T>,
    ): Promise<T> => {
      const tx = {
        node: {
          findMany: (args: {
            where: {
              userId: string;
              status?: string;
              type?: string;
              createdAt?: { lt: Date };
            };
            take: number;
          }): Promise<FakeNode[]> => {
            let rows = nodes.filter((n) => n.userId === userId);
            if (args.where.type) {
              rows = rows.filter((n) => n.type === args.where.type);
            }
            if (args.where.status) {
              rows = rows.filter((n) => n.status === args.where.status);
            }
            if (args.where.createdAt?.lt) {
              const lt = args.where.createdAt.lt.getTime();
              rows = rows.filter((n) => n.createdAt.getTime() < lt);
            }
            rows = rows.sort(
              (a, b) => a.createdAt.getTime() - b.createdAt.getTime(),
            );
            return Promise.resolve(rows.slice(0, args.take));
          },
        },
      } as unknown as Prisma.TransactionClient;
      return work(tx);
    },
  } as unknown as PrismaRlsService;

  const enqueued: UnderstandingJobData[] = [];
  const queue: UnderstandingQueuePort = {
    enqueueUnderstanding: (data) => {
      enqueued.push(data);
      return Promise.resolve();
    },
  };

  const config = {
    get: (key: string): string | undefined =>
      key === 'RECONCILIATION_BATCH_LIMIT' ? batchLimit : undefined,
  } as unknown as ConfigService;

  const service = new ReconciliationService(prisma, rls, queue, config);
  return { service, enqueued };
}

describe('ReconciliationService', () => {
  it('re-enqueues stale raw captures and skips fresh ones', async () => {
    const userId = randomUUID();
    const staleId = randomUUID();
    const nodes: FakeNode[] = [
      {
        id: staleId,
        userId,
        type: 'capture',
        status: 'raw',
        createdAt: minutesAgo(10),
      },
      {
        id: randomUUID(),
        userId,
        type: 'capture',
        status: 'raw',
        createdAt: minutesAgo(1),
      },
    ];
    const { service, enqueued } = buildHarness(nodes);

    const count = await service.reconcile();

    expect(count).toBe(1);
    expect(enqueued).toHaveLength(1);
    expect(enqueued[0]).toMatchObject({
      schema_version: 1,
      capture_id: staleId,
      user_id: userId,
    });
  });

  it('does not re-enqueue non-raw or non-capture nodes', async () => {
    const userId = randomUUID();
    const nodes: FakeNode[] = [
      {
        id: randomUUID(),
        userId,
        type: 'capture',
        status: 'processed',
        createdAt: minutesAgo(20),
      },
      {
        id: randomUUID(),
        userId,
        type: 'note',
        status: 'raw',
        createdAt: minutesAgo(20),
      },
    ];
    const { service, enqueued } = buildHarness(nodes);

    expect(await service.reconcile()).toBe(0);
    expect(enqueued).toHaveLength(0);
  });

  it('honours the batch limit across users', async () => {
    const nodes: FakeNode[] = [
      {
        id: randomUUID(),
        userId: randomUUID(),
        type: 'capture',
        status: 'raw',
        createdAt: minutesAgo(30),
      },
      {
        id: randomUUID(),
        userId: randomUUID(),
        type: 'capture',
        status: 'raw',
        createdAt: minutesAgo(30),
      },
      {
        id: randomUUID(),
        userId: randomUUID(),
        type: 'capture',
        status: 'raw',
        createdAt: minutesAgo(30),
      },
    ];
    const { service, enqueued } = buildHarness(nodes, '2');

    expect(await service.reconcile()).toBe(2);
    expect(enqueued).toHaveLength(2);
  });
});
