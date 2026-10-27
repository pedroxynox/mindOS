import { BadRequestException, NotFoundException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaRlsService } from '../prisma/prisma-rls.service';
import { GraphService } from './graph.service';
import { ListNodesQueryDto } from './dto/list-nodes-query.dto';

/**
 * Unit tests for GraphService: every query runs through
 * PrismaRlsService.withUser (RLS boundary); people/projects/... are grouped by
 * normalised name while tasks stay one by one; the entity screen gathers
 * captures, related entities and tasks; corrections (rename, remove, review a
 * connection) are scoped to one mention or the whole entity. The Prisma client
 * is a lightweight double (no DB) — the real SQL runs in the integration suite.
 */
const USER_ID = '11111111-1111-1111-1111-111111111111';
const CAPTURE_ID = '22222222-2222-2222-2222-222222222222';

type TxDouble = {
  node: {
    groupBy?: jest.Mock;
    findMany?: jest.Mock;
    findFirst?: jest.Mock;
    updateMany?: jest.Mock;
  };
  edge: {
    findMany?: jest.Mock;
    findFirst?: jest.Mock;
    update?: jest.Mock;
    updateMany?: jest.Mock;
  };
  $executeRaw?: jest.Mock;
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

function node(
  overrides: Record<string, unknown> = {},
): Record<string, unknown> {
  return {
    id: 'n1',
    type: 'task',
    title: 'Call Marcos',
    confidence: 0.9,
    occurredAt: null,
    createdAt: new Date('2026-07-10T00:00:00.000Z'),
    attributes: {},
    origin: 'ai',
    ...overrides,
  };
}

function edge(
  overrides: Record<string, unknown> = {},
): Record<string, unknown> {
  return {
    id: 'e1',
    sourceNodeId: 'task-1',
    targetNodeId: 'p-1',
    type: 'assigned_to',
    confidence: 0.8,
    userConfirmed: false,
    ...overrides,
  };
}

function listQuery(type: string, extra: Record<string, unknown> = {}) {
  return Object.assign(new ListNodesQueryDto(), { type, limit: 20, ...extra });
}

describe('GraphService.summary', () => {
  it('counts distinct entities per type and tasks one by one', async () => {
    const findMany = jest
      .fn()
      .mockResolvedValue([
        node({ id: 't1', type: 'task', title: 'Pagar luz' }),
        node({ id: 't2', type: 'task', title: 'Pagar luz' }),
        node({ id: 'p1', type: 'person', title: 'Marcos' }),
        node({ id: 'p2', type: 'person', title: 'marcos.' }),
        node({ id: 'p3', type: 'person', title: 'Ana' }),
      ]);
    const { service, withUser } = buildService({
      node: { findMany },
      edge: {},
    });

    const result = await service.summary(USER_ID);

    expect(withUser).toHaveBeenCalledWith(USER_ID, expect.any(Function));
    expect(result).toEqual({ counts: { task: 2, person: 2 }, total: 4 });
    // Captures and notes (incl. Growth items) are excluded from the overview.
    expect(findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({
          deletedAt: null,
          type: { notIn: ['capture', 'note'] },
        }),
      }),
    );
  });
});

describe('GraphService.listNodes', () => {
  it('rejects listing captures via the graph API', async () => {
    const { service } = buildService({ node: {}, edge: {} });
    await expect(
      service.listNodes(USER_ID, listQuery('capture')),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('lists tasks one by one with an id cursor', async () => {
    const findMany = jest
      .fn()
      .mockResolvedValue([node({ id: 'a' }), node({ id: 'b' })]);
    const { service } = buildService({ node: { findMany }, edge: {} });

    const page = await service.listNodes(
      USER_ID,
      listQuery('task', { limit: 1 }),
    );

    expect(page.data).toEqual([
      expect.objectContaining({ id: 'a', type: 'task', mentions: 1 }),
    ]);
    expect(page.next_cursor).toBe('b');
  });

  it('groups people by name with an offset cursor', async () => {
    const findMany = jest.fn().mockResolvedValue([
      node({
        id: 'm1',
        type: 'person',
        title: 'Marcos',
        createdAt: new Date('2026-10-01'),
      }),
      node({
        id: 'a1',
        type: 'person',
        title: 'Ana',
        createdAt: new Date('2026-10-02'),
      }),
      node({
        id: 'm2',
        type: 'person',
        title: 'MARCOS',
        createdAt: new Date('2026-10-03'),
      }),
    ]);
    const { service } = buildService({ node: { findMany }, edge: {} });

    const first = await service.listNodes(
      USER_ID,
      listQuery('person', { limit: 1 }),
    );
    expect(first.data).toEqual([
      expect.objectContaining({ id: 'm2', title: 'MARCOS', mentions: 2 }),
    ]);
    expect(first.next_cursor).toBe('1');

    const second = await service.listNodes(
      USER_ID,
      listQuery('person', { limit: 1, cursor: '1' }),
    );
    expect(second.data).toEqual([
      expect.objectContaining({ id: 'a1', title: 'Ana', mentions: 1 }),
    ]);
    expect(second.next_cursor).toBeNull();
  });

  it('rejects a malformed offset cursor', async () => {
    const { service } = buildService({
      node: { findMany: jest.fn() },
      edge: {},
    });
    await expect(
      service.listNodes(USER_ID, listQuery('person', { cursor: 'abc' })),
    ).rejects.toBeInstanceOf(BadRequestException);
  });
});

describe('GraphService.entity', () => {
  it('gathers mentions, captures, related entities and tasks', async () => {
    const marcos1 = node({
      id: 'm1',
      type: 'person',
      title: 'Marcos',
      createdAt: new Date('2026-10-01'),
    });
    const marcos2 = node({
      id: 'm2',
      type: 'person',
      title: 'marcos',
      createdAt: new Date('2026-10-03'),
      attributes: { user_edited: true },
    });
    const nodeFindFirst = jest.fn().mockResolvedValue(marcos1);
    const nodeFindMany = jest
      .fn()
      // same-type candidates
      .mockResolvedValueOnce([
        marcos1,
        marcos2,
        node({ id: 'a1', type: 'person', title: 'Ana' }),
      ])
      // captures
      .mockResolvedValueOnce([
        {
          id: 'c2',
          body: 'Llamar a Marcos por Aurora',
          origin: 'voice',
          occurredAt: null,
          createdAt: new Date('2026-10-03'),
        },
        {
          id: 'c1',
          body: 'Marcos y Ana',
          origin: 'manual_text',
          occurredAt: null,
          createdAt: new Date('2026-10-01'),
        },
      ])
      // neighbours
      .mockResolvedValueOnce([
        node({ id: 'proj1', type: 'project', title: 'Aurora' }),
        node({ id: 'proj2', type: 'project', title: 'aurora' }),
        node({ id: 'a1', type: 'person', title: 'Ana' }),
        node({
          id: 't1',
          type: 'task',
          title: 'Llamar a Marcos',
          attributes: { priority: 'high' },
        }),
        node({
          id: 't2',
          type: 'task',
          title: 'Enviar acta',
          attributes: { done: true },
        }),
      ]);
    const edgeFindMany = jest
      .fn()
      // provenance of the mentions
      .mockResolvedValueOnce([{ targetNodeId: 'c1' }, { targetNodeId: 'c2' }])
      // co-occurring nodes
      .mockResolvedValueOnce([
        { sourceNodeId: 'proj1' },
        { sourceNodeId: 'proj2' },
        { sourceNodeId: 'a1' },
        { sourceNodeId: 't2' },
      ])
      // direct links
      .mockResolvedValueOnce([{ sourceNodeId: 't1', targetNodeId: 'm2' }]);
    const { service } = buildService({
      node: { findFirst: nodeFindFirst, findMany: nodeFindMany },
      edge: { findMany: edgeFindMany },
    });

    const result = await service.entity(USER_ID, 'm1');

    expect(result).toMatchObject({
      id: 'm1',
      type: 'person',
      title: 'marcos',
      mentions: 2,
      node_ids: ['m2', 'm1'],
      user_edited: true,
    });
    expect(result.captures.map((c) => [c.id, c.modality])).toEqual([
      ['c2', 'voice'],
      ['c1', 'text'],
    ]);
    expect(result.related).toEqual([
      { id: 'proj2', type: 'project', title: 'aurora', mentions: 2 },
      { id: 'a1', type: 'person', title: 'Ana', mentions: 1 },
    ]);
    // Pending first, then done.
    expect(result.tasks.map((t) => [t.id, t.done])).toEqual([
      ['t1', false],
      ['t2', true],
    ]);
    // Neighbours never include captures or the entity itself.
    const neighbourWhere = nodeFindMany.mock.calls[2][0].where;
    expect(neighbourWhere.type).toEqual({ not: 'capture' });
    expect(neighbourWhere.id.in).not.toContain('m1');
    expect(neighbourWhere.id.in).not.toContain('m2');
  });

  it('404s for an unknown node and 400s for a capture', async () => {
    const findFirst = jest
      .fn()
      .mockResolvedValueOnce(null)
      .mockResolvedValueOnce(node({ id: CAPTURE_ID, type: 'capture' }));
    const { service } = buildService({ node: { findFirst }, edge: {} });

    await expect(service.entity(USER_ID, 'x')).rejects.toBeInstanceOf(
      NotFoundException,
    );
    await expect(service.entity(USER_ID, CAPTURE_ID)).rejects.toBeInstanceOf(
      BadRequestException,
    );
  });
});

describe('GraphService corrections', () => {
  const marcos = node({ id: 'm1', type: 'person', title: 'Marcos' });
  const candidates = [
    marcos,
    node({ id: 'm2', type: 'person', title: 'MARCOS' }),
    node({ id: 'a1', type: 'person', title: 'Ana' }),
  ];

  it('renames one mention by default and flags it user_edited', async () => {
    const findFirst = jest.fn().mockResolvedValue(marcos);
    const findMany = jest.fn();
    const executeRaw = jest.fn().mockResolvedValue(1);
    const { service } = buildService({
      node: { findFirst, findMany },
      edge: {},
      $executeRaw: executeRaw,
    });

    const result = await service.rename(USER_ID, 'm1', 'Marcos Pérez', 'node');

    expect(result).toMatchObject({
      id: 'm1',
      title: 'Marcos Pérez',
      updated: 1,
    });
    expect(findMany).not.toHaveBeenCalled();
    const [sql, ...values] = executeRaw.mock.calls[0];
    expect(sql.join('?')).toContain('user_edited');
    expect(values).toEqual(['Marcos Pérez', USER_ID, ['m1']]);
  });

  it('renames every mention with scope=entity', async () => {
    const findFirst = jest.fn().mockResolvedValue(marcos);
    const findMany = jest.fn().mockResolvedValue(candidates);
    const executeRaw = jest.fn().mockResolvedValue(2);
    const { service } = buildService({
      node: { findFirst, findMany },
      edge: {},
      $executeRaw: executeRaw,
    });

    const result = await service.rename(USER_ID, 'm1', 'Marcos', 'entity');

    expect(result.updated).toBe(2);
    expect(executeRaw.mock.calls[0].slice(1)).toEqual([
      'Marcos',
      USER_ID,
      ['m1', 'm2'],
    ]);
  });

  it('removes the entity and all its edges with scope=entity', async () => {
    const findFirst = jest.fn().mockResolvedValue(marcos);
    const findMany = jest.fn().mockResolvedValue(candidates);
    const nodeUpdateMany = jest.fn().mockResolvedValue({ count: 2 });
    const edgeUpdateMany = jest.fn().mockResolvedValue({ count: 3 });
    const { service } = buildService({
      node: { findFirst, findMany, updateMany: nodeUpdateMany },
      edge: { updateMany: edgeUpdateMany },
    });

    await service.remove(USER_ID, 'm1', 'entity');

    expect(nodeUpdateMany.mock.calls[0][0].where.id).toEqual({
      in: ['m1', 'm2'],
    });
    expect(nodeUpdateMany.mock.calls[0][0].data.deletedAt).toBeInstanceOf(Date);
    expect(edgeUpdateMany.mock.calls[0][0].where.OR).toEqual([
      { sourceNodeId: { in: ['m1', 'm2'] } },
      { targetNodeId: { in: ['m1', 'm2'] } },
    ]);
  });

  it('removes only a task itself even with scope=entity', async () => {
    const task = node({ id: 't1', type: 'task' });
    const findFirst = jest.fn().mockResolvedValue(task);
    const findMany = jest.fn();
    const nodeUpdateMany = jest.fn().mockResolvedValue({ count: 1 });
    const edgeUpdateMany = jest.fn().mockResolvedValue({ count: 0 });
    const { service } = buildService({
      node: { findFirst, findMany, updateMany: nodeUpdateMany },
      edge: { updateMany: edgeUpdateMany },
    });

    await service.remove(USER_ID, 't1', 'entity');

    expect(findMany).not.toHaveBeenCalled();
    expect(nodeUpdateMany.mock.calls[0][0].where.id).toEqual({ in: ['t1'] });
  });

  it('refuses to correct a capture', async () => {
    const findFirst = jest
      .fn()
      .mockResolvedValue(node({ id: CAPTURE_ID, type: 'capture' }));
    const { service } = buildService({ node: { findFirst }, edge: {} });

    await expect(
      service.remove(USER_ID, CAPTURE_ID, 'node'),
    ).rejects.toBeInstanceOf(BadRequestException);
    await expect(
      service.rename(USER_ID, CAPTURE_ID, 'x', 'node'),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('confirms a connection', async () => {
    const findFirst = jest
      .fn()
      .mockResolvedValue({ id: 'e1', type: 'assigned_to' });
    const update = jest.fn().mockResolvedValue(edge({ userConfirmed: true }));
    const { service } = buildService({ node: {}, edge: { findFirst, update } });

    const result = await service.reviewEdge(USER_ID, 'e1', true);

    expect(update).toHaveBeenCalledWith({
      where: { id: 'e1' },
      data: { userConfirmed: true },
    });
    expect(result).toMatchObject({
      id: 'e1',
      user_confirmed: true,
      deleted: false,
    });
  });

  it('rejects a connection with a soft delete', async () => {
    const findFirst = jest
      .fn()
      .mockResolvedValue({ id: 'e1', type: 'assigned_to' });
    const update = jest.fn().mockResolvedValue(edge());
    const { service } = buildService({ node: {}, edge: { findFirst, update } });

    const result = await service.reviewEdge(USER_ID, 'e1', false);

    expect(update.mock.calls[0][0].data.deletedAt).toBeInstanceOf(Date);
    expect(result.deleted).toBe(true);
  });

  it('never reviews provenance links and 404s unknown ones', async () => {
    const findFirst = jest
      .fn()
      .mockResolvedValueOnce({ id: 'e1', type: 'derived_from' })
      .mockResolvedValueOnce(null);
    const { service } = buildService({ node: {}, edge: { findFirst } });

    await expect(
      service.reviewEdge(USER_ID, 'e1', false),
    ).rejects.toBeInstanceOf(BadRequestException);
    await expect(
      service.reviewEdge(USER_ID, 'e2', true),
    ).rejects.toBeInstanceOf(NotFoundException);
  });
});

describe('GraphService.captureEntities', () => {
  it("throws NotFound when the capture is not the caller's", async () => {
    const findFirst = jest.fn().mockResolvedValue(null);
    const { service } = buildService({ node: { findFirst }, edge: {} });

    await expect(
      service.captureEntities(USER_ID, CAPTURE_ID),
    ).rejects.toBeInstanceOf(NotFoundException);
  });

  it('returns extracted nodes and semantic edges (with ids) for a capture', async () => {
    const findFirst = jest
      .fn()
      .mockResolvedValue({ id: CAPTURE_ID, status: 'processed' });
    const findMany = jest
      .fn()
      .mockResolvedValue([
        node({ id: 'task-1', type: 'task' }),
        node({ id: 'p-1', type: 'person', title: 'Marcos' }),
      ]);
    const edgeFindMany = jest
      .fn()
      // 1st call: provenance edges (derived_from) -> source node ids.
      .mockResolvedValueOnce([
        { sourceNodeId: 'task-1' },
        { sourceNodeId: 'p-1' },
      ])
      // 2nd call: semantic edges among those nodes.
      .mockResolvedValueOnce([edge()]);
    const { service } = buildService({
      node: { findFirst, findMany },
      edge: { findMany: edgeFindMany },
    });

    const result = await service.captureEntities(USER_ID, CAPTURE_ID);

    expect(result.status).toBe('processed');
    expect(result.nodes).toHaveLength(2);
    expect(result.edges).toEqual([
      {
        id: 'e1',
        source: 'task-1',
        target: 'p-1',
        type: 'assigned_to',
        confidence: 0.8,
        user_confirmed: false,
      },
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
