/**
 * Timezone-aware calendar math (D-013) using only the platform ICU data
 * (`Intl`), so no extra dependency. Every "today" the API computes —
 * briefing, finance day buckets, habit check-ins and streaks — goes through
 * these helpers with the user's IANA zone.
 *
 * All functions are pure and DST-safe: offsets are computed for the instant in
 * question, never assumed constant.
 */
import { addDaysToKey } from './time';

const formatters = new Map<string, Intl.DateTimeFormat>();

function partsFormatter(timeZone: string): Intl.DateTimeFormat {
  let f = formatters.get(timeZone);
  if (!f) {
    f = new Intl.DateTimeFormat('en-US', {
      timeZone,
      hourCycle: 'h23',
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
    });
    formatters.set(timeZone, f);
  }
  return f;
}

/** True when `timeZone` is a zone the runtime knows (IANA name or 'UTC'). */
export function isValidTimeZone(timeZone: string): boolean {
  if (!timeZone || typeof timeZone !== 'string') return false;
  try {
    new Intl.DateTimeFormat('en-US', { timeZone }).format(0);
    return true;
  } catch {
    return false;
  }
}

/** Wall-clock components of `instant` in `timeZone`. */
function wallClock(instant: Date, timeZone: string) {
  const values: Record<string, number> = {};
  for (const part of partsFormatter(timeZone).formatToParts(instant)) {
    if (part.type !== 'literal') values[part.type] = Number(part.value);
  }
  return {
    year: values.year,
    month: values.month,
    day: values.day,
    hour: values.hour === 24 ? 0 : values.hour,
    minute: values.minute,
    second: values.second,
  };
}

/** Offset (ms) of `timeZone` from UTC at `instant` (e.g. -6h for CDMX). */
export function zoneOffsetMs(instant: Date, timeZone: string): number {
  const w = wallClock(instant, timeZone);
  const asUtc = Date.UTC(
    w.year,
    w.month - 1,
    w.day,
    w.hour,
    w.minute,
    w.second,
  );
  const truncated = instant.getTime() - instant.getUTCMilliseconds();
  return asUtc - truncated;
}

/** Calendar day (YYYY-MM-DD) of `instant` as seen in `timeZone`. */
export function localDateKey(instant: Date, timeZone: string): string {
  const w = wallClock(instant, timeZone);
  return `${w.year}-${String(w.month).padStart(2, '0')}-${String(w.day).padStart(2, '0')}`;
}

/** The instant at which local day `key` starts in `timeZone` (DST-safe). */
export function startOfLocalDayKey(key: string, timeZone: string): Date {
  const [y, m, d] = key.split('-').map(Number);
  const wallMidnight = Date.UTC(y, m - 1, d);
  // Two passes: the offset at the guessed instant may differ across a DST jump.
  let guess = wallMidnight - zoneOffsetMs(new Date(wallMidnight), timeZone);
  guess = wallMidnight - zoneOffsetMs(new Date(guess), timeZone);
  return new Date(guess);
}

/** Window of the user's current local day: [start, end). */
export interface LocalDay {
  key: string;
  start: Date;
  end: Date;
}

export function localDay(instant: Date, timeZone: string): LocalDay {
  const key = localDateKey(instant, timeZone);
  return {
    key,
    start: startOfLocalDayKey(key, timeZone),
    end: startOfLocalDayKey(addDaysToKey(key, 1), timeZone),
  };
}

/** ISO-4217 codes the runtime knows (Intl), cached. */
let currencies: Set<string> | null = null;

export function isValidCurrency(code: string): boolean {
  if (!/^[A-Z]{3}$/.test(code ?? '')) return false;
  if (!currencies) {
    const intl = Intl as unknown as {
      supportedValuesOf?: (key: string) => string[];
    };
    currencies = new Set(intl.supportedValuesOf?.('currency') ?? []);
  }
  return currencies.size === 0 || currencies.has(code);
}
