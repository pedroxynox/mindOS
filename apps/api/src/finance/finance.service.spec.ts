import { BadRequestException, NotFoundException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaRlsService } from '../prisma/prisma-rls.service';
import { UserSettingsService } from '../users/user-settings.service';
import { canonicalCategory, EXPENSE_CATEGORIES } from './categories';
import { computeSummary, FinanceService } from './finance.service';
import { ListExpensesQueryDto } from './dto/list-expenses-query.dto';

/**
 * Finance summary math (D-013/D-014): expenses are bucketed by the LOCAL day
 * they were spent, only the user's currency is summed (others are reported
 * apart), categories are aggregated for the week under their canonical key
 * (legacy free text included), and the week-over-week change is computed
 * (null without a baseline). The expense list mixes manual and AI-detected
 * expenses; removing one soft-deletes it and its provenance edge.
 */
const TODAY = '2026-07-10';

function expense(
  amount: number,
  spentAt: string,
  extra: Record<string, unknown> = {},
): { attributes: Prisma.JsonValue; createdAt: Date } {
  return {
    attributes: {
      kind: 'expense',
      amount,
      currency: 'BRL',
      spent_at: spentAt,
      ...extra,
    },
    createdAt: new Date(spentAt),
  };
}

describe('computeSummary', () => {
  it('totals the trailing 7 local days and fills the daily series', () => {
    const rows = [
      expense(10, '2026-07-10T12:00:00Z'),
      expense(5, '2026-07-10T13:00:00Z'),
      expense(20, '2026-07-07T12:00:00Z'),
    ];
    const s = computeSummary(rows, TODAY, 'UTC', 'BRL');
    expect(s.week_total).toBe(35);
    expect(s.daily).toEqual([0, 0, 0, 20, 0, 0, 15]);
  });

  it('buckets by the user’s local day, not UTC', () => {
    // 2026-07-11 01:30 UTC is still the 10th in São Paulo (UTC-3).
    const late = expense(42, '2026-07-11T01:30:00Z');
    const local = computeSummary([late], TODAY, 'America/Sao_Paulo', 'BRL');
    expect(local.daily[6]).toBe(42);
    const utc = computeSummary([late], TODAY, 'UTC', 'BRL');
    expect(utc.week_total).toBe(0); // the 11th is "tomorrow" in UTC
  });

  it('separates the previous week and computes the change percentage', () => {
    const rows = [
      expense(100, '2026-07-09T12:00:00Z'),
      expense(50, '2026-07-02T12:00:00Z'),
    ];
    const s = computeSummary(rows, TODAY, 'UTC', 'BRL');
    expect(s.week_total).toBe(100);
    expect(s.prev_week_total).toBe(50);
    expect(s.change_pct).toBe(100);
  });

  it('never sums other currencies into the user’s total', () => {
    const rows = [
      expense(30, '2026-07-10T10:00:00Z'),
      expense(12, '2026-07-10T11:00:00Z', { currency: 'USD' }),
      expense(8, '2026-07-09T11:00:00Z', { currency: 'USD' }),
    ];
    const s = computeSummary(rows, TODAY, 'UTC', 'BRL');
    expect(s.week_total).toBe(30);
    expect(s.other_currencies).toEqual([{ currency: 'USD', week_total: 20 }]);
  });

  it('aggregates this week by category, largest first', () => {
    const rows = [
      expense(10, '2026-07-10T10:00:00Z', { category: 'Comida' }),
      expense(25, '2026-07-09T10:00:00Z', { category: 'transporte' }),
      expense(5, '2026-07-08T10:00:00Z', { category: 'comida' }),
      expense(7, '2026-07-08T10:00:00Z'),
    ];
    const s = computeSummary(rows, TODAY, 'UTC', 'BRL');
    expect(s.by_category).toEqual([
      { category: 'transport', total: 25 },
      { category: 'food', total: 15 },
      { category: 'other', total: 7 },
    ]);
  });

  it('returns null change without a baseline and ignores non-positive amounts', () => {
    const s = computeSummary(
      [
        expense(30, '2026-07-10T10:00:00Z'),
        expense(-5, '2026-07-09T10:00:00Z'),
      ],
      TODAY,
      'UTC',
      'BRL',
    );
    expect(s.week_total).toBe(30);
    expect(s.change_pct).toBeNull();
  });
});

describe('canonicalCategory', () => {
  it.each([
    ['food', 'food'],
    ['Comida', 'food'],
    ['  Alimentación ', 'food'],
    ['almoço', 'food'],
    ['Uber', 'transport'],
    ['aluguel', 'home'],
    ['Farmacia', 'health'],
    ['cine', 'leisure'],
    ['ropa', 'shopping'],
    ['luz', 'bills'],
    ['Cursos', 'education'],
    ['otros', 'other'],
    ['algo raro', 'other'],
    [undefined, 'other'],
    [42, 'other'],
  ])('%j → %s', (raw, expected) => {
    expect(canonicalCategory(raw)).toBe(expected);
  });

  it('keeps every canonical key as is', () => {
    for (const key of EXPENSE_CATEGORIES) {
      expect(canonicalCategory(key)).toBe(key);
    }
  });
});

describe('FinanceService', () => {
  const USER_ID = '11111111-1111-1111-1111-111111111111';

  function build(
    settings: { timezone: string; currency: string | null },
    tx: {
      node: {
        create?: jest.Mock;
        findMany?: jest.Mock;
        findFirst?: jest.Mock;
        update?: jest.Mock;
      };
      edge?: { updateMany?: jest.Mock };
    },
  ) {
    const withUser = jest.fn(
      async <T>(
        _u: string,
        work: (t: Prisma.TransactionClient) => Promise<T>,
      ): Promise<T> => work(tx as unknown as Prisma.TransactionClient),
    );
    return new FinanceService(
      { withUser } as unknown as PrismaRlsService,
      {
        get: jest.fn().mockResolvedValue(settings),
      } as unknown as UserSettingsService,
    );
  }

  it('defaults a new expense to the user’s currency and stamps spent_at', async () => {
    const create = jest.fn().mockImplementation((args) =>
      Promise.resolve({
        id: 'e1',
        attributes: args.data.attributes,
        createdAt: new Date(),
        body: args.data.body,
        origin: 'manual_text',
      }),
    );
    const service = build(
      { timezone: 'America/Sao_Paulo', currency: 'BRL' },
      { node: { create } },
    );

    const res = await service.addExpense(USER_ID, {
      amount: 12.5,
      note: ' pan ',
    });

    expect(res.currency).toBe('BRL');
    expect(res.note).toBe('pan');
    expect(res.category).toBe('other');
    expect(res.capture_id).toBeNull();
    expect(typeof create.mock.calls[0][0].data.attributes.spent_at).toBe(
      'string',
    );
  });

  it('rejects an expense dated in the future', async () => {
    const service = build({ timezone: 'UTC', currency: null }, { node: {} });
    await expect(
      service.addExpense(USER_ID, {
        amount: 5,
        spent_at: new Date(Date.now() + 86_400_000).toISOString(),
      }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('summarises in the chosen currency with an explicit order', async () => {
    const findMany = jest.fn().mockResolvedValue([]);
    const service = build(
      { timezone: 'UTC', currency: 'MXN' },
      { node: { findMany } },
    );

    const s = await service.summary(USER_ID, new Date('2026-07-10T12:00:00Z'));

    expect(s.currency).toBe('MXN');
    expect(findMany.mock.calls[0][0].orderBy).toEqual([{ createdAt: 'asc' }]);
  });

  it('stores a typed category under its canonical key', async () => {
    const create = jest.fn().mockImplementation((args) =>
      Promise.resolve({
        id: 'e1',
        attributes: args.data.attributes,
        createdAt: new Date(),
        body: null,
        title: null,
        origin: 'manual_text',
      }),
    );
    const service = build(
      { timezone: 'UTC', currency: null },
      { node: { create } },
    );

    const res = await service.addExpense(USER_ID, {
      amount: 9,
      category: 'Taxi',
    });

    expect(create.mock.calls[0][0].data.attributes.category).toBe('transport');
    expect(res.category).toBe('transport');
    expect(res.currency).toBe('USD');
  });

  it('lists manual and AI expenses with a cursor', async () => {
    const row = (id: string, extra: Record<string, unknown> = {}) => ({
      id,
      attributes: {
        kind: 'expense',
        amount: 30,
        currency: 'BRL',
        category: 'food',
        spent_at: '2026-10-26T13:30:00.000Z',
        ...extra,
      },
      createdAt: new Date('2026-10-26T13:31:00.000Z'),
      body: null,
      title: 'almuerzo',
      origin: 'ai',
    });
    const findMany = jest
      .fn()
      .mockResolvedValue([row('a', { capture_id: 'c1' }), row('b')]);
    const service = build(
      { timezone: 'UTC', currency: 'BRL' },
      { node: { findMany } },
    );
    const query = Object.assign(new ListExpensesQueryDto(), { limit: 1 });

    const page = await service.listExpenses(USER_ID, query);

    expect(page.data).toEqual([
      expect.objectContaining({
        id: 'a',
        note: 'almuerzo',
        origin: 'ai',
        capture_id: 'c1',
        spent_at: '2026-10-26T13:30:00.000Z',
      }),
    ]);
    expect(page.next_cursor).toBe('b');
    const where = findMany.mock.calls[0][0].where;
    expect(where).toMatchObject({
      userId: USER_ID,
      type: 'note',
      deletedAt: null,
      attributes: { path: ['kind'], equals: 'expense' },
    });
  });

  it('removes an expense and its edges, 404 when it is not an expense', async () => {
    const findFirst = jest
      .fn()
      .mockResolvedValueOnce({ id: 'e1' })
      .mockResolvedValueOnce(null);
    const update = jest.fn().mockResolvedValue({});
    const updateMany = jest.fn().mockResolvedValue({ count: 1 });
    const service = build(
      { timezone: 'UTC', currency: null },
      { node: { findFirst, update }, edge: { updateMany } },
    );

    await service.removeExpense(USER_ID, 'e1');
    expect(update.mock.calls[0][0].data.deletedAt).toBeInstanceOf(Date);
    expect(updateMany.mock.calls[0][0].where.OR).toEqual([
      { sourceNodeId: 'e1' },
      { targetNodeId: 'e1' },
    ]);

    await expect(service.removeExpense(USER_ID, 'x')).rejects.toBeInstanceOf(
      NotFoundException,
    );
  });
});
