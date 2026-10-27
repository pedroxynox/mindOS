import { INestApplication } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import request from 'supertest';
import { PrismaService } from '../prisma/prisma.service';
import { createHttpHarness, TEST_USER_ID } from '../test/http-harness';
import { MeController } from './me.controller';
import { UserSettingsService } from './user-settings.service';

/**
 * `/v1/me` (D-013/D-014): returns the profile with the effective currency;
 * PATCH validates the IANA timezone and the ISO-4217 currency, and accepts
 * `currency: null` to reset. Prisma is a double; validation is real.
 */
describe('MeController (HTTP)', () => {
  let app: INestApplication;
  const user = {
    id: TEST_USER_ID,
    email: 'pedro@example.com',
    timezone: 'UTC',
    currency: null as string | null,
    createdAt: new Date('2026-07-01T00:00:00.000Z'),
  };
  const prisma = {
    user: {
      findUnique: jest.fn(async () => ({ ...user })),
      update: jest.fn(async ({ data }: { data: Partial<typeof user> }) => {
        Object.assign(user, data);
        return user;
      }),
    },
  };

  beforeAll(async () => {
    app = await createHttpHarness(
      [MeController],
      [
        UserSettingsService,
        { provide: PrismaService, useValue: prisma },
        { provide: JwtService, useValue: {} },
      ],
    );
  });

  afterAll(async () => {
    await app.close();
  });

  it('returns the profile with the effective currency', async () => {
    const res = await request(app.getHttpServer()).get('/v1/me');
    expect(res.status).toBe(200);
    expect(res.body).toMatchObject({
      email: 'pedro@example.com',
      timezone: 'UTC',
      currency: null,
      effective_currency: 'USD',
    });
  });

  it('updates timezone and currency', async () => {
    const res = await request(app.getHttpServer())
      .patch('/v1/me')
      .send({ timezone: 'America/Sao_Paulo', currency: 'BRL' });
    expect(res.status).toBe(200);
    expect(res.body).toMatchObject({
      timezone: 'America/Sao_Paulo',
      currency: 'BRL',
      effective_currency: 'BRL',
    });
  });

  it.each([
    [{ timezone: 'Mars/Olympus' }],
    [{ timezone: '' }],
    [{ currency: 'REAIS' }],
    [{ currency: 'brl' }],
    [{ email: 'x@y.z' }],
  ])('rejects an invalid patch %j with 400', async (body) => {
    const res = await request(app.getHttpServer()).patch('/v1/me').send(body);
    expect(res.status).toBe(400);
  });

  it('resets the currency with null', async () => {
    const res = await request(app.getHttpServer())
      .patch('/v1/me')
      .send({ currency: null });
    expect(res.status).toBe(200);
    expect(res.body.currency).toBeNull();
    expect(res.body.effective_currency).toBe('USD');
  });
});
