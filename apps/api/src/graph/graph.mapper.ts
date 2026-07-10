import { Edge, Node } from '@prisma/client';

/**
 * Public wire shapes for the read-only graph endpoints (design.md §7, API
 * conventions #04: snake_case). These expose the AI-derived knowledge — the
 * people/tasks/projects/events/topics the understanding pipeline extracted —
 * so the client can finally SHOW what the brain understood.
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

/** A semantic relationship between two derived nodes. */
export interface GraphEdgeResponse {
  source: string;
  target: string;
  /** e.g. 'assigned_to', 'relates_to', 'mentions', 'derived_from'. */
  type: string;
  confidence: number | null;
}

/** Count of derived nodes per type, for the home overview. */
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

type GraphEdgeFields = Pick<
  Edge,
  'sourceNodeId' | 'targetNodeId' | 'type' | 'confidence'
>;

export function toGraphEdge(edge: GraphEdgeFields): GraphEdgeResponse {
  return {
    source: edge.sourceNodeId,
    target: edge.targetNodeId,
    type: edge.type,
    confidence: edge.confidence ?? null,
  };
}
