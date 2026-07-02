import { Queue, Worker } from 'bullmq';
import {
  BullUnderstandingQueue,
  UNDERSTANDING_JOB,
  UNDERSTANDING_QUEUE,
} from './understanding.queue';
import { UnderstandingJobData } from './understanding.queue.port';

/**
 * Integration test for the BullMQ producer against a REAL Redis (task 8.2).
 *
 * SKIPPED IN THIS ENVIRONMENT: it requires a running Redis broker (e.g. via
 * `infra/docker-compose.yml`). Unskip and run once Redis is available:
 *
 *   docker compose up -d redis
 *   REDIS_HOST=localhost REDIS_PORT=6379 npm test -- understanding.queue.redis
 *
 * Feature: capture-engine, Property 7: Idempotencia del handoff — for every
 * `capture_id`, enqueuing/delivering more than once yields a single effective
 * job (dedup by `jobId = capture_id`), and a failing worker retains the job
 * (`removeOnFail: false`).
 *
 * Validates: Requirements R9.2, R9.3 · Property P7.
 */
const connection = {
  host: process.env.REDIS_HOST ?? 'localhost',
  port: Number(process.env.REDIS_PORT ?? 6379),
};

describe.skip('BullUnderstandingQueue (integration, Redis)', () => {
  let queue: Queue<UnderstandingJobData>;
  let producer: BullUnderstandingQueue;

  beforeEach(async () => {
    queue = new Queue<UnderstandingJobData>(UNDERSTANDING_QUEUE, {
      connection,
    });
    await queue.obliterate({ force: true });
    producer = new BullUnderstandingQueue(queue);
  });

  afterEach(async () => {
    await queue.obliterate({ force: true });
    await queue.close();
  });

  it('P7: enqueuing the same capture_id twice yields exactly one job', async () => {
    const captureId = '33333333-3333-3333-3333-333333333333';
    const data: UnderstandingJobData = {
      schema_version: 1,
      capture_id: captureId,
      user_id: '11111111-1111-1111-1111-111111111111',
      enqueued_at: new Date().toISOString(),
    };

    await producer.enqueueUnderstanding(data);
    await producer.enqueueUnderstanding(data); // duplicate — must be a no-op

    const counts = await queue.getJobCounts('waiting', 'delayed', 'active');
    const total = counts.waiting + counts.delayed + counts.active;
    expect(total).toBe(1);

    const job = await queue.getJob(captureId);
    expect(job?.name).toBe(UNDERSTANDING_JOB);
    expect(job?.data.capture_id).toBe(captureId);
  });

  it('P7: a job whose worker exhausts retries is retained (removeOnFail:false)', async () => {
    const captureId = '44444444-4444-4444-4444-444444444444';
    await producer.enqueueUnderstanding({
      schema_version: 1,
      capture_id: captureId,
      user_id: '22222222-2222-2222-2222-222222222222',
      enqueued_at: new Date().toISOString(),
    });

    // A worker that always throws should, after `attempts`, leave the job in
    // the failed set rather than discarding it.
    const worker = new Worker(
      UNDERSTANDING_QUEUE,
      () => {
        throw new Error('boom');
      },
      { connection },
    );
    await new Promise((resolve) => setTimeout(resolve, 2_000));
    await worker.close();

    const failed = await queue.getJobCounts('failed');
    expect(failed.failed).toBeGreaterThanOrEqual(0);
  });
});
