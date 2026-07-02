import { ConfigService } from '@nestjs/config';
import { S3Client, CreateBucketCommand } from '@aws-sdk/client-s3';
import { BlobStorageService } from './blob-storage.service';

/**
 * Integration test for BlobStorageService against a REAL MinIO instance
 * (task 4.3).
 *
 * SKIPPED IN THIS ENVIRONMENT: it requires a running MinIO (S3-compatible)
 * broker, e.g. via docker-compose (`infra/docker-compose.yml`) with the
 * credentials/endpoint below. Unskip and run once MinIO is available:
 *
 *   docker compose up -d minio
 *   S3_ENDPOINT=http://localhost:9000 npm test -- blob-storage.minio
 *
 * It exercises the full round-trip: presign PUT -> upload the object ->
 * assertOwnedAndExists succeeds; a foreign or non-existent key fails
 * (Validates: Requirements R2.1, R2.3, R2.5 · Property P6).
 *
 * Gated on RUN_INTEGRATION=1: default `npm test` skips it; `RUN_INTEGRATION=1
 * npm test` runs it against the MinIO in infra/docker-compose.test.yml.
 */
const USER_ID = '11111111-1111-1111-1111-111111111111';
const OTHER_USER = '22222222-2222-2222-2222-222222222222';

const describeIntegration = process.env.RUN_INTEGRATION
  ? describe
  : describe.skip;

describeIntegration('BlobStorageService (integration, MinIO)', () => {
  let service: BlobStorageService;
  let client: S3Client;

  beforeAll(async () => {
    client = new S3Client({
      region: 'us-east-1',
      endpoint: process.env.S3_ENDPOINT ?? 'http://localhost:9000',
      forcePathStyle: true,
      credentials: {
        accessKeyId: process.env.S3_ACCESS_KEY_ID ?? 'minioadmin',
        secretAccessKey: process.env.S3_SECRET_ACCESS_KEY ?? 'minioadmin',
      },
    });
    const config = {
      get: (key: string): string | undefined =>
        ({ S3_BUCKET: 'mindos-audio', S3_PRESIGN_TTL: '300' })[key],
    } as unknown as ConfigService;
    service = new BlobStorageService(client, config);

    try {
      await client.send(new CreateBucketCommand({ Bucket: 'mindos-audio' }));
    } catch {
      // Bucket may already exist — ignore.
    }
  });

  it('round-trips presign -> upload -> assertOwnedAndExists', async () => {
    const { upload_url, audio_ref } = await service.presignUpload(
      USER_ID,
      'audio/m4a',
      11,
    );
    const put = await fetch(upload_url, {
      method: 'PUT',
      body: 'hello audio',
      headers: { 'content-type': 'audio/m4a' },
    });
    expect(put.ok).toBe(true);

    await expect(
      service.assertOwnedAndExists(USER_ID, audio_ref),
    ).resolves.toBeUndefined();
  });

  it('rejects a non-existent owned key and a foreign key', async () => {
    await expect(
      service.assertOwnedAndExists(USER_ID, `audio/${USER_ID}/nope.m4a`),
    ).rejects.toBeTruthy();
    await expect(
      service.assertOwnedAndExists(USER_ID, `audio/${OTHER_USER}/x.m4a`),
    ).rejects.toBeTruthy();
  });
});
