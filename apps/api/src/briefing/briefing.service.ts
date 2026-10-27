import { Injectable } from '@nestjs/common';
import { normalizeName } from '../common/time';
import { localDay } from '../common/tz';
import { PrismaRlsService } from '../prisma/prisma-rls.service';
import { UserSettingsService } from '../users/user-settings.service';
import {
  compareTasks,
  TaskResponse,
  toTaskResponse,
} from '../tasks/tasks.mapper';
import {
  BriefingPerson,
  BriefingResponse,
  toBriefingEvent,
} from './briefing.mapper';

const TASK_PREVIEW = 5;
const EVENT_PREVIEW = 5;
const PEOPLE_PREVIEW = 3;
const DAY_MS = 24 * 60 * 60 * 1000;

/** Window of "today" used to classify due dates and upcoming events. */
export interface DayWindow {
  /** Instant at which the user's current day started. */
  start: Date;
  /** Instant at which the user's current day ends (exclusive). */
  end: Date;
}

/** UTC day window (fallback when the user's timezone is unknown). */
export function utcDayWindow(now: Date): DayWindow {
  const start = new Date(
    Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()),
  );
  return { start, end: new Date(start.getTime() + DAY_MS) };
}

/**
 * Pure classification of pending tasks against "now" and today's window:
 * overdue = due before now; due today = due between now and end of today.
 */
export function classifyPending(
  pending: TaskResponse[],
  now: Date,
  day: DayWindow,
): { overdue: number; dueToday: number } {
  let overdue = 0;
  let dueToday = 0;
  for (const t of pending) {
    if (!t.due_at) continue;
    const due = new Date(t.due_at).getTime();
    if (Number.isNaN(due)) continue;
    if (due < now.getTime()) overdue += 1;
    else if (due < day.end.getTime()) dueToday += 1;
  }
  return { overdue, dueToday };
}

/**
 * Builds the Daily Briefing from the user's graph. Every read runs inside
 * `PrismaRlsService.withUser`, so RLS guarantees only the caller's own
 * knowledge is used.
 */
@Injectable()
export class BriefingService {
  constructor(
    private readonly rls: PrismaRlsService,
    private readonly settings: UserSettingsService,
  ) {}

  /** Build the briefing with "today" in the user's own timezone (D-013). */
  async build(
    userId: string,
    now: Date = new Date(),
  ): Promise<BriefingResponse> {
    const { timezone } = await this.settings.get(userId);
    const day: DayWindow = localDay(now, timezone);
    return this.rls.withUser(userId, async (tx) => {
      const [taskRows, events] = await Promise.all([
        tx.node.findMany({
          where: { userId, type: 'task', deletedAt: null },
          select: {
            id: true,
            title: true,
            attributes: true,
            origin: true,
            createdAt: true,
          },
        }),
        tx.node.findMany({
          where: {
            userId,
            type: 'event',
            deletedAt: null,
            occurredAt: { gte: day.start },
          },
          orderBy: [{ occurredAt: 'asc' }],
          take: EVENT_PREVIEW,
          select: { id: true, title: true, occurredAt: true },
        }),
      ]);

      const pending = taskRows
        .map(toTaskResponse)
        .filter((t) => !t.done)
        .sort(compareTasks);
      const { overdue, dueToday } = classifyPending(pending, now, day);

      // Who is waiting on the user: persons linked to pending tasks.
      let people: BriefingPerson[] = [];
      if (pending.length > 0) {
        const edges = await tx.edge.findMany({
          where: {
            userId,
            type: 'assigned_to',
            deletedAt: null,
            sourceNodeId: { in: pending.map((t) => t.id) },
          },
          select: { sourceNodeId: true, targetNodeId: true },
        });
        if (edges.length > 0) {
          const persons = await tx.node.findMany({
            where: {
              userId,
              type: 'person',
              deletedAt: null,
              id: { in: [...new Set(edges.map((e) => e.targetNodeId))] },
            },
            select: { id: true, title: true },
          });
          people = groupPeople(edges, persons);
        }
      }

      return {
        generated_at: now.toISOString(),
        task_total: pending.length,
        overdue_count: overdue,
        due_today_count: dueToday,
        tasks: pending.slice(0, TASK_PREVIEW).map((t) => ({
          id: t.id,
          title: t.title,
          priority: t.priority,
          due_at: t.due_at,
        })),
        upcoming_events: events.map(toBriefingEvent),
        people,
      };
    });
  }
}

/**
 * Group person nodes by normalised name (the same person is extracted once per
 * capture) and count the DISTINCT pending tasks linked to each.
 */
export function groupPeople(
  edges: { sourceNodeId: string; targetNodeId: string }[],
  persons: { id: string; title: string | null }[],
): BriefingPerson[] {
  const byId = new Map(persons.map((p) => [p.id, p]));
  const groups = new Map<string, { name: string; tasks: Set<string> }>();
  for (const edge of edges) {
    const person = byId.get(edge.targetNodeId);
    const title = person?.title?.trim();
    if (!title) continue;
    const key = normalizeName(title);
    const group = groups.get(key) ?? { name: title, tasks: new Set<string>() };
    group.tasks.add(edge.sourceNodeId);
    groups.set(key, group);
  }
  return [...groups.values()]
    .map((g) => ({ name: g.name, pending_count: g.tasks.size }))
    .sort(
      (a, b) =>
        b.pending_count - a.pending_count || a.name.localeCompare(b.name),
    )
    .slice(0, PEOPLE_PREVIEW);
}
