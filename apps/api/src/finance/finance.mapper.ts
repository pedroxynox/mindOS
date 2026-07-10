import { Node } from '@prisma/client';

/**
 * Finance is a lightweight, zero-migration feature: expenses are stored as
 * `node` rows of type `note` with `attributes.kind = 'expense'` and
 * `{ amount, category, currency }`. RLS on `nodes` isolates them per user, and
 * they are already excluded from the knowledge overview (notes are excluded).
 * Wire shapes are snake_case (#04).
 */
export interface ExpenseResponse {
  id: string;
  amount: number;
  category: string | null;
  currency: string;
  created_at: string;
}

export interface FinanceSummaryResponse {
  currency: string;
  /** Total of the trailing 7 days (today included). */
  week_total: number;
  /** Total of the previous 7 days. */
  prev_week_total: number;
  /** Percentage change vs the previous week (null when no baseline). */
  change_pct: number | null;
  /** Trailing 7 daily totals, oldest first — for the sparkline. */
  daily: number[];
}

type ExpenseAttrs = {
  kind?: unknown;
  amount?: unknown;
  category?: unknown;
  currency?: unknown;
};

export function readAmount(node: Pick<Node, 'attributes'>): number {
  const a = (node.attributes ?? {}) as ExpenseAttrs;
  return typeof a.amount === 'number' && Number.isFinite(a.amount)
    ? a.amount
    : 0;
}

export function toExpenseResponse(
  node: Pick<Node, 'id' | 'attributes' | 'createdAt'>,
): ExpenseResponse {
  const a = (node.attributes ?? {}) as ExpenseAttrs;
  return {
    id: node.id,
    amount: readAmount(node),
    category: typeof a.category === 'string' ? a.category : null,
    currency: typeof a.currency === 'string' ? a.currency : 'USD',
    created_at: node.createdAt.toISOString(),
  };
}
