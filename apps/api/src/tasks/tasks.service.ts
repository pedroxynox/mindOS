import { Injectable, NotFoundException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaRlsService } from '../prisma/prisma-rls.service';
import { CreateTaskDto } from './dto/create-task.dto';
import { UpdateTaskDto } from './dto/update-task.dto';
import { compareTasks, TaskResponse, toTaskResponse } from './tasks.mapper';

/**
 * Task management over the knowledge graph. Tasks are `node` rows of type
 * `task`: some are AI-extracted from captures (`origin = 'ai'`), others created
 * by the user here (`origin = 'manual_text'`). Their lifecycle (done / priority
 * / due date / area) lives in `attributes`, so this needs no schema migration.
 *
 * All reads and writes run inside `PrismaRlsService.withUser`, so PostgreSQL RLS
 * guarantees a user only ever touches their own tasks.
 */
@Injectable()
export class TasksService {
  constructor(private readonly rls: PrismaRlsService) {}

  /** Tasks ordered by priority (open first). `filter='pending'` hides done. */
  async list(
    userId: string,
    filter: 'pending' | 'all' = 'all',
  ): Promise<TaskResponse[]> {
    const rows = await this.rls.withUser(userId, (tx) =>
      tx.node.findMany({
        where: { userId, type: 'task', deletedAt: null },
        select: {
          id: true,
          title: true,
          attributes: true,
          origin: true,
          createdAt: true,
        },
      }),
    );
    let tasks = rows.map(toTaskResponse);
    if (filter === 'pending') {
      tasks = tasks.filter((t) => !t.done);
    }
    return tasks.sort(compareTasks);
  }

  /** Create a task manually. */
  async create(userId: string, dto: CreateTaskDto): Promise<TaskResponse> {
    const attributes: Prisma.InputJsonValue = {
      done: false,
      done_at: null,
      priority: dto.priority ?? 'medium',
      due_at: dto.dueAt ?? null,
      ...(dto.area ? { area: dto.area } : {}),
    };
    const node = await this.rls.withUser(userId, (tx) =>
      tx.node.create({
        data: {
          userId,
          type: 'task',
          title: dto.title.trim(),
          origin: 'manual_text',
          status: 'processed',
          attributes,
        },
        select: {
          id: true,
          title: true,
          attributes: true,
          origin: true,
          createdAt: true,
        },
      }),
    );
    return toTaskResponse(node);
  }

  /** Patch a task: any of done / priority / due date / title / area. */
  async update(
    userId: string,
    id: string,
    dto: UpdateTaskDto,
  ): Promise<TaskResponse> {
    return this.rls.withUser(userId, async (tx) => {
      const existing = await tx.node.findFirst({
        where: { id, userId, type: 'task', deletedAt: null },
        select: { id: true, title: true, attributes: true },
      });
      if (!existing) {
        throw new NotFoundException({
          code: 'not_found',
          message: 'Task not found.',
        });
      }

      const current = (existing.attributes ?? {}) as Record<string, unknown>;
      const next: Record<string, unknown> = { ...current };

      if (dto.done !== undefined) {
        next.done = dto.done;
        next.done_at = dto.done ? new Date().toISOString() : null;
      }
      if (dto.priority !== undefined) next.priority = dto.priority;
      if (dto.dueAt !== undefined) next.due_at = dto.dueAt; // null clears it
      if (dto.area !== undefined) {
        if (dto.area === null) delete next.area;
        else next.area = dto.area;
      }

      const data: Prisma.NodeUpdateInput = {
        attributes: next as Prisma.InputJsonValue,
      };
      if (dto.title !== undefined) data.title = dto.title.trim();

      const updated = await tx.node.update({
        where: { id },
        data,
        select: {
          id: true,
          title: true,
          attributes: true,
          origin: true,
          createdAt: true,
        },
      });
      return toTaskResponse(updated);
    });
  }
}
