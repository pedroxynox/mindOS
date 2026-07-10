import { Prisma } from '@prisma/client';
import { PrismaRlsService } from '../prisma/prisma-rls.service';
import { BriefingService } from './briefing.service';

/**
 * Unit tests for BriefingService: reads run through PrismaRlsService.withUser
 * (RLS boundary), only future events are requested (occurredAt >= start of
 * today), and the response shape aggregates task total + previews + upcoming
 * events. The Prisma client is a lightweight double (no DB).
 */
const USER_ID = '11111111-1111-1111-1111-111111111111';

function buildService(tx: {
  node: { count?: jest.Mock; findMany?: jest.Mock };
}): { service: BriefingService; withUser: jest.Mock } {
  const withUser = jest.fn(
    async <T>(
      _userId: string,
      work: (t: Prisma.TransactionClient) => Promise<T>,
    ): Promise<T> => work(tx as unknown as Prisma.TransactionClient),
  );
  const rls = { withUser } as unknown as PrismaRlsService;
  return { service: new BriefingService(rls), withUser };
}

describe('BriefingService.build', () => {
  it('aggregates task total, task previews and upcoming events', async () => {
    const count = jest.fn().mockResolvedValue(4);
    const findMany = jest
      .fn()
      // tasks preview
      .mockResolvedValueOnce([{ id: 't1', title: 'Call Marcos' }])
      // upcoming events
      .mockResolvedValueOnce([
        {
          id: 'e1',
          title: 'Kickoff',
          occurredAt: new Date('2026-07-15T09:00:00.000Z'),
        },
      ]);
    const { service, withUser } = buildService({ node: { count, findMany } });

    const result = await service.build(USER_ID);

    expect(withUser).toHaveBeenCalledWith(USER_ID, expect.any(Function));
    expect(result.task_total).toBe(4);
    expect(result.tasks).toEqual([{ id: 't1', title: 'Call Marcos' }]);
    expect(result.upcoming_events).toEqual([
      {
        id: 'e1',
        title: 'Kickoff',
        occurred_at: '2026-07-15T09:00:00.000Z',
      },
    ]);
    expect(typeof result.generated_at).toBe('string');
  });

  it('only requests events occurring today or later', async () => {
    const count = jest.fn().mockResolvedValue(0);
    const findMany = jest.fn().mockResolvedValue([]);
    const { service } = buildService({ node: { count, findMany } });

    await service.build(USER_ID);

    // The 2nd findMany call is the events query; assert its date filter.
    const eventsCall = findMany.mock.calls[1][0];
    expect(eventsCall.where.type).toBe('event');
    expect(eventsCall.where.occurredAt.gte).toBeInstanceOf(Date);
    expect(eventsCall.orderBy).toEqual([{ occurredAt: 'asc' }]);
  });

  it('returns empty sections when the user has no knowledge yet', async () => {
    const count = jest.fn().mockResolvedValue(0);
    const findMany = jest.fn().mockResolvedValue([]);
    const { service } = buildService({ node: { count, findMany } });

    const result = await service.build(USER_ID);

    expect(result.task_total).toBe(0);
    expect(result.tasks).toEqual([]);
    expect(result.upcoming_events).toEqual([]);
  });
});
