import { Prisma } from '@prisma/client';
import { computeSummary } from './finance.service';

/**
 * Unit tests for the finance summary math: expenses are bucketed into the
 * trailing-7-day window, this-week vs previous-week totals are separated, and
 * the percentage change is computed (null without a baseline).
 */
function expense(amount: number, daysAgo: number): {
  attributes: Prisma.JsonValue;
  createdAt: Date;
} {
  const now = new Date('2026-07-10T12:00:00.000Z');
  const d = new Date(now.getTime() - daysAgo * 24 * 60 * 60 * 1000);
  return {
    attributes: { kind: 'expense', amount, currency: 'USD' },
    createdAt: d,
  };
}

const NOW = new Date('2026-07-10T12:00:00.000Z');

describe('computeSummary', () => {
  it('totals the trailing 7 days and fills the daily series', () => {
    const rows = [expense(10, 0), expense(5, 0), expense(20, 3)];
    const s = computeSummary(rows, NOW);
    expect(s.week_total).toBe(35);
    expect(s.daily).toHaveLength(7);
    // Today is the last bucket.
    expect(s.daily[6]).toBe(15);
    expect(s.daily[3]).toBe(20);
  });

  it('separates the previous week and computes the change percentage', () => {
    const rows = [expense(100, 1), expense(50, 8)]; // this week 100, prev 50
    const s = computeSummary(rows, NOW);
    expect(s.week_total).toBe(100);
    expect(s.prev_week_total).toBe(50);
    expect(s.change_pct).toBe(100); // +100%
  });

  it('returns null change when there is no previous-week baseline', () => {
    const s = computeSummary([expense(30, 0)], NOW);
    expect(s.change_pct).toBeNull();
  });

  it('ignores non-positive amounts', () => {
    const s = computeSummary([expense(0, 0), expense(-5, 1)], NOW);
    expect(s.week_total).toBe(0);
  });
});
