import { BadRequestException, NotFoundException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaRlsService } from '../prisma/prisma-rls.service';
import { GraphService } from './graph.service';
import { ListNodesQueryDto } from './dto/list-nodes-query.dto';

/**
 * Unit tests for GraphService: every read runs through PrismaRlsService.withUser
 * (RLS boundary), captures are excluded from the derived-node list, list
 * pagination emits a cursor only when there is a next page, and capture entities
 * resolve provenance edges into their derived nodes. The Prisma client is a
 * lightweight double (no DB).
 */
const USER_ID = '11111111-1111-1111-1111-111111111111';
const CAPTURE_ID = '22222222-2222-2222-2222-222222222222';

type TxDouble = {
  node: {
    groupBy?: jest.Mock;
    findMany?: jest.Mock;
    findFirst?: jest.Mock;
  };
  edge: { findMany?: jest.Mock };
};

function buildService(tx: TxDouble): {
  service: GraphService;
  withUser: jest.Mock;
} {
  const withUser = jest.fn(
    async <T>(
      _userId: string,
      work: (t: Prisma.TransactionClient) => Promise<T>,
    ): Promise<T> => work(tx as unknown as Prisma.TransactionClient),
  );
  const rls = { withUser } as unknown as PrismaRlsService;
  return { service: new GraphService(rls), withUser };
}

function node(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    id: overrides.id ?? 'n1',
    type: overrides.type ?? 'task',
    title: overrides.title ?? 'Call Marcos',
    confidence: overrides.confidence ?? 0.9,
    occurredAt: null,
    createdAt: new Date('2026-07-10T00:00:00.000Z'),
    ...overrides,
  };
}

describe('GraphService.summary', () => {
  it('counts derived nodes per type and totals them', async () => {
    const groupBy = jest.fn().mockResolvedValue([
      { type: 'task', _count: { _all: 3 } },
      { type: 'person', _count: { _all: 2 } },
    ]);
    const { service, withUser } = buildService({ node: { groupBy }, edge: {} });

    const result = await service.summary(USER_ID);

    expect(withUser).toHaveBeenCalledWith(USER_ID, expect.any(Function));
    expect(result).toEqual({ counts: { task: 3, person: 2 }, total: 5 });
    // Captures must be excluded from the derived-knowledge summary.
    expect(groupBy).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({ type: { not: 'capture' } }),
      }),
    );
  });
});

describe('GraphService.listNodes', () => {
  it('rejects listing captures via the graph API', async () => {
    const { service } = buildService({ node: {}, edge: {} });
    const query = Object.assign(new ListNodesQueryDto(), { type: 'capture' });

    await expect(service.listNodes(USER_ID, query)).rejects.toBeInstanceOf(
      BadRequestException,
    );
  });

  it('returns a page with no cursor when results fit in the limit', async () => {
    const findMany = jest.fn().mockResolvedValue([node({ id: 'a' })]);
    const { service } = buildService({ node: { findMany }, edge: {} });
    const query = Object.assign(new ListNodesQueryDto(), {
      type: 'task',
      limit: 20,
    });

    const page = await service.listNodes(USER_ID, query);

    expect(page.next_cursor).toBeNull();
    expect(page.data).toHaveLength(1);
    expect(page.data[0]).toMatchObject({ id: 'a', type: 'task' });
  });

  it('emits a cursor when there is an extra row beyond the limit', async () => {
    const findMany = jest
      .fn()
      .mockResolvedValue([node({ id: 'a' }), node({ id: 'b' })]);
    const { service } = buildService({ node: { findMany }, edge: {} });
    const query = Object.assign(new ListNodesQueryDto(), {
      type: 'task',
      limit: 1,
    });

    const page = await service.listNodes(USER_ID, query);

    expect(page.data).toHaveLength(1);
    expect(page.next_cursor).toBe('b');
  });
});

describe('GraphService.captureEntities', () => {
  it('throws NotFound when the capture is not the caller\'s', async () => {
    const findFirst = jest.fn().mockResolvedValue(null);
    const { service } = buildService({ node: { findFirst }, edge: {} });

    await expect(
      service.captureEntities(USER_ID, CAPTURE_ID),
    ).rejects.toBeInstanceOf(NotFoundException);
  });

  it('returns extracted nodes and semantic edges for a capture', async () => {
    const findFirst = jest
      .fn()
      .mockResolvedValue({ id: CAPTURE_ID, status: 'processed' });
    const findMany = jest
      .fn()
      .mockResolvedValue([node({ id: 'task-1', type: 'task' }), node({ id: 'p-1', type: 'person', title: 'Marcos' })]);
    const edgeFindMany = jest
      .fn()
      // 1st call: provenance edges (derived_from) -> source node ids.
      .mockResolvedValueOnce([
        { sourceNodeId: 'task-1' },
        { sourceNodeId: 'p-1' },
      ])
      // 2nd call: semantic edges among those nodes.
      .mockResolvedValueOnce([
        {
          sourceNodeId: 'task-1',
          targetNodeId: 'p-1',
          type: 'assigned_to',
          confidence: 0.8,
        },
      ]);
    const { service } = buildService({
      node: { findFirst, findMany },
      edge: { findMany: edgeFindMany },
    });

    const result = await service.captureEntities(USER_ID, CAPTURE_ID);

    expect(result.status).toBe('processed');
    expect(result.nodes).toHaveLength(2);
    expect(result.edges).toEqual([
      { source: 'task-1', target: 'p-1', type: 'assigned_to', confidence: 0.8 },
    ]);
  });

  it('returns empty entities when nothing was extracted yet', async () => {
    const findFirst = jest
      .fn()
      .mockResolvedValue({ id: CAPTURE_ID, status: 'processing' });
    const edgeFindMany = jest.fn().mockResolvedValueOnce([]);
    const { service } = buildService({
      node: { findFirst },
      edge: { findMany: edgeFindMany },
    });

    const result = await service.captureEntities(USER_ID, CAPTURE_ID);

    expect(result.status).toBe('processing');
    expect(result.nodes).toEqual([]);
    expect(result.edges).toEqual([]);
  });
});
