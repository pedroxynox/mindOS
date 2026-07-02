import { Test, TestingModule } from '@nestjs/testing';
import { PrismaService } from './prisma.service';
import { PrismaRlsService } from './prisma-rls.service';

/**
 * Unit tests for PrismaRlsService.withUser (design.md §6.1, task 3.2).
 *
 * These use a mocked Prisma client and verify the *orchestration* contract:
 *   - an interactive transaction is opened, and
 *   - `set_config('app.current_user_id', <userId>, true)` is executed with the
 *     given userId BEFORE the caller's `work` runs.
 *
 * The actual RLS isolation behaviour (properties P1/P8) can only be verified
 * against a real PostgreSQL instance with RLS + a non-owner role; that lives in
 * the DB-integration tests (see prisma-rls.rls.integration.spec.ts), which are
 * skipped in this environment.
 */
describe('PrismaRlsService', () => {
  let service: PrismaRlsService;
  let executeRawCalls: unknown[][];
  let tx: { $executeRaw: jest.Mock };
  let prisma: { $transaction: jest.Mock };

  beforeEach(async () => {
    executeRawCalls = [];
    tx = {
      // Prisma's tagged-template $executeRaw receives (strings, ...values).
      $executeRaw: jest.fn((...args: unknown[]) => {
        executeRawCalls.push(args);
        return Promise.resolve(1);
      }),
    };
    prisma = {
      $transaction: jest.fn(async (cb: (t: typeof tx) => Promise<unknown>) =>
        cb(tx),
      ),
    };

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        PrismaRlsService,
        { provide: PrismaService, useValue: prisma },
      ],
    }).compile();

    service = module.get<PrismaRlsService>(PrismaRlsService);
  });

  it('opens an interactive transaction and returns the work result', async () => {
    const result = await service.withUser('user-uuid-1', async () => 'ok');

    expect(prisma.$transaction).toHaveBeenCalledTimes(1);
    expect(result).toBe('ok');
  });

  it('sets app.current_user_id with the given userId before running work', async () => {
    const order: string[] = [];
    tx.$executeRaw.mockImplementation((...args: unknown[]) => {
      executeRawCalls.push(args);
      order.push('set_config');
      return Promise.resolve(1);
    });

    await service.withUser('user-uuid-42', async () => {
      order.push('work');
      return undefined;
    });

    // set_config must run strictly before the caller's work.
    expect(order).toEqual(['set_config', 'work']);

    // The template tag receives the SQL fragments as the first arg and the
    // bound values afterwards. Verify the userId is passed as a bound value and
    // the statement targets app.current_user_id transaction-locally.
    expect(executeRawCalls).toHaveLength(1);
    const [strings, ...values] = executeRawCalls[0] as [
      TemplateStringsArray,
      ...unknown[],
    ];
    expect(strings.join('?')).toContain('set_config');
    expect(strings.join('?')).toContain('app.current_user_id');
    expect(values).toContain('user-uuid-42');
  });

  it('propagates the transaction client to the work callback', async () => {
    let received: unknown;
    await service.withUser('user-uuid-7', async (client) => {
      received = client;
      return undefined;
    });
    expect(received).toBe(tx);
  });
});
