import { NotFoundException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import * as fc from 'fast-check';
import { addDaysToKey, isoWeekKey } from '../common/time';
import { PrismaRlsService } from '../prisma/prisma-rls.service';
import { UserSettingsService } from '../users/user-settings.service';
import {
  computeStreak,
  computeWeeklyStreak,
  toGoalResponse,
  toHabitResponse,
} from './growth.mapper';
import { GrowthService } from './growth.service';

/**
 * Unit tests for Growth: daily and weekly streaks, derived goal completion, and
 * the habit toggle (adds today when absent, removes it when present). Prisma is
 * a lightweight double; writes run through PrismaRlsService.withUser (RLS).
 */
const USER_ID = '11111111-1111-1111-1111-111111111111';
const TODAY = '2026-07-10'; // a Friday

function buildService(tx: {
  node: { findFirst?: jest.Mock; update?: jest.Mock };
}): GrowthService {
  const withUser = jest.fn(
    async <T>(
      _u: string,
      work: (t: Prisma.TransactionClient) => Promise<T>,
    ): Promise<T> => work(tx as unknown as Prisma.TransactionClient),
  );
  const settings = {
    get: jest.fn().mockResolvedValue({ timezone: 'America/Sao_Paulo', currency: null }),
  } as unknown as UserSettingsService;
  return new GrowthService({ withUser } as unknown as PrismaRlsService, settings);
}

function habitNode(attributes: Record<string, unknown>) {
  return {
    id: 'h1',
    title: 'Meditar',
    attributes: { kind: 'habit', ...attributes },
    createdAt: new Date('2026-07-01T00:00:00.000Z'),
  };
}

describe('computeStreak (daily)', () => {
  it('counts consecutive days ending today', () => {
    expect(
      computeStreak(['2026-07-08', '2026-07-09', '2026-07-10'], TODAY),
    ).toBe(3);
  });

  it('still counts a streak that ends yesterday (grace day)', () => {
    expect(computeStreak(['2026-07-08', '2026-07-09'], TODAY)).toBe(2);
  });

  it('breaks the streak when both today and yesterday are missing', () => {
    expect(computeStreak(['2026-07-06', '2026-07-07'], TODAY)).toBe(0);
  });

  it('is zero for an empty log', () => {
    expect(computeStreak([], TODAY)).toBe(0);
  });

  it('crosses month boundaries', () => {
    expect(computeStreak(['2026-06-30', '2026-07-01'], '2026-07-01')).toBe(2);
  });
});

describe('computeWeeklyStreak', () => {
  it('counts consecutive ISO weeks with at least one check', () => {
    // Weeks of 2026-06-24 (W26), 2026-07-01 (W27) and 2026-07-08 (W28).
    expect(
      computeWeeklyStreak(['2026-06-24', '2026-07-01', '2026-07-08'], TODAY),
    ).toBe(3);
  });

  it('keeps last week as grace while this week is still in progress', () => {
    expect(computeWeeklyStreak(['2026-06-30', '2026-07-02'], TODAY)).toBe(1);
  });

  it('counts several checks in one week only once', () => {
    expect(
      computeWeeklyStreak(['2026-07-06', '2026-07-07', '2026-07-10'], TODAY),
    ).toBe(1);
  });

  it('is zero when neither this week nor last week has a check', () => {
    expect(computeWeeklyStreak(['2026-06-15'], TODAY)).toBe(0);
  });

  it('never exceeds the number of distinct weeks logged (property)', () => {
    fc.assert(
      fc.property(fc.array(fc.integer({ min: 0, max: 120 })), (offsets) => {
        const log = offsets.map((o) => addDaysToKey(TODAY, -o));
        const weeks = new Set(log.map(isoWeekKey)).size;
        expect(computeWeeklyStreak(log, TODAY)).toBeLessThanOrEqual(weeks);
      }),
    );
  });
});

describe('isoWeekKey', () => {
  it('follows ISO-8601 week-year rules at year boundaries', () => {
    expect(isoWeekKey('2026-01-01')).toBe('2026-W01'); // Thursday
    expect(isoWeekKey('2027-01-01')).toBe('2026-W53'); // Friday
    expect(isoWeekKey('2026-07-10')).toBe('2026-W28');
  });
});

describe('toGoalResponse', () => {
  it('derives done from progress, so lowering progress re-opens the goal', () => {
    const base = { id: 'g', title: 'x', createdAt: new Date() };
    expect(
      toGoalResponse({ ...base, attributes: { progress: 100 } }).done,
    ).toBe(true);
    expect(
      toGoalResponse({ ...base, attributes: { progress: 60, done: true } })
        .done,
    ).toBe(false);
  });
});

describe('toHabitResponse', () => {
  it('reports weekly streaks in weeks and satisfies the period with any check', () => {
    const res = toHabitResponse(
      habitNode({ cadence: 'weekly', log: ['2026-07-07'] }),
      TODAY,
    );
    expect(res.streak_unit).toBe('week');
    expect(res.streak).toBe(1);
    expect(res.done_today).toBe(false);
    expect(res.period_done).toBe(true);
  });

  it('reports daily streaks in days', () => {
    const res = toHabitResponse(habitNode({ log: [TODAY] }), TODAY);
    expect(res.streak_unit).toBe('day');
    expect(res.period_done).toBe(true);
  });
});

describe('GrowthService.toggleHabitToday', () => {
  function updateEcho() {
    return jest.fn().mockImplementation((args) =>
      Promise.resolve({
        ...habitNode({}),
        body: null,
        attributes: args.data.attributes,
      }),
    );
  }

  it('adds today when not yet completed', async () => {
    const findFirst = jest.fn().mockResolvedValue(habitNode({ log: [] }));
    const update = updateEcho();
    const service = buildService({ node: { findFirst, update } });

    const result = await service.toggleHabitToday(USER_ID, 'h1', TODAY);

    expect(update.mock.calls[0][0].data.attributes.log).toEqual([TODAY]);
    expect(result.done_today).toBe(true);
  });

  it('removes today when already completed', async () => {
    const findFirst = jest.fn().mockResolvedValue(habitNode({ log: [TODAY] }));
    const service = buildService({ node: { findFirst, update: updateEcho() } });

    const result = await service.toggleHabitToday(USER_ID, 'h1', TODAY);

    expect(result.done_today).toBe(false);
  });

  it("checks the user's LOCAL day when no day is given", async () => {
    const findFirst = jest.fn().mockResolvedValue(habitNode({ log: [] }));
    const update = updateEcho();
    const service = buildService({ node: { findFirst, update } });

    jest.useFakeTimers().setSystemTime(new Date('2026-07-11T01:30:00.000Z'));
    try {
      await service.toggleHabitToday(USER_ID, 'h1');
    } finally {
      jest.useRealTimers();
    }

    // Still the 10th in São Paulo (UTC-3).
    expect(update.mock.calls[0][0].data.attributes.log).toEqual(['2026-07-10']);
  });

  it("throws NotFound for a habit that is not the caller's", async () => {
    const findFirst = jest.fn().mockResolvedValue(null);
    const service = buildService({ node: { findFirst } });
    await expect(
      service.toggleHabitToday(USER_ID, 'missing', TODAY),
    ).rejects.toBeInstanceOf(NotFoundException);
  });
});

describe('GrowthService.updateGoal', () => {
  it('stores done=false again when progress drops below 100', async () => {
    const findFirst = jest.fn().mockResolvedValue({
      id: 'g1',
      title: 'Correr',
      attributes: { kind: 'goal', progress: 100, done: true },
      createdAt: new Date(),
    });
    const update = jest.fn().mockImplementation((args) =>
      Promise.resolve({
        id: 'g1',
        title: 'Correr',
        body: null,
        attributes: args.data.attributes,
        createdAt: new Date(),
      }),
    );
    const service = buildService({ node: { findFirst, update } });

    const result = await service.updateGoal(USER_ID, 'g1', { progress: 70 });

    expect(update.mock.calls[0][0].data.attributes.done).toBe(false);
    expect(result.done).toBe(false);
    expect(result.progress).toBe(70);
  });

  it('accepts the snake_case target_date and its camelCase alias', async () => {
    const findFirst = jest.fn().mockResolvedValue({
      id: 'g1',
      title: 'x',
      attributes: { kind: 'goal' },
      createdAt: new Date(),
    });
    const update = jest.fn().mockImplementation((args) =>
      Promise.resolve({
        id: 'g1',
        title: 'x',
        body: null,
        attributes: args.data.attributes,
        createdAt: new Date(),
      }),
    );
    const service = buildService({ node: { findFirst, update } });

    const a = await service.updateGoal(USER_ID, 'g1', {
      target_date: '2026-12-31T00:00:00.000Z',
    });
    const b = await service.updateGoal(USER_ID, 'g1', {
      targetDate: '2027-01-31T00:00:00.000Z',
    });
    expect(a.target_date).toBe('2026-12-31T00:00:00.000Z');
    expect(b.target_date).toBe('2027-01-31T00:00:00.000Z');
  });
});

describe('GrowthService.remove', () => {
  it('soft-deletes an owned item', async () => {
    const findFirst = jest.fn().mockResolvedValue(habitNode({}));
    const update = jest.fn().mockResolvedValue({});
    const service = buildService({ node: { findFirst, update } });

    await service.remove(USER_ID, 'h1', 'habit');

    expect(update.mock.calls[0][0].data.deletedAt).toBeInstanceOf(Date);
  });

  it('throws NotFound for an item of another kind or user', async () => {
    const service = buildService({
      node: { findFirst: jest.fn().mockResolvedValue(null) },
    });
    await expect(service.remove(USER_ID, 'x', 'goal')).rejects.toBeInstanceOf(
      NotFoundException,
    );
  });
});
