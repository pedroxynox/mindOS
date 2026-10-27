import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { NodeType, Prisma } from '@prisma/client';
import { PrismaRlsService } from '../prisma/prisma-rls.service';
import { compareTasks, toTaskResponse } from '../tasks/tasks.mapper';
import { CorrectionScope } from './dto/correct-graph.dto';
import { ListNodesQueryDto } from './dto/list-nodes-query.dto';
import {
  entityKey,
  groupEntities,
  isGroupedType,
  sameEntity,
  snippet,
} from './entity-groups';
import {
  CaptureEntitiesResponse,
  EntityDetailResponse,
  GraphEdgeReviewResponse,
  GraphEntityResponse,
  GraphRenameResponse,
  GraphSummaryResponse,
  toGraphEdge,
  toGraphEntity,
  toGraphNode,
} from './graph.mapper';

/** A page of derived nodes returned by the list endpoint. */
export interface GraphNodeListPage {
  data: GraphEntityResponse[];
  next_cursor: string | null;
}

/** Provenance edge the pipeline writes from every derived node to its capture. */
const DERIVED_FROM = 'derived_from';

/** Caps of the entity screen (newest / most related first). */
const ENTITY_CAPTURES = 20;
const ENTITY_RELATED = 12;
const ENTITY_TASKS = 20;

const NODE_FIELDS = {
  id: true,
  type: true,
  title: true,
  confidence: true,
  occurredAt: true,
  createdAt: true,
} as const;
const CORRECTABLE_FIELDS = { ...NODE_FIELDS, attributes: true } as const;

type Tx = Prisma.TransactionClient;
type CorrectableNode = Prisma.NodeGetPayload<{
  select: typeof CORRECTABLE_FIELDS;
}>;

function notFound(message: string): NotFoundException {
  return new NotFoundException({ code: 'not_found', message });
}

function badRequest(message: string): BadRequestException {
  return new BadRequestException({ code: 'validation_error', message });
}

function unique<T>(values: T[]): T[] {
  return [...new Set(values)];
}

/** Offset cursor of the grouped lists ("20" = skip 20 entities). */
function parseOffset(cursor: string | undefined): number {
  if (cursor === undefined || cursor === '') return 0;
  if (!/^\d{1,6}$/.test(cursor)) throw badRequest('Invalid cursor.');
  return Number(cursor);
}

/**
 * The AI-derived knowledge graph (design.md §7) and the user's corrections to
 * it (FR-2.4, mejoras-v2 §D). Every query runs inside
 * `PrismaRlsService.withUser`, so PostgreSQL RLS scopes rows to the caller.
 * Captures (raw input) are excluded; they have their own `/v1/captures` API.
 *
 * Corrections are soft: renames keep the row (flagged `user_edited`) and
 * removals set `deleted_at` on the node and its edges. The worker's upserts
 * only touch `confidence` on conflict, so reprocessing a capture never
 * resurrects or renames what the user fixed.
 */
@Injectable()
export class GraphService {
  constructor(private readonly rls: PrismaRlsService) {}

  /** Distinct entities per type (tasks one by one); notes are excluded. */
  async summary(userId: string): Promise<GraphSummaryResponse> {
    const rows = await this.rls.withUser(userId, (tx) =>
      tx.node.findMany({
        // Captures are raw input and notes include Growth items (goals,
        // habits, reflections), which have their own section.
        where: {
          userId,
          deletedAt: null,
          type: { notIn: ['capture', 'note'] },
        },
        select: { id: true, type: true, title: true },
      }),
    );

    const keys = new Map<NodeType, Set<string>>();
    for (const row of rows) {
      const key = isGroupedType(row.type) ? entityKey(row) : row.id;
      const set = keys.get(row.type) ?? new Set<string>();
      set.add(key);
      keys.set(row.type, set);
    }

    const counts: Record<string, number> = {};
    let total = 0;
    for (const [type, set] of keys) {
      counts[type] = set.size;
      total += set.size;
    }
    return { counts, total };
  }

  /**
   * One type of derived knowledge. People, projects, events, topics and
   * decisions come grouped by name (`mentions`, offset cursor); tasks and
   * notes are listed row by row (id cursor).
   */
  async listNodes(
    userId: string,
    query: ListNodesQueryDto,
  ): Promise<GraphNodeListPage> {
    if (query.type === 'capture') {
      throw badRequest('Use /v1/captures to list captures.');
    }
    if (isGroupedType(query.type)) return this.listEntities(userId, query);

    const take = query.limit;
    const rows = await this.rls.withUser(userId, (tx) =>
      tx.node.findMany({
        where: { userId, type: query.type, deletedAt: null },
        orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
        take: take + 1,
        ...(query.cursor ? { cursor: { id: query.cursor }, skip: 1 } : {}),
      }),
    );

    let nextCursor: string | null = null;
    if (rows.length > take) {
      const overflow = rows.pop();
      nextCursor = overflow ? overflow.id : null;
    }

    return {
      data: rows.map((row) => ({ ...toGraphNode(row), mentions: 1 })),
      next_cursor: nextCursor,
    };
  }

  private async listEntities(
    userId: string,
    query: ListNodesQueryDto,
  ): Promise<GraphNodeListPage> {
    const offset = parseOffset(query.cursor);
    const rows = await this.rls.withUser(userId, (tx) =>
      tx.node.findMany({
        where: { userId, type: query.type, deletedAt: null },
        select: NODE_FIELDS,
      }),
    );
    const groups = groupEntities(rows);
    const end = offset + query.limit;
    return {
      data: groups.slice(offset, end).map(toGraphEntity),
      next_cursor: end < groups.length ? String(end) : null,
    };
  }

  /**
   * One entity with its context: every mention, the captures where it
   * appears, the entities seen with it and the related tasks (same capture
   * or a direct edge). Any member id resolves the whole entity.
   */
  async entity(userId: string, id: string): Promise<EntityDetailResponse> {
    return this.rls.withUser(userId, async (tx) => {
      const node = await this.findCorrectable(tx, userId, id);
      const members = isGroupedType(node.type)
        ? sameEntity(
            node,
            await tx.node.findMany({
              where: { userId, type: node.type, deletedAt: null },
              select: CORRECTABLE_FIELDS,
            }),
          )
        : [node];
      const group = groupEntities(members)[0];
      const memberIds = new Set(group.nodeIds);
      const ids = [...memberIds];

      const provenance = await tx.edge.findMany({
        where: {
          userId,
          type: DERIVED_FROM,
          deletedAt: null,
          sourceNodeId: { in: ids },
        },
        select: { targetNodeId: true },
      });
      const captureIds = unique(provenance.map((e) => e.targetNodeId));

      const [captures, together, links] = await Promise.all([
        captureIds.length
          ? tx.node.findMany({
              where: {
                userId,
                type: 'capture',
                deletedAt: null,
                id: { in: captureIds },
              },
              orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
              take: ENTITY_CAPTURES,
              select: {
                id: true,
                body: true,
                origin: true,
                occurredAt: true,
                createdAt: true,
              },
            })
          : Promise.resolve([]),
        // Everything else the same captures produced.
        captureIds.length
          ? tx.edge.findMany({
              where: {
                userId,
                type: DERIVED_FROM,
                deletedAt: null,
                targetNodeId: { in: captureIds },
                sourceNodeId: { notIn: ids },
              },
              select: { sourceNodeId: true },
            })
          : Promise.resolve([]),
        // Direct semantic links (e.g. task -assigned_to-> person).
        tx.edge.findMany({
          where: {
            userId,
            deletedAt: null,
            type: { not: DERIVED_FROM },
            OR: [{ sourceNodeId: { in: ids } }, { targetNodeId: { in: ids } }],
          },
          select: { sourceNodeId: true, targetNodeId: true },
        }),
      ]);

      const neighbourIds = unique([
        ...together.map((e) => e.sourceNodeId),
        ...links.map((e) =>
          memberIds.has(e.sourceNodeId) ? e.targetNodeId : e.sourceNodeId,
        ),
      ]).filter((n) => !memberIds.has(n));
      const neighbours = neighbourIds.length
        ? await tx.node.findMany({
            where: {
              userId,
              deletedAt: null,
              id: { in: neighbourIds },
              type: { not: 'capture' },
            },
            select: { ...CORRECTABLE_FIELDS, origin: true },
          })
        : [];

      const related = groupEntities(
        neighbours.filter((n) => isGroupedType(n.type)),
      )
        .filter((g) => g.key !== group.key)
        .sort(
          (a, b) =>
            b.mentions - a.mentions ||
            b.lastSeenAt.getTime() - a.lastSeenAt.getTime(),
        )
        .slice(0, ENTITY_RELATED)
        .map((g) => ({
          id: g.representativeId,
          type: g.type,
          title: g.title,
          mentions: g.mentions,
        }));

      const tasks = neighbours
        .filter((n) => n.type === 'task')
        .map(toTaskResponse)
        .sort(compareTasks)
        .slice(0, ENTITY_TASKS)
        .map((t) => ({
          id: t.id,
          title: t.title,
          done: t.done,
          priority: t.priority,
          due_at: t.due_at,
        }));

      return {
        id: node.id,
        type: group.type,
        title: group.title,
        mentions: group.mentions,
        node_ids: group.nodeIds,
        confidence: group.confidence,
        user_edited: members.some(
          (m) =>
            (m.attributes as Record<string, unknown> | null)?.user_edited ===
            true,
        ),
        first_seen_at: group.firstSeenAt.toISOString(),
        last_seen_at: group.lastSeenAt.toISOString(),
        captures: captures.map((c) => ({
          id: c.id,
          snippet: snippet(c.body),
          modality: c.origin === 'voice' ? 'voice' : 'text',
          occurred_at: c.occurredAt ? c.occurredAt.toISOString() : null,
          created_at: c.createdAt.toISOString(),
        })),
        related,
        tasks,
      };
    });
  }

  /**
   * Rename what the AI understood. `scope=entity` renames every mention of the
   * same name; `scope=node` fixes one capture (renaming into an existing name
   * merges it with that entity, since entities are grouped by name).
   */
  async rename(
    userId: string,
    id: string,
    title: string,
    scope: CorrectionScope,
  ): Promise<GraphRenameResponse> {
    return this.rls.withUser(userId, async (tx) => {
      const node = await this.findCorrectable(tx, userId, id);
      const ids = await this.scopeIds(tx, userId, node, scope);
      const updated = await tx.$executeRaw`
        UPDATE nodes
           SET title = ${title},
               attributes = attributes || '{"user_edited": true}'::jsonb,
               updated_at = now()
         WHERE user_id = ${userId}::uuid
           AND id = ANY(${ids}::uuid[])
           AND deleted_at IS NULL`;
      return { ...toGraphNode({ ...node, title }), updated };
    });
  }

  /** Forget a node (or every mention of the entity) and all its edges. */
  async remove(
    userId: string,
    id: string,
    scope: CorrectionScope,
  ): Promise<void> {
    await this.rls.withUser(userId, async (tx) => {
      const node = await this.findCorrectable(tx, userId, id);
      const ids = await this.scopeIds(tx, userId, node, scope);
      const now = new Date();
      await tx.node.updateMany({
        where: { userId, id: { in: ids }, deletedAt: null },
        data: { deletedAt: now },
      });
      await tx.edge.updateMany({
        where: {
          userId,
          deletedAt: null,
          OR: [{ sourceNodeId: { in: ids } }, { targetNodeId: { in: ids } }],
        },
        data: { deletedAt: now },
      });
    });
  }

  /** Confirm (keep, `user_confirmed`) or reject (soft-delete) a connection. */
  async reviewEdge(
    userId: string,
    id: string,
    confirmed: boolean,
  ): Promise<GraphEdgeReviewResponse> {
    return this.rls.withUser(userId, async (tx) => {
      const edge = await tx.edge.findFirst({
        where: { id, userId, deletedAt: null },
        select: { id: true, type: true },
      });
      if (!edge) throw notFound('Connection not found.');
      if (edge.type === DERIVED_FROM) {
        throw badRequest(
          'Provenance links cannot be reviewed; remove the item instead.',
        );
      }
      const row = await tx.edge.update({
        where: { id: edge.id },
        data: confirmed
          ? { userConfirmed: true }
          : { userConfirmed: false, deletedAt: new Date() },
      });
      return { ...toGraphEdge(row), deleted: !confirmed };
    });
  }

  /**
   * What the brain extracted from ONE capture: the derived nodes (linked to the
   * capture by a `derived_from` edge) plus the semantic edges among them.
   * Returns the capture's pipeline `status` so the UI can show progress.
   */
  async captureEntities(
    userId: string,
    captureId: string,
  ): Promise<CaptureEntitiesResponse> {
    return this.rls.withUser(userId, async (tx) => {
      const capture = await tx.node.findFirst({
        where: { id: captureId, userId, type: 'capture' },
        select: { id: true, status: true },
      });
      if (!capture) throw notFound('Capture not found.');

      // Provenance edges point FROM each derived node TO the capture.
      const provenance = await tx.edge.findMany({
        where: {
          userId,
          targetNodeId: captureId,
          type: DERIVED_FROM,
          deletedAt: null,
        },
        select: { sourceNodeId: true },
      });
      const nodeIds = provenance.map((e) => e.sourceNodeId);

      if (nodeIds.length === 0) {
        return {
          capture_id: capture.id,
          status: capture.status,
          nodes: [],
          edges: [],
        };
      }

      const [nodes, semanticEdges] = await Promise.all([
        tx.node.findMany({
          where: { userId, id: { in: nodeIds }, deletedAt: null },
          orderBy: [{ type: 'asc' }, { createdAt: 'asc' }],
        }),
        // Semantic edges between the extracted nodes (drop provenance edges).
        tx.edge.findMany({
          where: {
            userId,
            sourceNodeId: { in: nodeIds },
            targetNodeId: { in: nodeIds },
            type: { not: DERIVED_FROM },
            deletedAt: null,
          },
        }),
      ]);

      return {
        capture_id: capture.id,
        status: capture.status,
        nodes: nodes.map(toGraphNode),
        edges: semanticEdges.map(toGraphEdge),
      };
    });
  }

  /** A live, non-capture node of the caller, or 404/400. */
  private async findCorrectable(
    tx: Tx,
    userId: string,
    id: string,
  ): Promise<CorrectableNode> {
    const node = await tx.node.findFirst({
      where: { id, userId, deletedAt: null },
      select: CORRECTABLE_FIELDS,
    });
    if (!node) throw notFound('Node not found.');
    if (node.type === 'capture') {
      throw badRequest('Captures are managed through /v1/captures.');
    }
    return node;
  }

  /** Ids a correction applies to: the node, or every mention of its entity. */
  private async scopeIds(
    tx: Tx,
    userId: string,
    node: { id: string; type: NodeType; title: string | null },
    scope: CorrectionScope,
  ): Promise<string[]> {
    if (scope !== 'entity' || !isGroupedType(node.type)) return [node.id];
    const candidates = await tx.node.findMany({
      where: { userId, type: node.type, deletedAt: null },
      select: { id: true, type: true, title: true },
    });
    return sameEntity(node, candidates).map((m) => m.id);
  }
}
