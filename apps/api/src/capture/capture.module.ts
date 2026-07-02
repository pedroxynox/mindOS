import { Module } from '@nestjs/common';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { BullModule } from '@nestjs/bullmq';
import { ScheduleModule } from '@nestjs/schedule';
import { S3Client } from '@aws-sdk/client-s3';
import { AuthModule } from '../auth/auth.module';
import { BlobJanitorService } from './blob-janitor.service';
import { BlobStorageService, S3_CLIENT } from './blob-storage.service';
import { CaptureController } from './capture.controller';
import { CaptureService } from './capture.service';
import { IdempotencyService } from './idempotency.service';
import { ReconciliationService } from './reconciliation.service';
import {
  BullUnderstandingQueue,
  UNDERSTANDING_QUEUE,
} from './understanding.queue';
import { UNDERSTANDING_QUEUE_PORT } from './understanding.queue.port';

/**
 * Builds the S3-compatible client from environment configuration. `endpoint`
 * and `forcePathStyle` support MinIO locally; region/credentials cover R2 in
 * production (design.md §9, ADR-012 D6).
 */
function createS3Client(config: ConfigService): S3Client {
  const endpoint = config.get<string>('S3_ENDPOINT');
  const region = config.get<string>('S3_REGION') ?? 'us-east-1';
  const accessKeyId = config.get<string>('S3_ACCESS_KEY_ID');
  const secretAccessKey = config.get<string>('S3_SECRET_ACCESS_KEY');
  const forcePathStyle =
    (config.get<string>('S3_FORCE_PATH_STYLE') ?? 'true') !== 'false';

  return new S3Client({
    region,
    ...(endpoint ? { endpoint } : {}),
    forcePathStyle,
    ...(accessKeyId && secretAccessKey
      ? { credentials: { accessKeyId, secretAccessKey } }
      : {}),
  });
}

/**
 * Capture bounded context (design.md §8, §10, §10.2, §9).
 *
 * Wiring:
 *  - Domain services + the S3 client (existing synchronous capture path).
 *  - BullMQ: a Redis connection (env-driven) and the `understanding` queue;
 *    `BullUnderstandingQueue` is bound behind `UNDERSTANDING_QUEUE_PORT` so the
 *    capture path and the reconciliation sweep depend only on the port (task 8).
 *  - `ScheduleModule` + the reconciliation sweep (task 9) and the orphan-blob
 *    janitor (task 10) crons.
 */
@Module({
  imports: [
    ConfigModule,
    AuthModule,
    ScheduleModule.forRoot(),
    BullModule.forRootAsync({
      imports: [ConfigModule],
      inject: [ConfigService],
      useFactory: (config: ConfigService) => ({
        connection: {
          host: config.get<string>('REDIS_HOST') ?? 'localhost',
          port: Number(config.get<string>('REDIS_PORT') ?? 6379),
          password: config.get<string>('REDIS_PASSWORD') || undefined,
          db: Number(config.get<string>('REDIS_DB') ?? 0),
        },
      }),
    }),
    BullModule.registerQueue({ name: UNDERSTANDING_QUEUE }),
  ],
  controllers: [CaptureController],
  providers: [
    CaptureService,
    IdempotencyService,
    BlobStorageService,
    ReconciliationService,
    BlobJanitorService,
    {
      provide: S3_CLIENT,
      inject: [ConfigService],
      useFactory: createS3Client,
    },
    {
      // BullMQ producer behind the port (task 8). Retries + dedup by
      // jobId = capture_id live in the adapter (design.md §10, P7).
      provide: UNDERSTANDING_QUEUE_PORT,
      useClass: BullUnderstandingQueue,
    },
  ],
})
export class CaptureModule {}
