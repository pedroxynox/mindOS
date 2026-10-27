import { PrismaService } from '../prisma/prisma.service';
import { PrismaRlsService } from '../prisma/prisma-rls.service';
import { BriefingService } from '../briefing/briefing.service';
import { FinanceService } from '../finance/finance.service';
import { GrowthService } from '../growth/growth.service';
import { TasksService } from '../tasks/tasks.service';
import { UserSettingsService } from '../users/user-settings.service';

/**
 * Integration test of the post-F2 modules against REAL PostgreSQL (D-012):
 * tasks, growth, finance, briefing and user settings, connected as the
 * NON-owner `mindos_app` role so FORCE RLS is observed for real.
 *
 * Verifies, end to end through the services:
 *  - per-user isolation: user B never sees or mutates user A's items;
 *  - soft delete hides a task from lists and the briefing;
 *  - the user's timezone/currency (users table, PR B migration) drive the
 *    finance totals and the habit "today".
 *
 * Skipped unless RUN_INTEGRATION=1 (see apps/api/TESTING.md).
 */
const runIntegration = process.env.RUN_INTEGRATION === '1';
const describeIntegration = runIntegration ? describe : describe.skip;

describeIntegration('post-F2 modules (PostgreSQL + RLS)', () => {
  let prisma: PrismaService;
  let rls: PrismaRlsService;
  let settings: UserSettingsService;
  let tasks: TasksService;
  let growth: GrowthService;
  let finance: FinanceService;
  let briefing: BriefingService;
  let userA: string;
  let userB: string;

  beforeAll(async () => {
    prisma = new PrismaService();
    await prisma.$connect();
    rls = new PrismaRlsService(prisma);
    settings = new UserSettingsService(prisma);
    tasks = new TasksService(rls);
    growth = new GrowthService(rls, settings);
    finance = new FinanceService(rls, settings);
    briefing = new BriefingService(rls, settings);

    const stamp = Date.now();
    const a = await prisma.user.create({
      data: { email: `mods-a-${stamp}@test.local`, passwordHash: 'x' },
    });
    const b = await prisma.user.create({
      data: { email: `mods-b-${stamp}@test.local`, passwordHash: 'x' },
    });
    userA = a.id;
    userB = b.id;
  });

  afterAll(async () => {
    await prisma.$disconnect();
  });

  it('isolates tasks per user and soft-deletes them', async () => {
    const t = await tasks.create(userA, {
      title: 'Pagar la luz',
      priority: 'high',
    });

    expect((await tasks.list(userA)).map((x) => x.id)).toContain(t.id);
    expect((await tasks.list(userB)).map((x) => x.id)).not.toContain(t.id);
    await expect(tasks.update(userB, t.id, { done: true })).rejects.toThrow();
    await expect(tasks.remove(userB, t.id)).rejects.toThrow();

    const before = await briefing.build(userA);
    expect(before.tasks.map((x) => x.id)).toContain(t.id);

    await tasks.remove(userA, t.id);
    expect((await tasks.list(userA)).map((x) => x.id)).not.toContain(t.id);
    const after = await briefing.build(userA);
    expect(after.tasks.map((x) => x.id)).not.toContain(t.id);
  });

  it('persists timezone/currency and uses them for finance and habits', async () => {
    await settings.update(userA, {
      timezone: 'America/Sao_Paulo',
      currency: 'BRL',
    });
    expect(await settings.get(userA)).toEqual({
      timezone: 'America/Sao_Paulo',
      currency: 'BRL',
    });

    const e = await finance.addExpense(userA, {
      amount: 30,
      category: 'comida',
    });
    expect(e.currency).toBe('BRL');
    await finance.addExpense(userA, { amount: 10, currency: 'USD' });

    const summary = await finance.summary(userA);
    expect(summary.currency).toBe('BRL');
    expect(summary.week_total).toBe(30);
    expect(summary.other_currencies).toEqual([
      { currency: 'USD', week_total: 10 },
    ]);

    // User B sees none of user A's money.
    const other = await finance.summary(userB);
    expect(other.week_total).toBe(0);

    const habit = await growth.createHabit(userA, { title: 'Meditar' });
    const checked = await growth.toggleHabitToday(userA, habit.id);
    expect(checked.done_today).toBe(true);
    await expect(growth.toggleHabitToday(userB, habit.id)).rejects.toThrow();
    expect(await growth.listHabits(userB)).toEqual([]);
  });
});
