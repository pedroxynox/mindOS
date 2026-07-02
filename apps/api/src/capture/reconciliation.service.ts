import { Inject, Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Cron, CronExpression } from '@nestjs/schedule';
import { PrismaService } from '../prisma/prisma.service';
import { PrismaRlsService } from '../prisma/prisma-rls.service';
import {
  UNDERSTANDING_QUEUE_PORT,
  UnderstandingQueuePort,
} from './understanding.queue.port';

/** Default age (minutes) after which a still-`raw` capture is reconciled. */
const DEFAULT_STALE_MINUTES = 5;

/** Default cap on captures re-enqueued per sweep run, to bound load. */
const DEFAULT_BATCH_LIMIT = 100;

/**
 * Reconciliation sweep — the "a capture is never lost" safety net
 * (design.md §10.2, R5.3/R5.4, Property P2).
 *
 * A capture is persisted BEFORE it is enqueued (CaptureService, §8). If the
 * process dies — or Redis is down — right after the commit, the capture stays
 * in PostgreSQL with `status = raw` and no job. This cron closes that gap: it
 * periodically re-enqueues stale `raw` captures. Because the queue dedups by
 * `jobId = capture_id`, re-enqueuing a capture that already has a live job is a
 * no-op, so the sweep is safe to run repeatedly.
 *
 * ─── RLS decision (important) ───────────────────────────────────────────────
 * The sweep is inherently cross-user, but it MUST NOT punch a hole in the
 * per-user isolation guaranteed by RLS. Two options were considered:
 *
 *   (A) Read orphans with an elevated/owner role that bypasses FORCE RLS, then
 *       fan out per user. Rejected: it introduces a privileged, RLS-bypassing
 *       read path into the running app — exactly the isolation hole we protect
 *       against, and easy to misuse later.
 *
 *   (B) Enumerate users (the `users` table is not RLS-protected — auth already
 *       reads it as the app role) and, for EACH user, run the orphan query
 *       INSIDE that user's normal `PrismaRlsService.withUser` context. Chosen.
 *
 * Option (B) keeps every `nodes` read under the exact same fail-closed RLS
 * context used by the request path: we never bypass RLS, never widen the app
 * role's privileges, and each row we read is provably the context user's own.
 * The enqueued message therefore always carries the correct `user_id`. The
 * only cost is iterating users; a global batch budget bounds the work per run,
 * and at scale this can be narrowed to "users with recent activity" without
 * changing the isolation model.
 */
@Injectable()
export class ReconciliationService {
  private readonly logger = new Logger(ReconciliationService.name);
  private readonly staleMinutes: number;
  private readonly batchLimit: number;
  /** Guards against overlapping runs if a sweep outlives its interval. */
  private running = false;

  constructor(
    private readonly prisma: PrismaService,
    private readonly rls: PrismaRlsService,
    @Inject(UNDERSTANDING_QUEUE_PORT)
    private readonly queue: UnderstandingQueuePort,
    config: ConfigService,
  ) {
    this.staleMinutes = this.positiveIntOrDefault(
      config.get<string>('RECONCILIATION_STALE_MINUTES'),
      DEFAULT_STALE_MINUTES,
    );
    this.batchLimit = this.positiveIntOrDefault(
      config.get<string>('RECONCILIATION_BATCH_LIMIT'),
      DEFAULT_BATCH_LIMIT,
    );
  }

  /** Runs the reconciliation sweep roughly once a minute (design.md §10.2). */
  @Cron(CronExpression.EVERY_MINUTE)
  async handleCron(): Promise<void> {
    if (this.running) {
      this.logger.debug('Reconciliation already running; skipping this tick.');
      return;
    }
    this.running = true;
    try {
      const reEnqueued = await this.reconcile();
      if (reEnqueued > 0) {
        this.logger.log(`Reconciliation re-enqueued ${reEnqueued} capture(s).`);
      }
    } catch (error) {
      this.logger.error(
        `Reconciliation sweep failed: ${(error as Error).message}`,
      );
    } finally {
      this.running = false;
    }
  }

  /**
   * Re-enqueue stale `raw` captures across all users, honouring a global batch
   * budget. Returns the number of captures re-enqueued. Exposed (not private)
   * so it can be driven directly by tests without the cron scheduler.
   */
  async reconcile(): Promise<number> {
    const threshold = new Date(Date.now() - this.staleMinutes * 60_000);
    let budget = this.batchLimit;
    let total = 0;

    // Enumerate users (no RLS on `users`); read each user's orphans under that
    // user's own RLS context (see the class-level RLS decision note).
    const users = await this.prisma.user.findMany({ select: { id: true } });

    for (const { id: userId } of users) {
      if (budget <= 0) {
        break;
      }

      const orphans = await this.rls.withUser(userId, (tx) =>
        tx.node.findMany({
          where: {
            userId,
            type: 'capture',
            status: 'raw',
            createdAt: { lt: threshold },
          },
          select: { id: true },
          orderBy: { createdAt: 'asc' },
          take: budget,
        }),
      );

      for (const orphan of orphans) {
        try {
          // Idempotent by jobId = capture_id: a live job is not duplicated.
          await this.queue.enqueueUnderstanding({
            schema_version: 1,
            capture_id: orphan.id,
            user_id: userId,
            enqueued_at: new Date().toISOString(),
          });
          total += 1;
          budget -= 1;
        } catch (error) {
          // A broker hiccup must not abort the whole sweep; the capture stays
          // `raw` and will be retried on the next tick.
          this.logger.warn(
            `Re-enqueue failed for capture ${orphan.id}: ${(error as Error).message}`,
          );
        }
        if (budget <= 0) {
          break;
        }
      }
    }

    return total;
  }

  private positiveIntOrDefault(
    raw: string | undefined,
    fallback: number,
  ): number {
    const parsed = Number(raw);
    return Number.isInteger(parsed) && parsed > 0 ? parsed : fallback;
  }
}
