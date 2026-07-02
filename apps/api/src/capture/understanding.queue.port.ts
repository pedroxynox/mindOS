import { Injectable, Logger } from '@nestjs/common';

/**
 * DI token for the understanding-queue port. CaptureService depends on this
 * abstraction, not on a concrete queue, so the synchronous capture path is
 * fully wired and testable before the BullMQ producer lands in task 8.
 */
export const UNDERSTANDING_QUEUE_PORT = Symbol('UNDERSTANDING_QUEUE_PORT');

/**
 * Contract of the understanding-handoff message (design.md §10). Versioned so
 * the F2 consumer can evolve without breaking (R9.4).
 */
export interface UnderstandingJobData {
  schema_version: 1;
  capture_id: string;
  user_id: string;
  enqueued_at: string;
}

/**
 * Port that hands a persisted capture off to the understanding pipeline (F2).
 * Task 8 will supply a BullMQ-backed implementation (dedup by `jobId`, retries,
 * `removeOnFail:false`); until then `LoggingUnderstandingQueue` provides a real,
 * wired implementation so nothing in the capture path is left dangling.
 */
export interface UnderstandingQueuePort {
  enqueueUnderstanding(data: UnderstandingJobData): Promise<void>;
}

/**
 * Temporary understanding-queue implementation that records the enqueue attempt
 * without an external broker. It is a genuine, injected provider (not dead
 * code): CaptureService calls it after persisting, and task 8 replaces it with
 * the BullMQ producer behind the same port.
 */
@Injectable()
export class LoggingUnderstandingQueue implements UnderstandingQueuePort {
  private readonly logger = new Logger(LoggingUnderstandingQueue.name);

  async enqueueUnderstanding(data: UnderstandingJobData): Promise<void> {
    // Persisted-before-enqueue is already guaranteed by the caller; here we only
    // record intent. BullMQ (task 8) will replace this with a real enqueue whose
    // jobId = capture_id provides handoff idempotency (P7).
    this.logger.log(
      `understanding handoff (stub): capture=${data.capture_id} user=${data.user_id} ` +
        `enqueued_at=${data.enqueued_at} schema_version=${data.schema_version}`,
    );
    return Promise.resolve();
  }
}
