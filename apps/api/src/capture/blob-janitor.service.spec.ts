import { ConfigService } from '@nestjs/config';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { PrismaRlsService } from '../prisma/prisma-rls.service';
import { BlobJanitorService } from './blob-janitor.service';
import { AudioObject, BlobStorageService } from './blob-storage.service';

/**
 * Unit tests for the orphan-blob janitor (task 10.1) over in-memory doubles.
 * Verifies: an unreferenced object older than the TTL is purged; a referenced
 * object is spared; a fresh unreferenced object is spared; the batch budget
 * caps a run. Per-user reads go through `rls.withUser`, mirroring RLS scoping.
 */
const USER_ID = '55555555-5555-5555-5555-555555555555';
const hoursAgo = (h: number): Date => new Date(Date.now() - h * 3_600_000);

interface Harness {
  janitor: BlobJanitorService;
  deleted: string[];
}

function buildHarness(params: {
  objects: AudioObject[];
  referenced: string[];
  ttlHours?: string;
  batchLimit?: string;
}): Harness {
  const prisma = {
    user: { findMany: () => Promise.resolve([{ id: USER_ID }]) },
  } as unknown as PrismaService;

  const rls = {
    withUser: <T>(
      _userId: string,
      work: (tx: Prisma.TransactionClient) => Promise<T>,
    ): Promise<T> => {
      const tx = {
        node: {
          findMany: (): Promise<Array<{ attributes: unknown }>> =>
            Promise.resolve(
              params.referenced.map((ref) => ({
                attributes: { audio_ref: ref, modality: 'voice' },
              })),
            ),
        },
      } as unknown as Prisma.TransactionClient;
      return work(tx);
    },
  } as unknown as PrismaRlsService;

  const deleted: string[] = [];
  const blobs = {
    listAudioObjects: () => Promise.resolve(params.objects),
    deleteObject: (key: string) => {
      deleted.push(key);
      return Promise.resolve();
    },
  } as unknown as BlobStorageService;

  const config = {
    get: (key: string): string | undefined =>
      ({
        JANITOR_TTL_HOURS: params.ttlHours,
        JANITOR_BATCH_LIMIT: params.batchLimit,
      })[key],
  } as unknown as ConfigService;

  return {
    janitor: new BlobJanitorService(prisma, rls, blobs, config),
    deleted,
  };
}

describe('BlobJanitorService', () => {
  it('purges an unreferenced object older than the TTL', async () => {
    const { janitor, deleted } = buildHarness({
      objects: [
        {
          key: `audio/${USER_ID}/orphan.m4a`,
          lastModified: hoursAgo(48),
          size: 10,
        },
      ],
      referenced: [],
    });

    expect(await janitor.purgeOrphans()).toBe(1);
    expect(deleted).toEqual([`audio/${USER_ID}/orphan.m4a`]);
  });

  it('never deletes a referenced object, even when old', async () => {
    const key = `audio/${USER_ID}/kept.m4a`;
    const { janitor, deleted } = buildHarness({
      objects: [{ key, lastModified: hoursAgo(72), size: 10 }],
      referenced: [key],
    });

    expect(await janitor.purgeOrphans()).toBe(0);
    expect(deleted).toEqual([]);
  });

  it('spares a fresh unreferenced object (within TTL)', async () => {
    const { janitor, deleted } = buildHarness({
      objects: [
        {
          key: `audio/${USER_ID}/fresh.m4a`,
          lastModified: hoursAgo(1),
          size: 10,
        },
      ],
      referenced: [],
    });

    expect(await janitor.purgeOrphans()).toBe(0);
    expect(deleted).toEqual([]);
  });

  it('honours the batch limit', async () => {
    const objects: AudioObject[] = Array.from({ length: 5 }, (_, i) => ({
      key: `audio/${USER_ID}/o${i}.m4a`,
      lastModified: hoursAgo(48),
      size: 10,
    }));
    const { janitor, deleted } = buildHarness({
      objects,
      referenced: [],
      batchLimit: '3',
    });

    expect(await janitor.purgeOrphans()).toBe(3);
    expect(deleted).toHaveLength(3);
  });
});
