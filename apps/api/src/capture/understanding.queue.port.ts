/**
 * DI token for the understanding-queue port. CaptureService depends on this
 * abstraction, not on a concrete queue, so the capture path stays decoupled
 * from the broker and remains unit-testable with a lightweight double.
 *
 * The concrete implementation bound to this token is `BullUnderstandingQueue`
 * (see `understanding.queue.ts`), which produces to BullMQ/Redis with
 * `jobId = capture_id` for handoff idempotency (design.md §10, P7).
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
 * The synchronous capture path and the reconciliation sweep both depend on this
 * interface; the BullMQ adapter provides the concrete behaviour (dedup by
 * `jobId`, retries with exponential backoff, `removeOnFail: false`).
 */
export interface UnderstandingQueuePort {
  enqueueUnderstanding(data: UnderstandingJobData): Promise<void>;
}
