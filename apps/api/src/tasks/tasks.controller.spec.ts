import { INestApplication } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import request from 'supertest';
import { createHttpHarness, TEST_USER_ID } from '../test/http-harness';
import { TasksController } from './tasks.controller';
import { TasksService } from './tasks.service';

/**
 * HTTP-level tests for `/v1/tasks` (D-012): DTO validation (blank titles,
 * unknown fields, bad priorities), the snake_case `due_at` field and its
 * deprecated alias, UUID params and the 204 on delete. The service is mocked.
 */
const TASK = {
  id: '22222222-2222-2222-2222-222222222222',
  title: 'Llamar a Ana',
  done: false,
  done_at: null,
  priority: 'medium',
  due_at: null,
  area: null,
  origin: 'manual_text',
  created_at: '2026-07-10T00:00:00.000Z',
};

describe('TasksController (HTTP)', () => {
  let app: INestApplication;
  const service = {
    list: jest.fn().mockResolvedValue([TASK]),
    create: jest.fn().mockResolvedValue(TASK),
    update: jest.fn().mockResolvedValue(TASK),
    remove: jest.fn().mockResolvedValue(undefined),
  };

  beforeAll(async () => {
    app = await createHttpHarness(
      [TasksController],
      [
        { provide: TasksService, useValue: service },
        { provide: JwtService, useValue: {} },
      ],
    );
  });

  afterAll(async () => {
    await app.close();
  });

  beforeEach(() => jest.clearAllMocks());

  it('lists tasks for the authenticated user', async () => {
    const res = await request(app.getHttpServer()).get(
      '/v1/tasks?filter=pending',
    );
    expect(res.status).toBe(200);
    expect(service.list).toHaveBeenCalledWith(TEST_USER_ID, 'pending');
  });

  it('creates a task with the snake_case due_at field', async () => {
    const res = await request(app.getHttpServer())
      .post('/v1/tasks')
      .send({
        title: 'Pagar luz',
        priority: 'high',
        due_at: '2026-07-12T10:00:00Z',
      });
    expect(res.status).toBe(201);
    expect(service.create.mock.calls[0][1]).toMatchObject({
      title: 'Pagar luz',
      due_at: '2026-07-12T10:00:00Z',
    });
  });

  it('still accepts the deprecated camelCase dueAt alias', async () => {
    const res = await request(app.getHttpServer())
      .post('/v1/tasks')
      .send({ title: 'Pagar luz', dueAt: '2026-07-12T10:00:00Z' });
    expect(res.status).toBe(201);
  });

  it.each([
    [{ title: '' }],
    [{ title: '   ' }],
    [{ title: 'ok', priority: 'urgent' }],
    [{ title: 'ok', due_at: 'tomorrow' }],
    [{ title: 'ok', hacker: true }],
  ])('rejects an invalid create body %j with 400', async (body) => {
    const res = await request(app.getHttpServer()).post('/v1/tasks').send(body);
    expect(res.status).toBe(400);
    expect(service.create).not.toHaveBeenCalled();
  });

  it('rejects a blank title on PATCH with 400', async () => {
    const res = await request(app.getHttpServer())
      .patch(`/v1/tasks/${TASK.id}`)
      .send({ title: '  ' });
    expect(res.status).toBe(400);
    expect(service.update).not.toHaveBeenCalled();
  });

  it('allows clearing the due date with due_at: null', async () => {
    const res = await request(app.getHttpServer())
      .patch(`/v1/tasks/${TASK.id}`)
      .send({ due_at: null });
    expect(res.status).toBe(200);
    expect(service.update.mock.calls[0][2]).toEqual({ due_at: null });
  });

  it('rejects a non-UUID id with 400', async () => {
    const res = await request(app.getHttpServer())
      .patch('/v1/tasks/not-a-uuid')
      .send({ done: true });
    expect(res.status).toBe(400);
  });

  it('deletes a task with 204', async () => {
    const res = await request(app.getHttpServer()).delete(
      `/v1/tasks/${TASK.id}`,
    );
    expect(res.status).toBe(204);
    expect(service.remove).toHaveBeenCalledWith(TEST_USER_ID, TASK.id);
  });
});
