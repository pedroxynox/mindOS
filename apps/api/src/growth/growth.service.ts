import { Injectable, NotFoundException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaRlsService } from '../prisma/prisma-rls.service';
import {
  CreateGoalDto,
  CreateHabitDto,
  CreateReflectionDto,
  UpdateGoalDto,
} from './dto/growth.dto';
import {
  dateKey,
  GoalResponse,
  GrowthKind,
  HabitResponse,
  ReflectionResponse,
  toGoalResponse,
  toHabitResponse,
  toReflectionResponse,
} from './growth.mapper';

const SELECT = {
  id: true,
  title: true,
  body: true,
  attributes: true,
  createdAt: true,
} as const;

/**
 * Personal-development features (Growth): goals, habits and reflections. Stored
 * as `note` nodes discriminated by `attributes.kind` — no schema migration, and
 * RLS on `nodes` isolates them per user. Every read/write runs inside
 * `PrismaRlsService.withUser`.
 */
@Injectable()
export class GrowthService {
  constructor(private readonly rls: PrismaRlsService) {}

  private listByKind(userId: string, kind: GrowthKind) {
    return this.rls.withUser(userId, (tx) =>
      tx.node.findMany({
        where: {
          userId,
          type: 'note',
          deletedAt: null,
          attributes: { path: ['kind'], equals: kind },
        },
        orderBy: [{ createdAt: 'desc' }],
        select: SELECT,
      }),
    );
  }

  private findOwned(
    tx: Prisma.TransactionClient,
    userId: string,
    id: string,
    kind: GrowthKind,
  ) {
    return tx.node.findFirst({
      where: {
        id,
        userId,
        type: 'note',
        deletedAt: null,
        attributes: { path: ['kind'], equals: kind },
      },
      select: SELECT,
    });
  }

  // --- Goals -----------------------------------------------------------------

  async listGoals(userId: string): Promise<GoalResponse[]> {
    const rows = await this.listByKind(userId, 'goal');
    return rows.map(toGoalResponse);
  }

  async createGoal(userId: string, dto: CreateGoalDto): Promise<GoalResponse> {
    const attributes: Prisma.InputJsonValue = {
      kind: 'goal',
      progress: 0,
      done: false,
      target_date: dto.targetDate ?? null,
      ...(dto.area ? { area: dto.area } : {}),
    };
    const node = await this.rls.withUser(userId, (tx) =>
      tx.node.create({
        data: {
          userId,
          type: 'note',
          title: dto.title.trim(),
          origin: 'manual_text',
          status: 'processed',
          attributes,
        },
        select: SELECT,
      }),
    );
    return toGoalResponse(node);
  }

  async updateGoal(
    userId: string,
    id: string,
    dto: UpdateGoalDto,
  ): Promise<GoalResponse> {
    return this.rls.withUser(userId, async (tx) => {
      const existing = await this.findOwned(tx, userId, id, 'goal');
      if (!existing) throw this.notFound('Goal');

      const next = { ...((existing.attributes ?? {}) as Record<string, unknown>) };
      if (dto.progress !== undefined) {
        next.progress = dto.progress;
        if (dto.progress >= 100) next.done = true;
      }
      if (dto.targetDate !== undefined) next.target_date = dto.targetDate;

      const data: Prisma.NodeUpdateInput = {
        attributes: next as Prisma.InputJsonValue,
      };
      if (dto.title !== undefined) data.title = dto.title.trim();

      const updated = await tx.node.update({ where: { id }, data, select: SELECT });
      return toGoalResponse(updated);
    });
  }

  // --- Habits ----------------------------------------------------------------

  async listHabits(userId: string): Promise<HabitResponse[]> {
    const rows = await this.listByKind(userId, 'habit');
    return rows.map((r) => toHabitResponse(r));
  }

  async createHabit(userId: string, dto: CreateHabitDto): Promise<HabitResponse> {
    const attributes: Prisma.InputJsonValue = {
      kind: 'habit',
      cadence: dto.cadence ?? 'daily',
      log: [],
      ...(dto.area ? { area: dto.area } : {}),
    };
    const node = await this.rls.withUser(userId, (tx) =>
      tx.node.create({
        data: {
          userId,
          type: 'note',
          title: dto.title.trim(),
          origin: 'manual_text',
          status: 'processed',
          attributes,
        },
        select: SELECT,
      }),
    );
    return toHabitResponse(node);
  }

  /** Toggle today's completion for a habit (idempotent per day). */
  async toggleHabitToday(userId: string, id: string): Promise<HabitResponse> {
    return this.rls.withUser(userId, async (tx) => {
      const existing = await this.findOwned(tx, userId, id, 'habit');
      if (!existing) throw this.notFound('Habit');

      const attrs = (existing.attributes ?? {}) as Record<string, unknown>;
      const log = Array.isArray(attrs.log)
        ? (attrs.log as unknown[]).filter((x): x is string => typeof x === 'string')
        : [];
      const today = dateKey(new Date());
      const next = log.includes(today)
        ? log.filter((d) => d !== today)
        : [...log, today];

      const updated = await tx.node.update({
        where: { id },
        data: { attributes: { ...attrs, log: next } as Prisma.InputJsonValue },
        select: SELECT,
      });
      return toHabitResponse(updated);
    });
  }

  // --- Reflections -----------------------------------------------------------

  async listReflections(userId: string): Promise<ReflectionResponse[]> {
    const rows = await this.listByKind(userId, 'reflection');
    return rows.map(toReflectionResponse);
  }

  async createReflection(
    userId: string,
    dto: CreateReflectionDto,
  ): Promise<ReflectionResponse> {
    const attributes: Prisma.InputJsonValue = {
      kind: 'reflection',
      ...(dto.mood ? { mood: dto.mood } : {}),
    };
    const node = await this.rls.withUser(userId, (tx) =>
      tx.node.create({
        data: {
          userId,
          type: 'note',
          body: dto.body.trim(),
          origin: 'manual_text',
          status: 'processed',
          attributes,
        },
        select: SELECT,
      }),
    );
    return toReflectionResponse(node);
  }

  private notFound(what: string): NotFoundException {
    return new NotFoundException({
      code: 'not_found',
      message: `${what} not found.`,
    });
  }
}
