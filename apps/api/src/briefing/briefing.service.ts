import { Injectable } from '@nestjs/common';
import { PrismaRlsService } from '../prisma/prisma-rls.service';
import {
  BriefingResponse,
  toBriefingEvent,
  toBriefingItem,
} from './briefing.mapper';

/** How many preview items to include per section. */
const TASK_PREVIEW = 5;
const EVENT_PREVIEW = 5;

/**
 * Builds the Daily Briefing: a proactive summary of the user's tasks and
 * upcoming events, derived from the knowledge graph. Read-only and RLS-scoped
 * via `PrismaRlsService.withUser`, so a user only ever sees their own data.
 *
 * "Upcoming" is computed from the start of today in UTC. Per-user timezones are
 * a future refinement (tracked for a later pass); UTC is a safe default for now.
 */
@Injectable()
export class BriefingService {
  constructor(private readonly rls: PrismaRlsService) {}

  async build(userId: string): Promise<BriefingResponse> {
    const now = new Date();
    const startOfToday = new Date(
      Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()),
    );

    return this.rls.withUser(userId, async (tx) => {
      const [taskTotal, tasks, events] = await Promise.all([
        tx.node.count({
          where: { userId, type: 'task', deletedAt: null },
        }),
        tx.node.findMany({
          where: { userId, type: 'task', deletedAt: null },
          orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
          take: TASK_PREVIEW,
          select: { id: true, title: true },
        }),
        tx.node.findMany({
          where: {
            userId,
            type: 'event',
            deletedAt: null,
            occurredAt: { gte: startOfToday },
          },
          orderBy: [{ occurredAt: 'asc' }],
          take: EVENT_PREVIEW,
          select: { id: true, title: true, occurredAt: true },
        }),
      ]);

      return {
        generated_at: now.toISOString(),
        task_total: taskTotal,
        tasks: tasks.map(toBriefingItem),
        upcoming_events: events.map(toBriefingEvent),
      };
    });
  }
}
