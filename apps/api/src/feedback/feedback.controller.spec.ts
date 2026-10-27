import { INestApplication } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { Prisma } from '@prisma/client';
import request from 'supertest';
import { PrismaRlsService } from '../prisma/prisma-rls.service';
import { createHttpHarness, TEST_USER_ID } from '../test/http-harness';
import { FeedbackController } from './feedback.controller';
import { FeedbackService } from './feedback.service';

/**
 * `/v1/feedback` (FR-3.5): one vote per (user, target) via an upsert under
 * RLS; voting again replaces it; GET returns the current vote or null.
 * Validation is real, Prisma is a double.
 */
describe('FeedbackController (HTTP)', () => {
  let app: INestApplication;
  const now = new Date('2026-10-27T12:00:00.000Z');
  const tx = {
    feedback: {
      upsert: jest.fn(
        async ({ create }: { create: Record<string, unknown> }) => ({
          id: 'f1',
          ...create,
          createdAt: now,
          updatedAt: now,
        }),
      ),
      findUnique: jest.fn(),
    },
  };
  const withUser = jest.fn(
    async <T>(_: string, work: (t: Prisma.TransactionClient) => Promise<T>) =>
      work(tx as unknown as Prisma.TransactionClient),
  );

  beforeAll(async () => {
    app = await createHttpHarness(
      [FeedbackController],
      [
        FeedbackService,
        { provide: PrismaRlsService, useValue: { withUser } },
        { provide: JwtService, useValue: {} },
      ],
    );
  });

  afterAll(async () => {
    await app.close();
  });

  beforeEach(() => jest.clearAllMocks());

  it('records a vote as an upsert on the (user, target) key', async () => {
    const res = await request(app.getHttpServer()).post('/v1/feedback').send({
      target_type: 'capture',
      target_id: ' c-1 ',
      useful: false,
      reason: ' mal ',
    });

    expect(res.status).toBe(201);
    expect(res.body).toMatchObject({
      target_type: 'capture',
      target_id: 'c-1',
      useful: false,
      reason: 'mal',
    });
    expect(withUser).toHaveBeenCalledWith(TEST_USER_ID, expect.any(Function));
    const args = tx.feedback.upsert.mock.calls[0][0] as unknown as {
      where: unknown;
      update: unknown;
    };
    expect(args.where).toEqual({
      uq_feedback_user_target: {
        userId: TEST_USER_ID,
        targetType: 'capture',
        targetId: 'c-1',
      },
    });
    expect(args.update).toEqual({ useful: false, reason: 'mal' });
  });

  it.each([
    [{ target_type: 'mood', target_id: 'x', useful: true }],
    [{ target_type: 'query', target_id: '   ', useful: true }],
    [{ target_type: 'query', target_id: 'x' }],
    [{ target_type: 'query', target_id: 'x', useful: 'yes' }],
    [
      {
        target_type: 'query',
        target_id: 'x',
        useful: true,
        user_id: TEST_USER_ID,
      },
    ],
  ])('rejects an invalid vote %j with 400', async (body) => {
    const res = await request(app.getHttpServer())
      .post('/v1/feedback')
      .send(body);
    expect(res.status).toBe(400);
    expect(tx.feedback.upsert).not.toHaveBeenCalled();
  });

  it('returns the current vote, or null when there is none', async () => {
    tx.feedback.findUnique.mockResolvedValueOnce({ useful: true });
    const voted = await request(app.getHttpServer())
      .get('/v1/feedback')
      .query({ target_type: 'briefing', target_id: '2026-10-27' });
    expect(voted.status).toBe(200);
    expect(voted.body).toEqual({
      target_type: 'briefing',
      target_id: '2026-10-27',
      useful: true,
    });

    tx.feedback.findUnique.mockResolvedValueOnce(null);
    const none = await request(app.getHttpServer())
      .get('/v1/feedback')
      .query({ target_type: 'query', target_id: '¿qué tengo pendiente?' });
    expect(none.body.useful).toBeNull();
  });
});
