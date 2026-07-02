import {
  BadRequestException,
  ForbiddenException,
  UnprocessableEntityException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { S3Client } from '@aws-sdk/client-s3';
import { BlobStorageService } from './blob-storage.service';

/**
 * Unit tests for BlobStorageService (task 4.2).
 *
 * The S3 client is a real S3Client configured with dummy static credentials so
 * that `getSignedUrl` can sign locally (no network), while `send` (HeadObject)
 * is stubbed. These tests cover the content-type allowlist, the size limit and
 * the key-ownership check — none of which require a live bucket.
 */
const USER_ID = '11111111-1111-1111-1111-111111111111';
const OTHER_USER = '22222222-2222-2222-2222-222222222222';

function buildConfig(): ConfigService {
  const values: Record<string, string> = {
    S3_BUCKET: 'mindos-audio',
    S3_PRESIGN_TTL: '300',
  };
  return {
    get: (key: string): string | undefined => values[key],
  } as unknown as ConfigService;
}

function buildService(sendImpl?: (command: unknown) => Promise<unknown>): {
  service: BlobStorageService;
  client: S3Client;
} {
  const client = new S3Client({
    region: 'us-east-1',
    endpoint: 'http://localhost:9000',
    forcePathStyle: true,
    credentials: { accessKeyId: 'test', secretAccessKey: 'test' },
  });
  if (sendImpl) {
    jest
      .spyOn(
        client as unknown as { send: (c: unknown) => Promise<unknown> },
        'send',
      )
      .mockImplementation(sendImpl);
  }
  const service = new BlobStorageService(client, buildConfig());
  return { service, client };
}

describe('BlobStorageService', () => {
  describe('presignUpload', () => {
    it('rejects a content_type outside the allowlist with 400', async () => {
      const { service } = buildService();
      await expect(
        service.presignUpload(USER_ID, 'application/pdf', 1024),
      ).rejects.toBeInstanceOf(BadRequestException);
    });

    it('rejects a size above the 25 MB limit with 400', async () => {
      const { service } = buildService();
      await expect(
        service.presignUpload(USER_ID, 'audio/m4a', 25 * 1024 * 1024 + 1),
      ).rejects.toBeInstanceOf(BadRequestException);
    });

    it('rejects a non-positive size with 400', async () => {
      const { service } = buildService();
      await expect(
        service.presignUpload(USER_ID, 'audio/mpeg', 0),
      ).rejects.toBeInstanceOf(BadRequestException);
    });

    it('mints a user-namespaced key and a presigned URL for allowed input', async () => {
      const { service } = buildService();
      const result = await service.presignUpload(USER_ID, 'audio/m4a', 2048);

      expect(result.audio_ref.startsWith(`audio/${USER_ID}/`)).toBe(true);
      expect(result.audio_ref.endsWith('.m4a')).toBe(true);
      expect(result.expires_in).toBe(300);
      expect(result.upload_url).toContain('http');
    });
  });

  describe('assertOwnedAndExists', () => {
    it("rejects a key prefixed with another user's id (403) without hitting S3", async () => {
      const send = jest.fn();
      const { service } = buildService(send);
      const foreignRef = `audio/${OTHER_USER}/abc.m4a`;

      await expect(
        service.assertOwnedAndExists(USER_ID, foreignRef),
      ).rejects.toBeInstanceOf(ForbiddenException);
      expect(send).not.toHaveBeenCalled();
    });

    it('rejects an owned but missing object with 422', async () => {
      const { service } = buildService(() =>
        Promise.reject(new Error('NotFound')),
      );
      await expect(
        service.assertOwnedAndExists(USER_ID, `audio/${USER_ID}/missing.m4a`),
      ).rejects.toBeInstanceOf(UnprocessableEntityException);
    });

    it('resolves when the owned object exists', async () => {
      const { service } = buildService(() => Promise.resolve({}));
      await expect(
        service.assertOwnedAndExists(USER_ID, `audio/${USER_ID}/ok.m4a`),
      ).resolves.toBeUndefined();
    });
  });

  describe('presignDownload', () => {
    it('rejects a foreign key prefix with 403', async () => {
      const { service } = buildService();
      await expect(
        service.presignDownload(USER_ID, `audio/${OTHER_USER}/x.m4a`),
      ).rejects.toBeInstanceOf(ForbiddenException);
    });

    it('returns a presigned URL for an owned key', async () => {
      const { service } = buildService();
      const url = await service.presignDownload(
        USER_ID,
        `audio/${USER_ID}/x.m4a`,
      );
      expect(url).toContain('http');
    });
  });
});
