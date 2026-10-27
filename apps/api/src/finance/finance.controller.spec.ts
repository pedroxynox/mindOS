import { INestApplication } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import request from 'supertest';
import { createHttpHarness, TEST_USER_ID } from '../test/http-harness';
import { FinanceController } from './finance.controller';
import { FinanceService } from './finance.service';

/**
 * `/v1/finance/expenses` over HTTP (mejoras-v2 §E): list with a validated
 * cursor/limit and soft delete with 204. The service is a double.
 */
describe('FinanceController (HTTP)', () => {
  let app: INestApplication;
  const ID = '44444444-4444-4444-8444-444444444444';
  const finance = {
    summary: jest.fn(),
    addExpense: jest.fn(),
    listExpenses: jest.fn(async () => ({ data: [], next_cursor: null })),
    removeExpense: jest.fn(async () => undefined),
  };

  beforeAll(async () => {
    app = await createHttpHarness(
      [FinanceController],
      [
        { provide: FinanceService, useValue: finance },
        { provide: JwtService, useValue: {} },
      ],
    );
  });

  afterAll(async () => {
    await app.close();
  });

  beforeEach(() => jest.clearAllMocks());

  it('lists expenses with the default page size', async () => {
    const res = await request(app.getHttpServer()).get('/v1/finance/expenses');
    expect(res.status).toBe(200);
    expect(finance.listExpenses).toHaveBeenCalledWith(
      TEST_USER_ID,
      expect.objectContaining({ limit: 50 }),
    );
  });

  it.each(['?limit=0', '?limit=101', '?cursor=abc'])(
    'rejects %s with 400',
    async (qs) => {
      const res = await request(app.getHttpServer()).get(
        `/v1/finance/expenses${qs}`,
      );
      expect(res.status).toBe(400);
      expect(finance.listExpenses).not.toHaveBeenCalled();
    },
  );

  it('removes an expense with 204', async () => {
    await request(app.getHttpServer())
      .delete(`/v1/finance/expenses/${ID}`)
      .expect(204);
    expect(finance.removeExpense).toHaveBeenCalledWith(TEST_USER_ID, ID);

    await request(app.getHttpServer())
      .delete('/v1/finance/expenses/nope')
      .expect(400);
    expect(finance.removeExpense).toHaveBeenCalledTimes(1);
  });
});
