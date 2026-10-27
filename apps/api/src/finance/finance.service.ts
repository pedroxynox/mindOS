import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { addDaysToKey } from '../common/time';
import { localDateKey, startOfLocalDayKey } from '../common/tz';
import { PrismaRlsService } from '../prisma/prisma-rls.service';
import {
  DEFAULT_CURRENCY,
  UserSettingsService,
} from '../users/user-settings.service';
import { canonicalCategory } from './categories';
import { CreateExpenseDto } from './dto/create-expense.dto';
import { ListExpensesQueryDto } from './dto/list-expenses-query.dto';
import {
  ExpenseListPage,
  ExpenseResponse,
  FinanceSummaryResponse,
  readAmount,
  readCategory,
  readCurrency,
  readSpentAt,
  toExpenseResponse,
} from './finance.mapper';

type ExpenseRow = { attributes: Prisma.JsonValue; createdAt: Date };

/** Expense rows (manual or AI): `note` nodes with `attributes.kind=expense`. */
const EXPENSE_WHERE = {
  type: 'note',
  deletedAt: null,
  attributes: { path: ['kind'], equals: 'expense' },
} satisfies Prisma.NodeWhereInput;

const EXPENSE_FIELDS = {
  id: true,
  attributes: true,
  createdAt: true,
  body: true,
  title: true,
  origin: true,
} as const;

const round2 = (n: number) => Math.round(n * 100) / 100;

/**
 * Pure summary computation (exported for testing). Buckets each expense by the
 * LOCAL day it was spent on (user's timezone, D-013) and only sums expenses in
 * the user's currency; other currencies are reported apart, never summed
 * without conversion (D-014).
 */
export function computeSummary(
  rows: ExpenseRow[],
  todayKey: string,
  timeZone: string,
  currency: string,
): Omit<FinanceSummaryResponse, 'currency'> {
  const weekKeys = Array.from({ length: 7 }, (_, i) =>
    addDaysToKey(todayKey, i - 6),
  );
  const weekIndex = new Map(weekKeys.map((k, i) => [k, i]));
  const prevKeys = new Set(
    Array.from({ length: 7 }, (_, i) => addDaysToKey(todayKey, i - 13)),
  );

  const daily = [0, 0, 0, 0, 0, 0, 0];
  let weekTotal = 0;
  let prevTotal = 0;
  const byCategory = new Map<string, number>();
  const others = new Map<string, number>();

  for (const row of rows) {
    const amount = readAmount(row);
    if (amount <= 0) continue;
    const key = localDateKey(readSpentAt(row), timeZone);
    const rowCurrency = readCurrency(row);
    const idx = weekIndex.get(key);

    if (rowCurrency !== currency) {
      if (idx !== undefined) {
        others.set(rowCurrency, (others.get(rowCurrency) ?? 0) + amount);
      }
      continue;
    }
    if (idx !== undefined) {
      daily[idx] += amount;
      weekTotal += amount;
      const cat = readCategory(row);
      byCategory.set(cat, (byCategory.get(cat) ?? 0) + amount);
    } else if (prevKeys.has(key)) {
      prevTotal += amount;
    }
  }

  const changePct =
    prevTotal > 0
      ? Math.round(((weekTotal - prevTotal) / prevTotal) * 100)
      : null;

  return {
    week_total: round2(weekTotal),
    prev_week_total: round2(prevTotal),
    change_pct: changePct,
    daily: daily.map(round2),
    by_category: [...byCategory.entries()]
      .map(([category, total]) => ({ category, total: round2(total) }))
      .sort(
        (a, b) => b.total - a.total || a.category.localeCompare(b.category),
      ),
    other_currencies: [...others.entries()]
      .map(([c, total]) => ({ currency: c, week_total: round2(total) }))
      .sort((a, b) => b.week_total - a.week_total),
  };
}

/**
 * Personal finance (lightweight). Expenses are `note` nodes discriminated by
 * `attributes.kind = 'expense'` (ADR-020); no schema migration and RLS applies
 * as-is. Currency and "today" come from the user's settings.
 */
@Injectable()
export class FinanceService {
  constructor(
    private readonly rls: PrismaRlsService,
    private readonly settings: UserSettingsService,
  ) {}

  async addExpense(
    userId: string,
    dto: CreateExpenseDto,
  ): Promise<ExpenseResponse> {
    const { currency } = await this.settings.get(userId);
    const now = new Date();
    let spentAt = now;
    if (dto.spent_at) {
      spentAt = new Date(dto.spent_at);
      if (spentAt.getTime() > now.getTime() + 60_000) {
        throw new BadRequestException({
          code: 'validation_error',
          message: 'spent_at cannot be in the future.',
        });
      }
    }
    const attributes: Prisma.InputJsonValue = {
      kind: 'expense',
      amount: dto.amount,
      currency: dto.currency ?? currency ?? DEFAULT_CURRENCY,
      spent_at: spentAt.toISOString(),
      category: canonicalCategory(dto.category),
    };
    const node = await this.rls.withUser(userId, (tx) =>
      tx.node.create({
        data: {
          userId,
          type: 'note',
          body: dto.note?.trim() || null,
          origin: 'manual_text',
          status: 'processed',
          attributes,
        },
        select: EXPENSE_FIELDS,
      }),
    );
    return toExpenseResponse(node);
  }

  /** Every expense, manual and AI-detected, most recently logged first. */
  async listExpenses(
    userId: string,
    query: ListExpensesQueryDto,
  ): Promise<ExpenseListPage> {
    const take = query.limit;
    const rows = await this.rls.withUser(userId, (tx) =>
      tx.node.findMany({
        where: { userId, ...EXPENSE_WHERE },
        orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
        take: take + 1,
        ...(query.cursor ? { cursor: { id: query.cursor }, skip: 1 } : {}),
        select: EXPENSE_FIELDS,
      }),
    );
    const next = rows.length > take ? rows[take].id : null;
    return {
      data: rows.slice(0, take).map(toExpenseResponse),
      next_cursor: next,
    };
  }

  /** Soft-delete an expense (and its provenance edge, for AI ones). */
  async removeExpense(userId: string, id: string): Promise<void> {
    await this.rls.withUser(userId, async (tx) => {
      const existing = await tx.node.findFirst({
        where: { id, userId, ...EXPENSE_WHERE },
        select: { id: true },
      });
      if (!existing) {
        throw new NotFoundException({
          code: 'not_found',
          message: 'Expense not found.',
        });
      }
      const now = new Date();
      await tx.node.update({ where: { id }, data: { deletedAt: now } });
      await tx.edge.updateMany({
        where: {
          userId,
          deletedAt: null,
          OR: [{ sourceNodeId: id }, { targetNodeId: id }],
        },
        data: { deletedAt: now },
      });
    });
  }

  async summary(
    userId: string,
    now: Date = new Date(),
  ): Promise<FinanceSummaryResponse> {
    const { timezone, currency: chosen } = await this.settings.get(userId);
    const todayKey = localDateKey(now, timezone);
    // One extra day of margin: expenses are bucketed by local spent day.
    const since = startOfLocalDayKey(addDaysToKey(todayKey, -14), timezone);

    const rows = await this.rls.withUser(userId, (tx) =>
      tx.node.findMany({
        where: { userId, ...EXPENSE_WHERE, createdAt: { gte: since } },
        orderBy: [{ createdAt: 'asc' }],
        select: { attributes: true, createdAt: true },
      }),
    );

    // The user's chosen currency; before they choose one, the currency of
    // their most recent expense (explicit order above), else USD.
    const currency =
      chosen ??
      (rows.length > 0
        ? readCurrency(rows[rows.length - 1])
        : DEFAULT_CURRENCY);

    return { currency, ...computeSummary(rows, todayKey, timezone, currency) };
  }
}
