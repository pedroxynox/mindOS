import { Module } from '@nestjs/common';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { S3Client } from '@aws-sdk/client-s3';
import { AuthModule } from '../auth/auth.module';
import { BlobStorageService, S3_CLIENT } from './blob-storage.service';
import { CaptureController } from './capture.controller';
import { CaptureService } from './capture.service';
import { IdempotencyService } from './idempotency.service';
import {
  LoggingUnderstandingQueue,
  UNDERSTANDING_QUEUE_PORT,
} from './understanding.queue.port';

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
 * Capture bounded context (design.md §8). Registers the domain services, the
 * S3 client, and the understanding-queue port (temporary logging implementation
 * until task 8 swaps in BullMQ behind the same token). Wired into AppModule.
 */
@Module({
  imports: [ConfigModule, AuthModule],
  controllers: [CaptureController],
  providers: [
    CaptureService,
    IdempotencyService,
    BlobStorageService,
    {
      provide: S3_CLIENT,
      inject: [ConfigService],
      useFactory: createS3Client,
    },
    {
      provide: UNDERSTANDING_QUEUE_PORT,
      useClass: LoggingUnderstandingQueue,
    },
  ],
})
export class CaptureModule {}
