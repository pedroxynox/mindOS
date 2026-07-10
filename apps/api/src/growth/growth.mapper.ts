import { Node } from '@prisma/client';
import { HabitCadence } from './dto/growth.dto';

/**
 * Personal-development items (Growth). To avoid a schema migration they are
 * stored as `node` rows of type `note` with `origin = 'manual_text'` and an
 * `attributes.kind` discriminator ('goal' | 'habit' | 'reflection'); type-
 * specific data lives in `attributes`. RLS on `nodes` protects them like
 * everything else. Wire shapes are snake_case (#04).
 */
export type GrowthKind = 'goal' | 'habit' | 'reflection';

export interface GoalResponse {
  id: string;
  title: string | null;
  progress: number; // 0..100
  done: boolean;
  target_date: string | null;
  area: string | null;
  created_at: string;
}

export interface HabitResponse {
  id: string;
  title: string | null;
  cadence: HabitCadence;
  streak: number;
  done_today: boolean;
  area: string | null;
  created_at: string;
}

export interface ReflectionResponse {
  id: string;
  body: string | null;
  mood: string | null;
  created_at: string;
}

/** UTC date key (YYYY-MM-DD) used for habit logs. */
export function dateKey(d: Date): string {
  return d.toISOString().slice(0, 10);
}

/**
 * Current daily streak: consecutive days completed ending today (or yesterday,
 * so a streak isn't considered broken until a full day is missed).
 */
export function computeStreak(dates: string[], today: Date = new Date()): number {
  const set = new Set(dates);
  const cursor = new Date(
    Date.UTC(today.getUTCFullYear(), today.getUTCMonth(), today.getUTCDate()),
  );
  if (!set.has(dateKey(cursor))) {
    cursor.setUTCDate(cursor.getUTCDate() - 1);
    if (!set.has(dateKey(cursor))) return 0;
  }
  let streak = 0;
  while (set.has(dateKey(cursor))) {
    streak += 1;
    cursor.setUTCDate(cursor.getUTCDate() - 1);
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

export function toGoalResponse(
  node: Pick<Node, 'id' | 'title' | 'attributes' | 'createdAt'>,
): GoalResponse {
  const a = (node.attributes ?? {}) as Attrs;
  const progress = Math.max(0, Math.min(100, num(a.progress, 0)));
  return {
    id: node.id,
    title: node.title,
    progress,
    done: a.done === true || progress >= 100,
    target_date: str(a.target_date),
    area: str(a.area),
    created_at: node.createdAt.toISOString(),
  };
}

export function toHabitResponse(
  node: Pick<Node, 'id' | 'title' | 'attributes' | 'createdAt'>,
  today: Date = new Date(),
): HabitResponse {
  const a = (node.attributes ?? {}) as Attrs;
  const log = Array.isArray(a.log) ? (a.log as unknown[]).filter((x): x is string => typeof x === 'string') : [];
  const cadence: HabitCadence = a.cadence === 'weekly' ? 'weekly' : 'daily';
  return {
    id: node.id,
    title: node.title,
    cadence,
    streak: computeStreak(log, today),
    done_today: log.includes(dateKey(today)),
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
