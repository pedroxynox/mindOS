import { Node } from '@prisma/client';

/**
 * Public shape returned by the capture endpoints (design.md §7.1). Uses
 * snake_case per the API conventions inherited from #04.
 *
 * `content` (the text, or the transcription of a voice note) and `modality`
 * were added additively so any device can render the user's capture history
 * from the server, not only from its local outbox.
 */
export interface CaptureResponse {
  capture_id: string;
  status: 'raw' | 'processing' | 'processed' | 'failed';
  created_at: string;
  occurred_at: string | null;
  content: string | null;
  modality: 'text' | 'voice';
}

/** Fields of a Node required to build a CaptureResponse. */
type CaptureNode = Pick<
  Node,
  'id' | 'status' | 'createdAt' | 'occurredAt' | 'body' | 'origin'
>;

/** Map a persisted capture Node onto the wire response. */
export function toCaptureResponse(node: CaptureNode): CaptureResponse {
  return {
    capture_id: node.id,
    status: node.status,
    created_at: node.createdAt.toISOString(),
    occurred_at: node.occurredAt ? node.occurredAt.toISOString() : null,
    content: node.body ?? null,
    modality: node.origin === 'voice' ? 'voice' : 'text',
  };
}
