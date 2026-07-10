import { NotFoundException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaRlsService } from '../prisma/prisma-rls.service';
import { computeStreak, dateKey } from './growth.mapper';
import { GrowthService } from './growth.service';

/**
 * Unit tests for Growth: the streak helper, and the habit toggle (adds today
 * when absent, removes it when present) — the core habit mechanic. Prisma is a
 * lightweight double; writes run through PrismaRlsService.withUser (RLS).
 */
const USER_ID = '11111111-1111-1111-1111-111111111111';

function buildService(tx: {
  node: { findFirst?: jest.Mock; update?: jest.Mock };
}): GrowthService {
  const withUser = jest.fn(
    async <T>(
      _u: string,
      work: (t: Prisma.TransactionClient) => Promise<T>,
    ): Promise<T> => work(tx as unknown as Prisma.TransactionClient),
  );
  return new GrowthService({ withUser } as unknown as PrismaRlsService);
}

describe('computeStreak', () => {
  const today = new Date('2026-07-10T12:00:00.000Z');

  it('counts consecutive days ending today', () => {
    const dates = ['2026-07-08', '2026-07-09', '2026-07-10'];
    expect(computeStreak(dates, today)).toBe(3);
  });

  it('still counts a streak that ends yesterday (grace day)', () => {
    expect(computeStreak(['2026-07-08', '2026-07-09'], today)).toBe(2);
  });

  it('breaks the streak when both today and yesterday are missing', () => {
    expect(computeStreak(['2026-07-06', '2026-07-07'], today)).toBe(0);
  });

  it('is zero for an empty log', () => {
    expect(computeStreak([], today)).toBe(0);
  });
});

describe('GrowthService.toggleHabitToday', () => {
  it('adds today when not yet completed', async () => {
    const findFirst = jest
      .fn()
      .mockResolvedValue({ id: 'h1', title: 'Meditar', attributes: { kind: 'habit', log: [] } });
    let savedLog: string[] = [];
    const update = jest.fn().mockImplementation((args) => {
      savedLog = args.data.attributes.log;
      return Promise.resolve({
        id: 'h1',
        title: 'Meditar',
        body: null,
        attributes: args.data.attributes,
        createdAt: new Date('2026-07-10T00:00:00.000Z'),
      });
    });
    const service = buildService({ node: { findFirst, update } });

    const result = await service.toggleHabitToday(USER_ID, 'h1');

    expect(savedLog).toContain(dateKey(new Date()));
    expect(result.done_today).toBe(true);
  });

  it('removes today when already completed', async () => {
    const today = dateKey(new Date());
    const findFirst = jest.fn().mockResolvedValue({
      id: 'h1',
      title: 'Meditar',
      attributes: { kind: 'habit', log: [today] },
    });
    const update = jest.fn().mockImplementation((args) =>
      Promise.resolve({
        id: 'h1',
        title: 'Meditar',
        body: null,
        attributes: args.data.attributes,
        createdAt: new Date('2026-07-10T00:00:00.000Z'),
      }),
    );
    const service = buildService({ node: { findFirst, update } });

    const result = await service.toggleHabitToday(USER_ID, 'h1');

    expect(result.done_today).toBe(false);
  });

  it('throws NotFound for a habit that is not the caller\'s', async () => {
    const findFirst = jest.fn().mockResolvedValue(null);
    const service = buildService({ node: { findFirst } });
    await expect(
      service.toggleHabitToday(USER_ID, 'missing'),
    ).rejects.toBeInstanceOf(NotFoundException);
  });
});
