import { Node } from '@prisma/client';
import { TaskPriority } from './dto/create-task.dto';

/**
 * Public wire shape for a task (`/v1/tasks`). Tasks are `node` rows of type
 * `task`; their lifecycle lives in `attributes` (JSONB) so no schema migration
 * is needed: `{ done, done_at, priority, due_at, area }`. Snake_case per #04.
 */
export interface TaskResponse {
  id: string;
  title: string | null;
  done: boolean;
  done_at: string | null;
  priority: TaskPriority;
  due_at: string | null;
  area: string | null;
  /** 'ai' when extracted from a capture, 'manual_text' when user-created. */
  origin: string;
  created_at: string;
}

type TaskAttributes = {
  done?: unknown;
  done_at?: unknown;
  priority?: unknown;
  due_at?: unknown;
  area?: unknown;
};

const VALID_PRIORITIES: readonly string[] = ['high', 'medium', 'low'];

/** Numeric rank for ordering (high first). */
export function priorityRank(priority: TaskPriority): number {
  return priority === 'high' ? 0 : priority === 'medium' ? 1 : 2;
}

function readPriority(value: unknown): TaskPriority {
  return typeof value === 'string' && VALID_PRIORITIES.includes(value)
    ? (value as TaskPriority)
    : 'medium';
}

function readString(value: unknown): string | null {
  return typeof value === 'string' && value.length > 0 ? value : null;
}

export function toTaskResponse(
  node: Pick<
    Node,
    'id' | 'title' | 'attributes' | 'origin' | 'createdAt'
  >,
): TaskResponse {
  const attrs = (node.attributes ?? {}) as TaskAttributes;
  return {
    id: node.id,
    title: node.title,
    done: attrs.done === true,
    done_at: readString(attrs.done_at),
    priority: readPriority(attrs.priority),
    due_at: readString(attrs.due_at),
    area: readString(attrs.area),
    origin: node.origin,
    created_at: node.createdAt.toISOString(),
  };
}

/**
 * Deterministic ordering for the task list: open tasks first, then by priority,
 * then by soonest due date (tasks without a date last), then newest first.
 */
export function compareTasks(a: TaskResponse, b: TaskResponse): number {
  if (a.done !== b.done) return a.done ? 1 : -1;
  const pr = priorityRank(a.priority) - priorityRank(b.priority);
  if (pr !== 0) return pr;
  if (a.due_at !== b.due_at) {
    if (a.due_at === null) return 1;
    if (b.due_at === null) return -1;
    return a.due_at < b.due_at ? -1 : 1;
  }
  return a.created_at < b.created_at ? 1 : -1;
}
