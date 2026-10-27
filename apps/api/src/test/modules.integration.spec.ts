import { randomUUID } from 'node:crypto';
import { BlobStorageService } from '../capture/blob-storage.service';
import { CaptureService } from '../capture/capture.service';
import { IdempotencyService } from '../capture/idempotency.service';
import { PrismaService } from '../prisma/prisma.service';
import { PrismaRlsService } from '../prisma/prisma-rls.service';
import { BriefingService } from '../briefing/briefing.service';
import { FinanceService } from '../finance/finance.service';
import { GrowthService } from '../growth/growth.service';
import { TasksService } from '../tasks/tasks.service';
import { UserSettingsService } from '../users/user-settings.service';
import { FeedbackService } from '../feedback/feedback.service';
import { GraphService } from '../graph/graph.service';
import { ListNodesQueryDto } from '../graph/dto/list-nodes-query.dto';
import { ListExpensesQueryDto } from '../finance/dto/list-expenses-query.dto';

/**
 * Integration test of the post-F2 modules against REAL PostgreSQL (D-012):
 * tasks, growth, finance, briefing and user settings, connected as the
 * NON-owner `mindos_app` role so FORCE RLS is observed for real.
 *
 * Verifies, end to end through the services:
 *  - per-user isolation: user B never sees or mutates user A's items;
 *  - soft delete hides a task from lists and the briefing;
 *  - the user's timezone/currency (users table, PR B migration) drive the
 *    finance totals and the habit "today";
 *  - feedback votes and graph corrections (PR D) stay per user, and a removed
 *    or renamed node survives the worker reprocessing its capture;
 *  - expenses the AI found in a capture (PR E) are listed and summed with the
 *    manual ones, per user, and can be removed.
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
  let graph: GraphService;
  let feedback: FeedbackService;
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
    graph = new GraphService(rls);
    feedback = new FeedbackService(rls);

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

  it('stores a voice note as text + cost under RLS, idempotently (ADR-021)', async () => {
    const transcribe = jest.fn().mockResolvedValue({
      text: 'Llamar a Marcos mañana',
      provider: 'openai',
      model: 'gpt-transcribe',
      duration_s: 4.2,
      cost_usd: 0.000315,
    });
    const queue = {
      enqueueUnderstanding: jest.fn().mockResolvedValue(undefined),
    };
    const captures = new CaptureService(
      rls,
      new IdempotencyService(rls),
      {} as BlobStorageService,
      queue,
      { transcribe },
    );
    const key = randomUUID();
    const audio = Buffer.from('fake-opus-bytes');

    const first = await captures.createVoice(userA, key, {
      audio,
      contentType: 'audio/webm',
      clientId: key,
      durationMs: 4200,
    });
    const replay = await captures.createVoice(userA, key, {
      audio,
      contentType: 'audio/webm',
      clientId: key,
      durationMs: 4200,
    });

    expect(first.content).toBe('Llamar a Marcos mañana');
    expect(replay.capture_id).toBe(first.capture_id);
    expect(transcribe).toHaveBeenCalledTimes(1); // no double charge

    const usage = await rls.withUser(userA, (tx) =>
      tx.llmUsage.findMany({ where: { captureId: first.capture_id } }),
    );
    expect(usage).toHaveLength(1);
    expect(usage[0].operation).toBe('transcribe');
    const hidden = await rls.withUser(userB, (tx) =>
      tx.llmUsage.findMany({ where: { captureId: first.capture_id } }),
    );
    expect(hidden).toHaveLength(0);
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

  it('keeps feedback votes per user and replaces a repeated vote', async () => {
    const target = { target_type: 'capture' as const, target_id: randomUUID() };
    await feedback.record(userA, { ...target, useful: true });
    await feedback.record(userA, {
      ...target,
      useful: false,
      reason: 'faltó Ana',
    });

    expect((await feedback.vote(userA, target)).useful).toBe(false);
    expect((await feedback.vote(userB, target)).useful).toBeNull();

    await feedback.record(userB, { ...target, useful: true });
    expect((await feedback.vote(userA, target)).useful).toBe(false);
    const rows = await rls.withUser(userA, (tx) =>
      tx.feedback.findMany({ where: { targetId: target.target_id } }),
    );
    expect(rows).toHaveLength(1);
    expect(rows[0].reason).toBe('faltó Ana');
  });

  it('groups, corrects and forgets entities under RLS (FR-2.4)', async () => {
    const run = randomUUID();
    // What the worker would have written for two captures mentioning Marcos.
    const seeded = await rls.withUser(userA, async (tx) => {
      const capture = (body: string) =>
        tx.node.create({
          data: {
            userId: userA,
            type: 'capture',
            body,
            origin: 'manual_text',
            status: 'processed',
          },
        });
      const derived = (type: 'person' | 'task', title: string, key: string) =>
        tx.node.create({
          data: {
            userId: userA,
            type,
            title,
            origin: 'ai',
            status: 'processed',
            confidence: 0.9,
            attributes: { dedup_key: `${run}-${key}` },
          },
        });
      const link = (type: string, source: string, target: string) =>
        tx.edge.create({
          data: {
            userId: userA,
            type,
            sourceNodeId: source,
            targetNodeId: target,
            origin: 'ai',
          },
        });

      const c1 = await capture('Llamar a Marcos por el presupuesto');
      const c2 = await capture('Café con márcos');
      const m1 = await derived('person', 'Marcos', 'm1');
      const t1 = await derived('task', 'Llamar a Marcos', 't1');
      const m2 = await derived('person', 'márcos', 'm2');
      await link('derived_from', m1.id, c1.id);
      await link('derived_from', t1.id, c1.id);
      await link('derived_from', m2.id, c2.id);
      const assigned = await link('assigned_to', t1.id, m1.id);
      return { c1, c2, m1, m2, t1, assigned };
    });

    const people = (user: string) =>
      graph.listNodes(
        user,
        Object.assign(new ListNodesQueryDto(), { type: 'person', limit: 50 }),
      );
    const marcos = (await people(userA)).data.find(
      (p) => p.id === seeded.m2.id,
    );
    expect(marcos?.mentions).toBe(2);
    expect((await people(userB)).data).toEqual([]);

    const detail = await graph.entity(userA, seeded.m1.id);
    expect(detail.mentions).toBe(2);
    expect(detail.captures.map((c) => c.id).sort()).toEqual(
      [seeded.c1.id, seeded.c2.id].sort(),
    );
    expect(detail.tasks.map((t) => t.id)).toEqual([seeded.t1.id]);
    await expect(graph.entity(userB, seeded.m1.id)).rejects.toThrow();

    // User B can never correct A's graph.
    await expect(
      graph.rename(userB, seeded.m1.id, 'X', 'entity'),
    ).rejects.toThrow();
    await expect(graph.remove(userB, seeded.m1.id, 'entity')).rejects.toThrow();
    await expect(
      graph.reviewEdge(userB, seeded.assigned.id, false),
    ).rejects.toThrow();

    const confirmed = await graph.reviewEdge(userA, seeded.assigned.id, true);
    expect(confirmed.user_confirmed).toBe(true);

    const renamed = await graph.rename(
      userA,
      seeded.t1.id,
      'Llamar a Marcos el lunes',
      'node',
    );
    expect(renamed.updated).toBe(1);
    const entityRename = await graph.rename(
      userA,
      seeded.m1.id,
      'Marcos Pérez',
      'entity',
    );
    expect(entityRename.updated).toBe(2);

    await graph.remove(userA, seeded.m2.id, 'entity');
    const after = await people(userA);
    expect(after.data.map((p) => p.id)).not.toContain(seeded.m1.id);
    expect(after.data.map((p) => p.id)).not.toContain(seeded.m2.id);
    const insights = await graph.captureEntities(userA, seeded.c1.id);
    expect(insights.nodes.map((n) => n.id)).toEqual([seeded.t1.id]);
    expect(insights.edges).toEqual([]);

    // The worker reprocesses capture 1 with its idempotent upsert: the removed
    // person stays removed and the renamed task keeps the user's title.
    await rls.withUser(userA, async (tx) => {
      for (const [type, title, key] of [
        ['person', 'Marcos', 'm1'],
        ['task', 'Llamar a Marcos', 't1'],
      ]) {
        await tx.$executeRaw`
          INSERT INTO nodes (user_id, type, title, attributes, origin, status, confidence, updated_at)
          VALUES (${userA}::uuid, ${type}::node_type, ${title},
                  jsonb_build_object('dedup_key', ${`${run}-${key}`}::text), 'ai',
                  'processed'::capture_status, 0.95, now())
          ON CONFLICT (user_id, ((attributes->>'dedup_key'))) WHERE origin = 'ai'
          DO UPDATE SET confidence = EXCLUDED.confidence`;
      }
    });
    const [person, task] = await rls.withUser(userA, (tx) =>
      Promise.all([
        tx.node.findUnique({ where: { id: seeded.m1.id } }),
        tx.node.findUnique({ where: { id: seeded.t1.id } }),
      ]),
    );
    expect(person?.deletedAt).not.toBeNull();
    expect(person?.title).toBe('Marcos Pérez');
    expect(task?.deletedAt).toBeNull();
    expect(task?.title).toBe('Llamar a Marcos el lunes');
    expect((task?.attributes as Record<string, unknown>).user_edited).toBe(
      true,
    );
    const summary = await graph.summary(userA);
    expect(summary.counts.person ?? 0).toBe(0);
  });

  it('lists, sums and removes AI-detected expenses under RLS (PR E)', async () => {
    const userC = (
      await prisma.user.create({
        data: {
          email: `mods-c-${Date.now()}@test.local`,
          passwordHash: 'x',
          currency: 'BRL',
          timezone: 'UTC',
        },
      })
    ).id;
    const spentAt = new Date(Date.now() - 60_000).toISOString();
    // What the worker writes for "Almuerzo R$ 30" (mejoras-v2 §E).
    const { capture, aiExpense } = await rls.withUser(userC, async (tx) => {
      const capture = await tx.node.create({
        data: {
          userId: userC,
          type: 'capture',
          body: 'Almuerzo R$ 30 con Ana',
          origin: 'manual_text',
          status: 'processed',
        },
      });
      const aiExpense = await tx.node.create({
        data: {
          userId: userC,
          type: 'note',
          title: 'almuerzo',
          origin: 'ai',
          status: 'processed',
          confidence: 0.8,
          attributes: {
            dedup_key: `exp-${randomUUID()}`,
            kind: 'expense',
            amount: 30,
            currency: 'BRL',
            category: 'food',
            spent_at: spentAt,
            capture_id: capture.id,
          },
        },
      });
      await tx.edge.create({
        data: {
          userId: userC,
          type: 'derived_from',
          sourceNodeId: aiExpense.id,
          targetNodeId: capture.id,
          origin: 'ai',
        },
      });
      return { capture, aiExpense };
    });
    await finance.addExpense(userC, { amount: 12, category: 'Uber' });

    const page = await finance.listExpenses(
      userC,
      Object.assign(new ListExpensesQueryDto(), { limit: 10 }),
    );
    expect(
      page.data.map((e) => [e.origin, e.amount, e.category]).sort(),
    ).toEqual([
      ['ai', 30, 'food'],
      ['manual_text', 12, 'transport'],
    ]);
    const ai = page.data.find((e) => e.origin === 'ai');
    expect(ai?.capture_id).toBe(capture.id);
    expect(ai?.note).toBe('almuerzo');

    const summary = await finance.summary(userC);
    expect(summary.week_total).toBe(42);
    expect(summary.by_category).toEqual([
      { category: 'food', total: 30 },
      { category: 'transport', total: 12 },
    ]);

    const insights = await graph.captureEntities(userC, capture.id);
    expect(insights.nodes[0].expense).toEqual({
      amount: 30,
      currency: 'BRL',
      category: 'food',
    });

    // Nobody else can list or remove it.
    const others = await finance.listExpenses(
      userA,
      Object.assign(new ListExpensesQueryDto(), { limit: 100 }),
    );
    expect(others.data.map((e) => e.id)).not.toContain(aiExpense.id);
    await expect(finance.removeExpense(userA, aiExpense.id)).rejects.toThrow();

    await finance.removeExpense(userC, aiExpense.id);
    const after = await finance.summary(userC);
    expect(after.week_total).toBe(12);
    expect((await graph.captureEntities(userC, capture.id)).nodes).toEqual([]);
  });
});
