/**
 * Calendar helpers shared by the day-bucketed features (briefing, growth,
 * finance). Pure functions over plain `YYYY-MM-DD` date keys so they are easy to
 * property-test and never depend on the server's local timezone.
 *
 * Today the callers pass UTC keys; per-user timezones (D-013) plug in by
 * computing the key in the user's zone (see `tz.ts`) — these helpers do not
 * change.
 */

const DAY_MS = 24 * 60 * 60 * 1000;

/** UTC calendar key (YYYY-MM-DD) of an instant. */
export function utcDateKey(instant: Date): string {
  return instant.toISOString().slice(0, 10);
}

/** Parse a `YYYY-MM-DD` key into the UTC midnight instant of that day. */
export function keyToUtcDate(key: string): Date {
  const [y, m, d] = key.split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, d));
}

/** Shift a date key by `days` (may be negative). */
export function addDaysToKey(key: string, days: number): string {
  return utcDateKey(new Date(keyToUtcDate(key).getTime() + days * DAY_MS));
}

/**
 * ISO-8601 week key (`YYYY-Www`) of a date key. Weeks start on Monday and the
 * week-year is the year that owns the week's Thursday, so 2026-01-01 (a
 * Thursday) is `2026-W01` and 2027-01-01 (a Friday) is `2026-W53`.
 */
export function isoWeekKey(key: string): string {
  const date = keyToUtcDate(key);
  // Monday=1 … Sunday=7.
  const weekday = date.getUTCDay() === 0 ? 7 : date.getUTCDay();
  // The Thursday of this week decides the ISO week-year.
  const thursday = new Date(date.getTime() + (4 - weekday) * DAY_MS);
  const weekYear = thursday.getUTCFullYear();
  const jan1 = Date.UTC(weekYear, 0, 1);
  const week = Math.floor((thursday.getTime() - jan1) / DAY_MS / 7) + 1;
  return `${weekYear}-W${String(week).padStart(2, '0')}`;
}

/** Normalise a person/entity name for grouping: trim, lowercase, no accents. */
export function normalizeName(name: string): string {
  return name
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/\s+/g, ' ')
    .trim();
}
