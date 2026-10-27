import { NodeType } from '@prisma/client';
import { normalizeLabel } from '../common/text';

/**
 * The pipeline writes one node per (capture, label): "Marcos" mentioned in
 * five captures is five `person` rows. For the user that is ONE person, so the
 * graph API groups nodes of the same type by normalised name (mejoras-v2 §D).
 *
 * Tasks and notes are free text and stay one-per-row.
 */
export const GROUPED_TYPES: ReadonlySet<NodeType> = new Set<NodeType>([
  'person',
  'project',
  'event',
  'topic',
  'decision',
]);

export function isGroupedType(type: NodeType): boolean {
  return GROUPED_TYPES.has(type);
}

export interface GroupableNode {
  id: string;
  type: NodeType;
  title: string | null;
  confidence: number | null;
  occurredAt: Date | null;
  createdAt: Date;
}

/** One entity as the user sees it: every mention of the same name. */
export interface EntityGroup {
  key: string;
  type: NodeType;
  /** Title of the most recent mention (the user's latest wording wins). */
  title: string | null;
  /** Most recent mention — the id the list hands out. */
  representativeId: string;
  /** All member ids, newest first. */
  nodeIds: string[];
  mentions: number;
  confidence: number | null;
  occurredAt: Date | null;
  firstSeenAt: Date;
  lastSeenAt: Date;
}

/** Group key: type + normalised title. Untitled nodes never merge. */
export function entityKey(
  node: Pick<GroupableNode, 'id' | 'type' | 'title'>,
): string {
  const norm = node.title ? normalizeLabel(node.title) : '';
  return norm ? `${node.type}\u001f${norm}` : `${node.type}\u001f#${node.id}`;
}

function newer(a: GroupableNode, b: GroupableNode): boolean {
  const diff = a.createdAt.getTime() - b.createdAt.getTime();
  return diff !== 0 ? diff > 0 : a.id > b.id;
}

/**
 * Collapse nodes into entities, most recently mentioned first (ties by title,
 * then key, so the order — and the offset cursor — is deterministic).
 */
export function groupEntities(nodes: GroupableNode[]): EntityGroup[] {
  const groups = new Map<
    string,
    { members: GroupableNode[]; latest: GroupableNode }
  >();
  for (const node of nodes) {
    const key = entityKey(node);
    const group = groups.get(key);
    if (!group) {
      groups.set(key, { members: [node], latest: node });
      continue;
    }
    group.members.push(node);
    if (newer(node, group.latest)) group.latest = node;
  }

  const result: EntityGroup[] = [];
  for (const [key, { members, latest }] of groups) {
    members.sort((a, b) => (newer(a, b) ? -1 : newer(b, a) ? 1 : 0));
    const confidences = members
      .map((m) => m.confidence)
      .filter((c): c is number => c !== null);
    const occurred = members
      .map((m) => m.occurredAt)
      .filter((d): d is Date => d !== null)
      .sort((a, b) => b.getTime() - a.getTime());
    result.push({
      key,
      type: latest.type,
      title: latest.title,
      representativeId: latest.id,
      nodeIds: members.map((m) => m.id),
      mentions: members.length,
      confidence: confidences.length ? Math.max(...confidences) : null,
      occurredAt: occurred[0] ?? null,
      firstSeenAt: members[members.length - 1].createdAt,
      lastSeenAt: latest.createdAt,
    });
  }

  return result.sort((a, b) => {
    const diff = b.lastSeenAt.getTime() - a.lastSeenAt.getTime();
    if (diff !== 0) return diff;
    const byTitle = (a.title ?? '').localeCompare(b.title ?? '');
    return byTitle !== 0 ? byTitle : a.key.localeCompare(b.key);
  });
}

/** Members of the entity that `node` belongs to (just itself if ungrouped). */
export function sameEntity<
  T extends Pick<GroupableNode, 'id' | 'type' | 'title'>,
>(node: T, candidates: T[]): T[] {
  if (!isGroupedType(node.type)) return [node];
  const key = entityKey(node);
  const members = candidates.filter((c) => entityKey(c) === key);
  return members.some((m) => m.id === node.id) ? members : [node, ...members];
}

/** Short preview of a capture body for the entity screen. */
export function snippet(body: string | null, max = 160): string {
  const text = (body ?? '').replace(/\s+/g, ' ').trim();
  if (text.length <= max) return text;
  const cut = text.slice(0, max);
  const space = cut.lastIndexOf(' ');
  return `${(space > max * 0.6 ? cut.slice(0, space) : cut).trimEnd()}…`;
}
