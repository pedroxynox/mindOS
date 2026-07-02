import { PrismaClient } from '@prisma/client';
import { PrismaRlsService } from './prisma-rls.service';
import { PrismaService } from './prisma.service';

/**
 * DB integration test for RLS fail-closed isolation (task 2.3, marked `*`).
 *
 * SKIPPED in this environment: requires a live PostgreSQL with the F1 migrations
 * applied (ENABLE/FORCE ROW LEVEL SECURITY + isolation policies) AND a
 * connection as the NON-OWNER application role (`mindos_app`). FORCE RLS is not
 * enforced for the table owner/superuser, so a real non-owner connection is
 * mandatory to observe the isolation. Run with docker-compose (Postgres) and
 * DATABASE_URL pointing at the non-owner role.
 *
 * Validates: Requirements R4.5, R4.2, R4.3 · Properties P1 (owner isolation),
 * P8 (fail-closed with no user context).
 *
 * Feature: capture-engine, Property 8: Fail-closed sin contexto de usuario.
 * Feature: capture-engine, Property 1: Aislamiento por dueño (RLS).
 */
describe.skip('PrismaRlsService — RLS isolation (requires Postgres + non-owner role)', () => {
  let prisma: PrismaService;
  let rls: PrismaRlsService;
  let userA: string;
  let userB: string;

  beforeAll(async () => {
    prisma = new PrismaService();
    await (prisma as unknown as PrismaClient).$connect();
    rls = new PrismaRlsService(prisma);

    // Seed two users (owner-context inserts happen without RLS on `users`).
    const a = await prisma.user.create({
      data: { email: `a-${Date.now()}@example.com`, passwordHash: 'x' },
    });
    const b = await prisma.user.create({
      data: { email: `b-${Date.now()}@example.com`, passwordHash: 'x' },
    });
    userA = a.id;
    userB = b.id;
  });

  afterAll(async () => {
    await (prisma as unknown as PrismaClient).$disconnect();
  });

  it('P1: each user only sees their own nodes', async () => {
    const created = await rls.withUser(userA, (tx) =>
      tx.node.create({
        data: {
          userId: userA,
          type: 'capture',
          origin: 'manual_text',
          body: 'a',
        },
      }),
    );

    // Owner A sees it.
    const seenByA = await rls.withUser(userA, (tx) =>
      tx.node.findUnique({ where: { id: created.id } }),
    );
    expect(seenByA).not.toBeNull();

    // Non-owner B does not.
    const seenByB = await rls.withUser(userB, (tx) =>
      tx.node.findUnique({ where: { id: created.id } }),
    );
    expect(seenByB).toBeNull();
  });

  it('P8: without app.current_user_id no rows are visible or writable', async () => {
    // Raw query outside withUser() => no context => fail-closed.
    const rows = await prisma.$queryRaw`SELECT id FROM nodes`;
    expect(rows).toHaveLength(0);

    await expect(
      prisma.$executeRaw`INSERT INTO nodes (user_id, type, origin) VALUES (${userA}::uuid, 'capture', 'manual_text')`,
    ).rejects.toBeTruthy();
  });
});
