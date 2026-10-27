import { Node } from '@prisma/client';

/**
 * Finance (lightweight, ADR-020): expenses are `note` nodes with
 * `attributes.kind = 'expense'` and `{ amount, currency, category, spent_at }`.
 * RLS on `nodes` isolates them per user and they are excluded from the
 * knowledge overview. Wire shapes are snake_case (#04).
 */
export interface ExpenseResponse {
  id: string;
  amount: number;
  category: string | null;
  currency: string;
  note: string | null;
  /** When the money was spent (defaults to when it was logged). */
  spent_at: string;
  /** 'manual_text' when typed by the user, 'ai' when detected in a capture. */
  origin: string;
  created_at: string;
}

export interface CategoryTotal {
  category: string;
  total: number;
}

export interface CurrencyTotal {
  currency: string;
  week_total: number;
}

export interface FinanceSummaryResponse {
  /** The user's currency; every total below is in it (no conversion). */
  currency: string;
  /** Total of the trailing 7 local days (today included). */
  week_total: number;
  /** Total of the previous 7 local days. */
  prev_week_total: number;
  /** Percentage change vs the previous week (null when no baseline). */
  change_pct: number | null;
  /** Trailing 7 daily totals, oldest first — for the sparkline. */
  daily: number[];
  /** This week's totals per category, largest first. */
  by_category: CategoryTotal[];
  /** This week's spend in OTHER currencies, reported apart (never summed). */
  other_currencies: CurrencyTotal[];
}

type ExpenseAttrs = {
  kind?: unknown;
  amount?: unknown;
  category?: unknown;
  currency?: unknown;
  spent_at?: unknown;
};

export function readAmount(node: Pick<Node, 'attributes'>): number {
  const a = (node.attributes ?? {}) as ExpenseAttrs;
  return typeof a.amount === 'number' && Number.isFinite(a.amount)
    ? a.amount
    : 0;
}

export function readCurrency(node: Pick<Node, 'attributes'>): string {
  const a = (node.attributes ?? {}) as ExpenseAttrs;
  return typeof a.currency === 'string' && a.currency.length > 0
    ? a.currency.toUpperCase()
    : 'USD';
}

export function readCategory(node: Pick<Node, 'attributes'>): string | null {
  const a = (node.attributes ?? {}) as ExpenseAttrs;
  return typeof a.category === 'string' && a.category.trim().length > 0
    ? a.category.trim()
    : null;
}

/** When the expense happened: `spent_at` if valid, else when it was logged. */
export function readSpentAt(
  node: Pick<Node, 'attributes' | 'createdAt'>,
): Date {
  const a = (node.attributes ?? {}) as ExpenseAttrs;
  if (typeof a.spent_at === 'string') {
    const d = new Date(a.spent_at);
    if (!Number.isNaN(d.getTime())) return d;
  }
  return node.createdAt;
}

export function toExpenseResponse(
  node: Pick<Node, 'id' | 'attributes' | 'createdAt' | 'body' | 'origin'>,
): ExpenseResponse {
  return {
    id: node.id,
    amount: readAmount(node),
    category: readCategory(node),
    currency: readCurrency(node),
    note: node.body ?? null,
    spent_at: readSpentAt(node).toISOString(),
    origin: node.origin,
    created_at: node.createdAt.toISOString(),
  };
}
