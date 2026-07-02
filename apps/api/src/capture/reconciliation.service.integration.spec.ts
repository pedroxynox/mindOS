import { ConfigService } from '@nestjs/config';
import { PrismaClient } from '@prisma/client';
import { Queue } from 'bullmq';
import { PrismaService } from '../prisma/prisma.service';
import { PrismaRlsService } from '../prisma/prisma-rls.service';
import { ReconciliationService } from './reconciliation.service';
import {
  BullUnderstandingQueue,
  UNDERSTANDING_QUEUE,
} from './understanding.queue';

/**
 * Integration test for the reconciliation sweep against REAL Postgres + Redis
 * (task 9.2).
 *
 * SKIPPED IN THIS ENVIRONMENT: it requires a live PostgreSQL with the F1
 * migrations (RLS + non-owner app role) AND a running Redis broker. Unskip and
 * run once both are available:
 *
 *   docker compose up -d postgres redis
 *   npm test -- reconciliation.service.integration
 *
 * Feature: capture-engine, Property 2: La captura nunca se pierde — a `raw`
 * capture with no job, older than the threshold, is re-enqueued exactly once by
 * the sweep; a capture accepted despite an enqueue failure is recoverable. The
 * batch limit and the 5-minute staleness threshold are respected.
 *
 * Validates: Requirements R5.2, R5.3, R5.4 · Property P2.
 */
const connection = {
  host: process.env.REDIS_HOST ?? 'localhost',
  port: Number(process.env.REDIS_PORT ?? 6379),
};

describe.skip('ReconciliationService (integration, Postgres + Redis)', () => {
  let prisma: PrismaService;
  let rls: PrismaRlsService;
  let queue: Queue;
  let service: ReconciliationService;
  let userId: string;

  beforeAll(async () => {
    prisma = new PrismaService();
    await (prisma as unknown as PrismaClient).$connect();
    rls = new PrismaRlsService(prisma);
    queue = new Queue(UNDERSTANDING_QUEUE, { connection });
    await queue.obliterate({ force: true });

    const config = {
      get: (key: string): string | undefined =>
        ({
          RECONCILIATION_STALE_MINUTES: '5',
          RECONCILIATION_BATCH_LIMIT: '100',
        })[key],
    } as unknown as ConfigService;
    service = new ReconciliationService(
      prisma,
      rls,
      new BullUnderstandingQueue(queue),
      config,
    );

    const user = await prisma.user.create({
      data: { email: `recon-${Date.now()}@example.com`, passwordHash: 'x' },
    });
    userId = user.id;
  });

  afterAll(async () => {
    await queue.obliterate({ force: true });
    await queue.close();
    await (prisma as unknown as PrismaClient).$disconnect();
  });

  it('P2: re-enqueues a stale raw capture exactly once and skips fresh ones', async () => {
    // A stale raw capture (created_at older than the threshold).
    const stale = await rls.withUser(userId, (tx) =>
      tx.node.create({
        data: {
          userId,
          type: 'capture',
          origin: 'manual_text',
          status: 'raw',
          body: 'stale',
          createdAt: new Date(Date.now() - 10 * 60_000),
        },
      }),
    );
    // A fresh raw capture that must NOT be re-enqueued yet.
    await rls.withUser(userId, (tx) =>
      tx.node.create({
        data: { userId, type: 'capture', origin: 'manual_text', body: 'fresh' },
      }),
    );

    const reEnqueued = await service.reconcile();
    expect(reEnqueued).toBe(1);

    const job = await queue.getJob(stale.id);
    expect(job?.data.capture_id).toBe(stale.id);

    // Idempotent: a second sweep does not create a duplicate job.
    await service.reconcile();
    const counts = await queue.getJobCounts('waiting', 'delayed', 'active');
    expect(counts.waiting + counts.delayed + counts.active).toBe(1);
  });
});
