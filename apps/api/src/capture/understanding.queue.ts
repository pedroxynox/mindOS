import { Injectable, Logger } from '@nestjs/common';
import { InjectQueue } from '@nestjs/bullmq';
import { JobsOptions, Queue } from 'bullmq';
import {
  UnderstandingJobData,
  UnderstandingQueuePort,
} from './understanding.queue.port';

/**
 * BullMQ queue name for the understanding handoff (design.md §10). Referenced by
 * `BullModule.registerQueue` and `@InjectQueue` so the producer here and the F2
 * consumer agree on the same queue.
 */
export const UNDERSTANDING_QUEUE = 'understanding';

/** Job name for a single "process this capture" unit of work (design.md §10). */
export const UNDERSTANDING_JOB = 'understanding.process';

/**
 * Reliability options for every understanding job (design.md §10):
 *  - `attempts: 5` with exponential backoff (2s base) so transient worker
 *    failures are retried without hammering the consumer.
 *  - `removeOnComplete: 1000` keeps the queue bounded while retaining recent
 *    successes for observability.
 *  - `removeOnFail: false` retains exhausted jobs for inspection / replay, so a
 *    failed understanding never silently discards the (already-safe) capture.
 *
 * NOTE: `jobId` is intentionally NOT set here — it is supplied per-enqueue as
 * `jobId = capture_id`, which is what gives the handoff its idempotency (P7).
 */
export const understandingJobOpts: JobsOptions = {
  attempts: 5,
  backoff: { type: 'exponential', delay: 2_000 },
  removeOnComplete: 1_000,
  removeOnFail: false,
};

/**
 * BullMQ-backed producer for the understanding pipeline (F2 consumes it).
 * Implements the `UnderstandingQueuePort` so `CaptureService` and the
 * reconciliation sweep depend only on the abstraction.
 *
 * Idempotency (P7): the job is enqueued with `jobId = capture_id`. BullMQ
 * ignores a second `add` for an existing job id, so retries from the network,
 * the client, or the reconciliation sweep never create a duplicate job for the
 * same capture.
 */
@Injectable()
export class BullUnderstandingQueue implements UnderstandingQueuePort {
  private readonly logger = new Logger(BullUnderstandingQueue.name);

  constructor(
    @InjectQueue(UNDERSTANDING_QUEUE)
    private readonly queue: Queue<UnderstandingJobData>,
  ) {}

  /**
   * Enqueue an understanding job for a persisted capture. Uses
   * `jobId = capture_id` so the enqueue is idempotent (dedup by job id).
   */
  async enqueueUnderstanding(data: UnderstandingJobData): Promise<void> {
    await this.queue.add(UNDERSTANDING_JOB, data, {
      jobId: data.capture_id,
      ...understandingJobOpts,
    });
    this.logger.debug(
      `enqueued understanding job capture=${data.capture_id} user=${data.user_id}`,
    );
  }
}
