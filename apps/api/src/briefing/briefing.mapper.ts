import { Node } from '@prisma/client';
import { TaskPriority } from '../tasks/dto/create-task.dto';

/**
 * Wire shapes for the Daily Briefing (`GET /v1/briefing`). The briefing is a
 * proactive glance at what matters now: the PENDING tasks that matter most,
 * what is overdue or due today, who is waiting on the user, and the events
 * coming up. Snake_case per API conventions (#04).
 *
 * The natural-language greeting/headline is composed on the CLIENT so it can use
 * the device's locale; the server only returns structured data.
 */
export interface BriefingTask {
  id: string;
  title: string | null;
  priority: TaskPriority;
  due_at: string | null;
}

export interface BriefingEvent {
  id: string;
  title: string | null;
  occurred_at: string;
}

/** A person the user has pending tasks with (via `assigned_to` edges). */
export interface BriefingPerson {
  name: string;
  pending_count: number;
}

export interface BriefingResponse {
  generated_at: string;
  /** Number of PENDING (not done) tasks. */
  task_total: number;
  /** Pending tasks whose due date has already passed. */
  overdue_count: number;
  /** Pending tasks due later today (not yet overdue). */
  due_today_count: number;
  /** The most important pending tasks, in the same order as `/v1/tasks`. */
  tasks: BriefingTask[];
  /** Upcoming events (occurring today or later), soonest first. */
  upcoming_events: BriefingEvent[];
  /** People with pending tasks, most pending first. */
  people: BriefingPerson[];
}

export function toBriefingEvent(
  node: Pick<Node, 'id' | 'title' | 'occurredAt'>,
): BriefingEvent {
  return {
    id: node.id,
    title: node.title,
    // Only events with a date are selected, so occurredAt is non-null here.
    occurred_at: (node.occurredAt as Date).toISOString(),
  };
}
