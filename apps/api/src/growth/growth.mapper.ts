import { Node } from '@prisma/client';
import { addDaysToKey, isoWeekKey, utcDateKey } from '../common/time';
import { HabitCadence } from './dto/growth.dto';

/**
 * Personal-development items (Growth). To avoid a schema migration they are
 * stored as `node` rows of type `note` with `origin = 'manual_text'` and an
 * `attributes.kind` discriminator ('goal' | 'habit' | 'reflection'); type-
 * specific data lives in `attributes` (ADR-020). RLS on `nodes` protects them
 * like everything else. Wire shapes are snake_case (#04).
 */
export type GrowthKind = 'goal' | 'habit' | 'reflection';

export interface GoalResponse {
  id: string;
  title: string | null;
  progress: number; // 0..100
  /** Derived: a goal is achieved exactly when progress reaches 100. */
  done: boolean;
  target_date: string | null;
  area: string | null;
  created_at: string;
}

export interface HabitResponse {
  id: string;
  title: string | null;
  cadence: HabitCadence;
  /** Consecutive periods completed (days for daily, ISO weeks for weekly). */
  streak: number;
  /** Unit of `streak`, so the client can render "3 días" vs "3 semanas". */
  streak_unit: 'day' | 'week';
  /** Whether today is checked (the toggle always acts on today). */
  done_today: boolean;
  /** Whether the current period is satisfied (today / this ISO week). */
  period_done: boolean;
  area: string | null;
  created_at: string;
}

export interface ReflectionResponse {
  id: string;
  body: string | null;
  mood: string | null;
  created_at: string;
}

/** Date key (YYYY-MM-DD) used for habit logs. UTC unless a zone is applied. */
export function dateKey(d: Date): string {
  return utcDateKey(d);
}

/**
 * Current daily streak: consecutive days completed ending today (or yesterday,
 * so a streak isn't considered broken until a full day is missed).
 */
export function computeStreak(dates: string[], todayKey: string): number {
  const set = new Set(dates);
  let cursor = todayKey;
  if (!set.has(cursor)) {
    cursor = addDaysToKey(cursor, -1);
    if (!set.has(cursor)) return 0;
  }
  let streak = 0;
  while (set.has(cursor)) {
    streak += 1;
    cursor = addDaysToKey(cursor, -1);
  }
  return streak;
}

/**
 * Current weekly streak: consecutive ISO weeks with at least one check, ending
 * this week (or last week — the current week is still in progress).
 */
export function computeWeeklyStreak(dates: string[], todayKey: string): number {
  const weeks = new Set(dates.map(isoWeekKey));
  let cursorDay = todayKey;
  if (!weeks.has(isoWeekKey(cursorDay))) {
    cursorDay = addDaysToKey(cursorDay, -7);
    if (!weeks.has(isoWeekKey(cursorDay))) return 0;
  }
  let streak = 0;
  while (weeks.has(isoWeekKey(cursorDay))) {
    streak += 1;
    cursorDay = addDaysToKey(cursorDay, -7);
  }
  return streak;
}

function num(value: unknown, fallback: number): number {
  return typeof value === 'number' && Number.isFinite(value) ? value : fallback;
}

function str(value: unknown): string | null {
  return typeof value === 'string' && value.length > 0 ? value : null;
}

type Attrs = Record<string, unknown>;

export function readLog(attributes: unknown): string[] {
  const a = (attributes ?? {}) as Attrs;
  return Array.isArray(a.log)
    ? (a.log as unknown[]).filter((x): x is string => typeof x === 'string')
    : [];
}

export function toGoalResponse(
  node: Pick<Node, 'id' | 'title' | 'attributes' | 'createdAt'>,
): GoalResponse {
  const a = (node.attributes ?? {}) as Attrs;
  const progress = Math.max(0, Math.min(100, Math.round(num(a.progress, 0))));
  return {
    id: node.id,
    title: node.title,
    progress,
    done: progress >= 100,
    target_date: str(a.target_date),
    area: str(a.area),
    created_at: node.createdAt.toISOString(),
  };
}

/**
 * @param todayKey the user's current calendar day (YYYY-MM-DD). Defaults to the
 *   UTC day; callers pass the user's local day once timezones are known.
 */
export function toHabitResponse(
  node: Pick<Node, 'id' | 'title' | 'attributes' | 'createdAt'>,
  todayKey: string = utcDateKey(new Date()),
): HabitResponse {
  const a = (node.attributes ?? {}) as Attrs;
  const log = readLog(node.attributes);
  const cadence: HabitCadence = a.cadence === 'weekly' ? 'weekly' : 'daily';
  const doneToday = log.includes(todayKey);
  const thisWeek = isoWeekKey(todayKey);
  return {
    id: node.id,
    title: node.title,
    cadence,
    streak:
      cadence === 'weekly'
        ? computeWeeklyStreak(log, todayKey)
        : computeStreak(log, todayKey),
    streak_unit: cadence === 'weekly' ? 'week' : 'day',
    done_today: doneToday,
    period_done:
      cadence === 'weekly'
        ? log.some((d) => isoWeekKey(d) === thisWeek)
        : doneToday,
    area: str(a.area),
    created_at: node.createdAt.toISOString(),
  };
}

export function toReflectionResponse(
  node: Pick<Node, 'id' | 'body' | 'attributes' | 'createdAt'>,
): ReflectionResponse {
  const a = (node.attributes ?? {}) as Attrs;
  return {
    id: node.id,
    body: node.body,
    mood: str(a.mood),
    created_at: node.createdAt.toISOString(),
  };
}
