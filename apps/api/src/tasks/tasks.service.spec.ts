import { NotFoundException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaRlsService } from '../prisma/prisma-rls.service';
import { TasksService } from './tasks.service';

/**
 * Unit tests for TasksService: reads/writes run through PrismaRlsService.withUser
 * (RLS boundary), the list is priority-ordered with done tasks last, create
 * fills sensible attribute defaults, and update merges lifecycle fields
 * (toggling done stamps done_at). Prisma is a lightweight double.
 */
const USER_ID = '11111111-1111-1111-1111-111111111111';

function buildService(tx: {
  node: {
    findMany?: jest.Mock;
    create?: jest.Mock;
    findFirst?: jest.Mock;
    update?: jest.Mock;
  };
}): TasksService {
  const withUser = jest.fn(
    async <T>(
      _userId: string,
      work: (t: Prisma.TransactionClient) => Promise<T>,
    ): Promise<T> => work(tx as unknown as Prisma.TransactionClient),
  );
  return new TasksService({ withUser } as unknown as PrismaRlsService);
}

function taskRow(id: string, attributes: Record<string, unknown>) {
  return {
    id,
    title: `task ${id}`,
    attributes,
    origin: 'ai',
    createdAt: new Date('2026-07-10T00:00:00.000Z'),
  };
}

describe('TasksService.list', () => {
  it('orders open tasks by priority and puts done tasks last', async () => {
    const findMany = jest
      .fn()
      .mockResolvedValue([
        taskRow('low', { priority: 'low', done: false }),
        taskRow('done', { priority: 'high', done: true }),
        taskRow('high', { priority: 'high', done: false }),
        taskRow('med', { priority: 'medium', done: false }),
      ]);
    const service = buildService({ node: { findMany } });

    const result = await service.list(USER_ID, 'all');

    expect(result.map((t) => t.id)).toEqual(['high', 'med', 'low', 'done']);
  });

  it('hides done tasks when filter is pending', async () => {
    const findMany = jest
      .fn()
      .mockResolvedValue([
        taskRow('a', { priority: 'medium', done: true }),
        taskRow('b', { priority: 'medium', done: false }),
      ]);
    const service = buildService({ node: { findMany } });

    const result = await service.list(USER_ID, 'pending');

    expect(result.map((t) => t.id)).toEqual(['b']);
  });
});

describe('TasksService.create', () => {
  it('creates a manual task with sensible attribute defaults', async () => {
    const create = jest.fn().mockImplementation((args) =>
      Promise.resolve({
        id: 'new',
        title: args.data.title,
        attributes: args.data.attributes,
        origin: args.data.origin,
        createdAt: new Date('2026-07-10T00:00:00.000Z'),
      }),
    );
    const service = buildService({ node: { create } });

    const result = await service.create(USER_ID, { title: '  Llamar a Ana  ' });

    expect(result.title).toBe('Llamar a Ana');
    expect(result.done).toBe(false);
    expect(result.priority).toBe('medium');
    expect(result.origin).toBe('manual_text');
  });
});

describe('TasksService.update', () => {
  it('stamps done_at when marking a task done', async () => {
    const findFirst = jest
      .fn()
      .mockResolvedValue({ id: 't1', title: 'x', attributes: { done: false } });
    const update = jest.fn().mockImplementation((args) =>
      Promise.resolve({
        id: 't1',
        title: 'x',
        attributes: args.data.attributes,
        origin: 'ai',
        createdAt: new Date('2026-07-10T00:00:00.000Z'),
      }),
    );
    const service = buildService({ node: { findFirst, update } });

    const result = await service.update(USER_ID, 't1', { done: true });

    expect(result.done).toBe(true);
    expect(result.done_at).not.toBeNull();
  });

  it('throws NotFound when the task does not belong to the user', async () => {
    const findFirst = jest.fn().mockResolvedValue(null);
    const service = buildService({ node: { findFirst } });

    await expect(
      service.update(USER_ID, 'missing', { done: true }),
    ).rejects.toBeInstanceOf(NotFoundException);
  });

  it('clears done_at when re-opening and sets/clears the due date', async () => {
    const findFirst = jest.fn().mockResolvedValue({
      id: 't1',
      title: 'x',
      attributes: {
        done: true,
        done_at: '2026-07-09T00:00:00.000Z',
        due_at: 'old',
      },
    });
    const update = jest.fn().mockImplementation((args) =>
      Promise.resolve({
        id: 't1',
        title: 'x',
        attributes: args.data.attributes,
        origin: 'manual_text',
        createdAt: new Date('2026-07-10T00:00:00.000Z'),
      }),
    );
    const service = buildService({ node: { findFirst, update } });

    const reopened = await service.update(USER_ID, 't1', {
      done: false,
      due_at: null,
    });

    expect(reopened.done).toBe(false);
    expect(reopened.done_at).toBeNull();
    expect(reopened.due_at).toBeNull();
  });
});

describe('TasksService.remove', () => {
  it('soft-deletes an owned task', async () => {
    const findFirst = jest.fn().mockResolvedValue({ id: 't1' });
    const update = jest.fn().mockResolvedValue({});
    const service = buildService({ node: { findFirst, update } });

    await service.remove(USER_ID, 't1');

    expect(update.mock.calls[0][0]).toMatchObject({ where: { id: 't1' } });
    expect(update.mock.calls[0][0].data.deletedAt).toBeInstanceOf(Date);
  });

  it('throws NotFound for a task that is not the caller’s', async () => {
    const service = buildService({
      node: { findFirst: jest.fn().mockResolvedValue(null) },
    });
    await expect(service.remove(USER_ID, 'x')).rejects.toBeInstanceOf(
      NotFoundException,
    );
  });
});
