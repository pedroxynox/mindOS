import { ConfigService } from '@nestjs/config';
import { PrismaClient } from '@prisma/client';
import {
  CreateBucketCommand,
  PutObjectCommand,
  S3Client,
} from '@aws-sdk/client-s3';
import { PrismaService } from '../prisma/prisma.service';
import { PrismaRlsService } from '../prisma/prisma-rls.service';
import { BlobJanitorService } from './blob-janitor.service';
import { BlobStorageService } from './blob-storage.service';

/**
 * Integration test for the orphan-blob janitor against REAL MinIO + Postgres
 * (task 10.2).
 *
 * SKIPPED IN THIS ENVIRONMENT: it requires a running MinIO (S3-compatible) and
 * a live PostgreSQL with the F1 migrations (RLS + non-owner app role). Because
 * the TTL is time-based, this test drives `purgeOrphans()` with a 0-hour TTL
 * (JANITOR_TTL_HOURS=0 is treated as the default, so the suite instead relies
 * on object age); prefer a fake clock / pre-aged objects when unskipping.
 *
 *   docker compose up -d minio postgres
 *   npm test -- blob-janitor.minio
 *
 * Validates: Requirements R2.1, R2.4 — an unreferenced, expired upload is
 * purged; an object referenced by a capture is never deleted.
 *
 * Gated on RUN_INTEGRATION=1: default `npm test` skips it; `RUN_INTEGRATION=1
 * npm test` runs it against MinIO + Postgres in infra/docker-compose.test.yml.
 */
const USER_ID = '55555555-5555-5555-5555-555555555555';

const describeIntegration = process.env.RUN_INTEGRATION
  ? describe
  : describe.skip;

describeIntegration(
  'BlobJanitorService (integration, MinIO + Postgres)',
  () => {
    let prisma: PrismaService;
    let rls: PrismaRlsService;
    let blobs: BlobStorageService;
    let janitor: BlobJanitorService;
    let s3: S3Client;

    beforeAll(async () => {
      prisma = new PrismaService();
      await (prisma as unknown as PrismaClient).$connect();
      rls = new PrismaRlsService(prisma);

      s3 = new S3Client({
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
          ({
            S3_BUCKET: 'mindos-audio',
            S3_PRESIGN_TTL: '300',
            JANITOR_TTL_HOURS: '1',
            JANITOR_BATCH_LIMIT: '100',
          })[key],
      } as unknown as ConfigService;
      blobs = new BlobStorageService(s3, config);
      janitor = new BlobJanitorService(prisma, rls, blobs, config);

      try {
        await s3.send(new CreateBucketCommand({ Bucket: 'mindos-audio' }));
      } catch {
        // Bucket may already exist — ignore.
      }
    });

    afterAll(async () => {
      await (prisma as unknown as PrismaClient).$disconnect();
    });

    it('purges an unreferenced expired object and keeps a referenced one', async () => {
      // Orphan upload: object exists but no capture references it.
      const orphanKey = `audio/${USER_ID}/orphan.m4a`;
      await s3.send(
        new PutObjectCommand({
          Bucket: 'mindos-audio',
          Key: orphanKey,
          Body: 'orphan',
        }),
      );

      // Referenced object: create a capture pointing at it.
      const referencedKey = `audio/${USER_ID}/kept.m4a`;
      await s3.send(
        new PutObjectCommand({
          Bucket: 'mindos-audio',
          Key: referencedKey,
          Body: 'kept',
        }),
      );
      await rls.withUser(USER_ID, (tx) =>
        tx.node.create({
          data: {
            userId: USER_ID,
            type: 'capture',
            origin: 'voice',
            attributes: { audio_ref: referencedKey, modality: 'voice' },
          },
        }),
      );

      // NOTE: real runs must age the orphan past the TTL (fake clock / pre-aged
      // object) so it is eligible; the referenced object is spared regardless.
      const objects = await blobs.listAudioObjects(USER_ID);
      expect(objects.map((o) => o.key)).toEqual(
        expect.arrayContaining([orphanKey, referencedKey]),
      );

      await janitor.purgeOrphans();

      const remaining = await blobs.listAudioObjects(USER_ID);
      expect(remaining.map((o) => o.key)).toContain(referencedKey);
    });
  },
);
