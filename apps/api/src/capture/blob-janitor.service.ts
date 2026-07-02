import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Cron, CronExpression } from '@nestjs/schedule';
import { PrismaService } from '../prisma/prisma.service';
import { PrismaRlsService } from '../prisma/prisma-rls.service';
import { BlobStorageService } from './blob-storage.service';

/** Default age (hours) after which an unreferenced audio object is purgeable. */
const DEFAULT_TTL_HOURS = 24;

/** Default cap on objects deleted per janitor run, to bound load. */
const DEFAULT_BATCH_LIMIT = 100;

/**
 * Orphan-blob janitor (design.md §9, refinement a).
 *
 * A voice capture uploads its audio directly to S3 via a presigned URL BEFORE
 * the capture row is created. If the client uploads but never completes
 * `POST /v1/captures` (crash, abandoned flow, lost network), the object is left
 * in S3 referenced by nothing. This cron purges such objects once they are
 * older than a TTL, so storage does not accumulate abandoned uploads. A
 * recently-uploaded object is spared (its capture may still be in flight), and
 * any object still referenced by a capture is never touched.
 *
 * ─── RLS decision ───────────────────────────────────────────────────────────
 * Like the reconciliation sweep, the janitor is cross-user but MUST NOT bypass
 * RLS. It enumerates users (the `users` table is not RLS-protected) and, for
 * each user, reads the referenced `audio_ref`s INSIDE that user's own
 * `PrismaRlsService.withUser` context, then reconciles them against the objects
 * stored under that user's `audio/{userId}/` prefix. Deletion is likewise
 * confined to that prefix, so one user's data can never affect another's.
 */
@Injectable()
export class BlobJanitorService {
  private readonly logger = new Logger(BlobJanitorService.name);
  private readonly ttlMs: number;
  private readonly batchLimit: number;
  /** Guards against overlapping runs. */
  private running = false;

  constructor(
    private readonly prisma: PrismaService,
    private readonly rls: PrismaRlsService,
    private readonly blobs: BlobStorageService,
    config: ConfigService,
  ) {
    const ttlHours = this.positiveIntOrDefault(
      config.get<string>('JANITOR_TTL_HOURS'),
      DEFAULT_TTL_HOURS,
    );
    this.ttlMs = ttlHours * 60 * 60 * 1000;
    this.batchLimit = this.positiveIntOrDefault(
      config.get<string>('JANITOR_BATCH_LIMIT'),
      DEFAULT_BATCH_LIMIT,
    );
  }

  /** Runs the orphan-blob sweep roughly once an hour (design.md §9). */
  @Cron(CronExpression.EVERY_HOUR)
  async handleCron(): Promise<void> {
    if (this.running) {
      this.logger.debug('Blob janitor already running; skipping this tick.');
      return;
    }
    this.running = true;
    try {
      const purged = await this.purgeOrphans();
      if (purged > 0) {
        this.logger.log(
          `Blob janitor purged ${purged} orphan audio object(s).`,
        );
      }
    } catch (error) {
      this.logger.error(`Blob janitor failed: ${(error as Error).message}`);
    } finally {
      this.running = false;
    }
  }

  /**
   * Delete unreferenced audio objects older than the TTL, across all users,
   * honouring a global batch budget. Returns the number of objects purged.
   * Exposed for direct test-driving without the scheduler.
   */
  async purgeOrphans(): Promise<number> {
    const cutoff = new Date(Date.now() - this.ttlMs);
    let budget = this.batchLimit;
    let purged = 0;

    const users = await this.prisma.user.findMany({ select: { id: true } });

    for (const { id: userId } of users) {
      if (budget <= 0) {
        break;
      }

      const [referenced, objects] = await Promise.all([
        this.referencedAudioRefs(userId),
        this.blobs.listAudioObjects(userId),
      ]);

      for (const object of objects) {
        if (budget <= 0) {
          break;
        }
        const isReferenced = referenced.has(object.key);
        const isExpired = object.lastModified.getTime() < cutoff.getTime();
        if (isReferenced || !isExpired) {
          continue;
        }
        try {
          await this.blobs.deleteObject(object.key);
          this.logger.log(`Purged orphan audio object '${object.key}'.`);
          purged += 1;
          budget -= 1;
        } catch (error) {
          this.logger.warn(
            `Failed to purge '${object.key}': ${(error as Error).message}`,
          );
        }
      }
    }

    return purged;
  }

  /**
   * Collect the set of `audio_ref`s referenced by a user's nodes, read under
   * that user's own RLS context. The `audio_ref` lives in the JSONB
   * `attributes`, so nodes are fetched and their references extracted in memory
   * (bounded per user).
   */
  private async referencedAudioRefs(userId: string): Promise<Set<string>> {
    const rows = await this.rls.withUser(userId, (tx) =>
      tx.node.findMany({
        where: { userId },
        select: { attributes: true },
      }),
    );

    const refs = new Set<string>();
    for (const row of rows) {
      const attributes = row.attributes as { audio_ref?: unknown } | null;
      if (attributes && typeof attributes.audio_ref === 'string') {
        refs.add(attributes.audio_ref);
      }
    }
    return refs;
  }

  private positiveIntOrDefault(
    raw: string | undefined,
    fallback: number,
  ): number {
    const parsed = Number(raw);
    return Number.isInteger(parsed) && parsed > 0 ? parsed : fallback;
  }
}
