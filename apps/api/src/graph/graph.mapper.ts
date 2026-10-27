import { Edge, Node } from '@prisma/client';
import { EntityGroup } from './entity-groups';

/**
 * Public wire shapes for the graph endpoints (design.md §7, API conventions
 * #04: snake_case). These expose the AI-derived knowledge — the
 * people/tasks/projects/events/topics the understanding pipeline extracted —
 * so the client can SHOW what the brain understood and let the user fix it.
 */
export interface GraphNodeResponse {
  id: string;
  type: string;
  title: string | null;
  /** AI confidence in [0,1]; null for user-authored nodes. */
  confidence: number | null;
  occurred_at: string | null;
  created_at: string;
}

/**
 * A list item of `GET /v1/graph/nodes`. For grouped types (people, projects,
 * events, topics, decisions) one item is one entity across captures:
 * `mentions` counts them and `created_at` is the latest mention. Tasks and
 * notes are always `mentions: 1`.
 */
export interface GraphEntityResponse extends GraphNodeResponse {
  mentions: number;
}

/** A semantic relationship between two derived nodes. */
export interface GraphEdgeResponse {
  id: string;
  source: string;
  target: string;
  /** e.g. 'assigned_to', 'relates_to', 'mentions'. */
  type: string;
  confidence: number | null;
  /** True once the user confirmed it (FR-2.4). */
  user_confirmed: boolean;
}

/** Result of `PATCH /v1/graph/edges/:id`. */
export interface GraphEdgeReviewResponse extends GraphEdgeResponse {
  /** True when the user rejected it (the edge is soft-deleted). */
  deleted: boolean;
}

/** Result of `PATCH /v1/graph/nodes/:id`. */
export interface GraphRenameResponse extends GraphNodeResponse {
  /** How many mentions were renamed (1 for `scope=node`). */
  updated: number;
}

/** Count of distinct entities per type, for the home overview. */
export interface GraphSummaryResponse {
  counts: Record<string, number>;
  total: number;
}

/** What the brain extracted from a single capture. */
export interface CaptureEntitiesResponse {
  capture_id: string;
  /** Pipeline status so the UI can show a "still thinking" state. */
  status: 'raw' | 'processing' | 'processed' | 'failed';
  nodes: GraphNodeResponse[];
  edges: GraphEdgeResponse[];
}

/** A capture where the entity appears. */
export interface EntityCaptureResponse {
  id: string;
  snippet: string;
  modality: string;
  occurred_at: string | null;
  created_at: string;
}

/** Another entity seen together with this one. */
export interface RelatedEntityResponse {
  id: string;
  type: string;
  title: string | null;
  /** Captures (or direct links) shared with the entity. */
  mentions: number;
}

/** A task linked to the entity (same capture or a direct edge). */
export interface EntityTaskResponse {
  id: string;
  title: string | null;
  done: boolean;
  priority: string;
  due_at: string | null;
}

/** `GET /v1/graph/nodes/:id` — one entity with its context. */
export interface EntityDetailResponse {
  id: string;
  type: string;
  title: string | null;
  mentions: number;
  /** Ids of every mention (the requested id is always included). */
  node_ids: string[];
  confidence: number | null;
  user_edited: boolean;
  first_seen_at: string;
  last_seen_at: string;
  captures: EntityCaptureResponse[];
  related: RelatedEntityResponse[];
  tasks: EntityTaskResponse[];
}

type GraphNodeFields = Pick<
  Node,
  'id' | 'type' | 'title' | 'confidence' | 'occurredAt' | 'createdAt'
>;

export function toGraphNode(node: GraphNodeFields): GraphNodeResponse {
  return {
    id: node.id,
    type: node.type,
    title: node.title,
    confidence: node.confidence ?? null,
    occurred_at: node.occurredAt ? node.occurredAt.toISOString() : null,
    created_at: node.createdAt.toISOString(),
  };
}

export function toGraphEntity(group: EntityGroup): GraphEntityResponse {
  return {
    id: group.representativeId,
    type: group.type,
    title: group.title,
    confidence: group.confidence,
    occurred_at: group.occurredAt ? group.occurredAt.toISOString() : null,
    created_at: group.lastSeenAt.toISOString(),
    mentions: group.mentions,
  };
}

type GraphEdgeFields = Pick<
  Edge,
  | 'id'
  | 'sourceNodeId'
  | 'targetNodeId'
  | 'type'
  | 'confidence'
  | 'userConfirmed'
>;

export function toGraphEdge(edge: GraphEdgeFields): GraphEdgeResponse {
  return {
    id: edge.id,
    source: edge.sourceNodeId,
    target: edge.targetNodeId,
    type: edge.type,
    confidence: edge.confidence ?? null,
    user_confirmed: edge.userConfirmed,
  };
}
