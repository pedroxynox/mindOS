import { Prisma } from '@prisma/client';
import { PrismaRlsService } from '../prisma/prisma-rls.service';
import {
  BriefingService,
  classifyPending,
  groupPeople,
  utcDayWindow,
} from './briefing.service';
import { TaskResponse } from '../tasks/tasks.mapper';

/**
 * Unit tests for BriefingService: reads run through PrismaRlsService.withUser
 * (RLS boundary); only PENDING tasks count and are previewed in priority order;
 * overdue / due-today are classified against "now"; people with pending
 * `assigned_to` tasks are grouped by normalised name; only future events are
 * requested. Prisma is a lightweight double (no DB).
 */
const USER_ID = '11111111-1111-1111-1111-111111111111';
const NOW = new Date('2026-07-10T15:00:00.000Z');

function taskRow(id: string, attributes: Record<string, unknown>) {
  return {
    id,
    title: `task ${id}`,
    attributes,
    origin: 'ai',
    createdAt: new Date('2026-07-01T00:00:00.000Z'),
  };
}

function buildService(tx: {
  node: { findMany: jest.Mock };
  edge?: { findMany: jest.Mock };
}): { service: BriefingService; withUser: jest.Mock } {
  const withUser = jest.fn(
    async <T>(
      _userId: string,
      work: (t: Prisma.TransactionClient) => Promise<T>,
    ): Promise<T> => work(tx as unknown as Prisma.TransactionClient),
  );
  return {
    service: new BriefingService({ withUser } as unknown as PrismaRlsService),
    withUser,
  };
}

describe('BriefingService.build', () => {
  it('counts only pending tasks and previews them in priority order', async () => {
    const findMany = jest
      .fn()
      .mockResolvedValueOnce([
        taskRow('done', { priority: 'high', done: true }),
        taskRow('low', { priority: 'low' }),
        taskRow('high', { priority: 'high' }),
      ])
      .mockResolvedValueOnce([]) // events
      .mockResolvedValueOnce([]); // persons
    const edgeFind = jest.fn().mockResolvedValue([]);
    const { service, withUser } = buildService({
      node: { findMany },
      edge: { findMany: edgeFind },
    });

    const result = await service.build(USER_ID, NOW);

    expect(withUser).toHaveBeenCalledWith(USER_ID, expect.any(Function));
    expect(result.task_total).toBe(2);
    expect(result.tasks.map((t) => t.id)).toEqual(['high', 'low']);
    expect(result.tasks[0]).toEqual({
      id: 'high',
      title: 'task high',
      priority: 'high',
      due_at: null,
    });
  });

  it('classifies overdue and due-today pending tasks', async () => {
    const findMany = jest
      .fn()
      .mockResolvedValueOnce([
        taskRow('late', { due_at: '2026-07-10T09:00:00.000Z' }),
        taskRow('tonight', { due_at: '2026-07-10T21:00:00.000Z' }),
        taskRow('tomorrow', { due_at: '2026-07-11T09:00:00.000Z' }),
      ])
      .mockResolvedValueOnce([]);
    const { service } = buildService({
      node: { findMany },
      edge: { findMany: jest.fn().mockResolvedValue([]) },
    });

    const result = await service.build(USER_ID, NOW);

    expect(result.overdue_count).toBe(1);
    expect(result.due_today_count).toBe(1);
  });

  it('lists the people the user has pending tasks with', async () => {
    const findMany = jest
      .fn()
      .mockResolvedValueOnce([taskRow('t1', {}), taskRow('t2', {})])
      .mockResolvedValueOnce([])
      .mockResolvedValueOnce([
        { id: 'p1', title: 'Marcos' },
        { id: 'p2', title: 'marcos' }, // same person, another capture
        { id: 'p3', title: 'Ana' },
      ]);
    const edgeFind = jest.fn().mockResolvedValue([
      { sourceNodeId: 't1', targetNodeId: 'p1' },
      { sourceNodeId: 't2', targetNodeId: 'p2' },
      { sourceNodeId: 't2', targetNodeId: 'p3' },
    ]);
    const { service } = buildService({
      node: { findMany },
      edge: { findMany: edgeFind },
    });

    const result = await service.build(USER_ID, NOW);

    expect(result.people).toEqual([
      { name: 'Marcos', pending_count: 2 },
      { name: 'Ana', pending_count: 1 },
    ]);
    // Only assigned_to edges from PENDING tasks are read.
    const where = edgeFind.mock.calls[0][0].where;
    expect(where.type).toBe('assigned_to');
    expect([...where.sourceNodeId.in].sort()).toEqual(['t1', 't2']);
  });

  it('only requests events occurring from the start of today', async () => {
    const findMany = jest.fn().mockResolvedValue([]);
    const { service } = buildService({ node: { findMany } });

    await service.build(USER_ID, NOW);

    const eventsCall = findMany.mock.calls[1][0];
    expect(eventsCall.where.type).toBe('event');
    expect(eventsCall.where.occurredAt.gte).toEqual(
      new Date('2026-07-10T00:00:00.000Z'),
    );
    expect(eventsCall.orderBy).toEqual([{ occurredAt: 'asc' }]);
  });

  it('returns empty sections when the user has no knowledge yet', async () => {
    const findMany = jest.fn().mockResolvedValue([]);
    const { service } = buildService({ node: { findMany } });

    const result = await service.build(USER_ID, NOW);

    expect(result).toMatchObject({
      task_total: 0,
      overdue_count: 0,
      due_today_count: 0,
      tasks: [],
      upcoming_events: [],
      people: [],
    });
  });
});

describe('briefing helpers', () => {
  it('classifyPending ignores tasks without a valid due date', () => {
    const pending = [
      { id: 'a', due_at: null },
      { id: 'b', due_at: 'not-a-date' },
    ] as unknown as TaskResponse[];
    expect(classifyPending(pending, NOW, utcDayWindow(NOW))).toEqual({
      overdue: 0,
      dueToday: 0,
    });
  });

  it('groupPeople skips persons without a title and caps the list', () => {
    const edges = ['p1', 'p2', 'p3', 'p4', 'p5'].map((p, i) => ({
      sourceNodeId: `t${i}`,
      targetNodeId: p,
    }));
    const persons = [
      { id: 'p1', title: 'Ana' },
      { id: 'p2', title: null },
      { id: 'p3', title: 'Bea' },
      { id: 'p4', title: 'Caro' },
      { id: 'p5', title: 'Dani' },
    ];
    const people = groupPeople(edges, persons);
    expect(people).toHaveLength(3);
    expect(people.map((p) => p.name)).toEqual(['Ana', 'Bea', 'Caro']);
  });
});
