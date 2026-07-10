import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaRlsService } from '../prisma/prisma-rls.service';
import { CreateExpenseDto } from './dto/create-expense.dto';
import {
  ExpenseResponse,
  FinanceSummaryResponse,
  readAmount,
  toExpenseResponse,
} from './finance.mapper';

const DAY_MS = 24 * 60 * 60 * 1000;

type ExpenseRow = { attributes: Prisma.JsonValue; createdAt: Date };

/** UTC start-of-day for a date. */
function startOfUtcDay(d: Date): Date {
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()));
}

/**
 * Pure summary computation (exported for testing): trailing-7-day daily totals,
 * this-week vs previous-week totals and the percentage change.
 */
export function computeSummary(
  rows: ExpenseRow[],
  now: Date,
): Omit<FinanceSummaryResponse, 'currency'> {
  const today = startOfUtcDay(now);
  const windowStart = today.getTime() - 6 * DAY_MS; // 7-day window incl. today
  const prevStart = windowStart - 7 * DAY_MS;

  const daily = [0, 0, 0, 0, 0, 0, 0];
  let weekTotal = 0;
  let prevTotal = 0;

  for (const row of rows) {
    const amount = readAmount(row);
    if (amount <= 0) continue;
    const day = startOfUtcDay(row.createdAt).getTime();
    if (day >= windowStart && day <= today.getTime()) {
      const idx = Math.round((day - windowStart) / DAY_MS);
      if (idx >= 0 && idx < 7) daily[idx] += amount;
      weekTotal += amount;
    } else if (day >= prevStart && day < windowStart) {
      prevTotal += amount;
    }
  }

  const round2 = (n: number) => Math.round(n * 100) / 100;
  const changePct =
    prevTotal > 0
      ? Math.round(((weekTotal - prevTotal) / prevTotal) * 100)
      : null;

  return {
    week_total: round2(weekTotal),
    prev_week_total: round2(prevTotal),
    change_pct: changePct,
    daily: daily.map(round2),
  };
}

/**
 * Personal finance (lightweight). Expenses are `note` nodes discriminated by
 * `attributes.kind = 'expense'`; no schema migration and RLS applies as-is.
 */
@Injectable()
export class FinanceService {
  constructor(private readonly rls: PrismaRlsService) {}

  async addExpense(
    userId: string,
    dto: CreateExpenseDto,
  ): Promise<ExpenseResponse> {
    const attributes: Prisma.InputJsonValue = {
      kind: 'expense',
      amount: dto.amount,
      currency: dto.currency ?? 'USD',
      ...(dto.category ? { category: dto.category } : {}),
    };
    const node = await this.rls.withUser(userId, (tx) =>
      tx.node.create({
        data: {
          userId,
          type: 'note',
          body: dto.note?.trim() ?? null,
          origin: 'manual_text',
          status: 'processed',
          attributes,
        },
        select: { id: true, attributes: true, createdAt: true },
      }),
    );
    return toExpenseResponse(node);
  }

  async summary(userId: string): Promise<FinanceSummaryResponse> {
    const now = new Date();
    const since = new Date(startOfUtcDay(now).getTime() - 13 * DAY_MS);

    const rows = await this.rls.withUser(userId, (tx) =>
      tx.node.findMany({
        where: {
          userId,
          type: 'note',
          deletedAt: null,
          attributes: { path: ['kind'], equals: 'expense' },
          createdAt: { gte: since },
        },
        select: { attributes: true, createdAt: true },
      }),
    );

    // Currency: use the most recent expense's currency, else USD.
    const currency =
      rows.length > 0
        ? ((rows[rows.length - 1].attributes as { currency?: unknown })
            ?.currency as string) ?? 'USD'
        : 'USD';

    return { currency, ...computeSummary(rows, now) };
  }
}
