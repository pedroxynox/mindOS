import { Node } from '@prisma/client';

/**
 * Wire shapes for the Daily Briefing (`GET /v1/briefing`). The briefing is a
 * proactive glance at what matters now: how many tasks the user has (with a few
 * recent ones) and the events coming up. Snake_case per API conventions (#04).
 *
 * The natural-language greeting/headline is composed on the CLIENT so it can use
 * the device's local time and locale; the server only returns structured data.
 */
export interface BriefingItem {
  id: string;
  title: string | null;
}

export interface BriefingEvent {
  id: string;
  title: string | null;
  occurred_at: string;
}

export interface BriefingResponse {
  generated_at: string;
  /** Total number of task nodes the user has. */
  task_total: number;
  /** A few most-recent tasks (title preview). */
  tasks: BriefingItem[];
  /** Upcoming events (occurring today or later), soonest first. */
  upcoming_events: BriefingEvent[];
}

export function toBriefingItem(
  node: Pick<Node, 'id' | 'title'>,
): BriefingItem {
  return { id: node.id, title: node.title };
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
