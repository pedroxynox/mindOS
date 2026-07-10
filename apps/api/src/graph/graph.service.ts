import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaRlsService } from '../prisma/prisma-rls.service';
import {
  CaptureEntitiesResponse,
  GraphNodeResponse,
  GraphSummaryResponse,
  toGraphEdge,
  toGraphNode,
} from './graph.mapper';
import { ListNodesQueryDto } from './dto/list-nodes-query.dto';

/** A page of derived nodes returned by the list endpoint. */
export interface GraphNodeListPage {
  data: GraphNodeResponse[];
  next_cursor: string | null;
}

/** Provenance edge the pipeline writes from every derived node to its capture. */
const DERIVED_FROM = 'derived_from';

/**
 * Read-only access to the AI-derived knowledge graph (design.md §7). Every read
 * runs inside `PrismaRlsService.withUser`, so PostgreSQL RLS scopes rows to the
 * caller — the client can only ever see its own knowledge. Captures (raw input)
 * are intentionally excluded here; they have their own `/v1/captures` API.
 */
@Injectable()
export class GraphService {
  constructor(private readonly rls: PrismaRlsService) {}

  /** Count of derived (non-capture, non-deleted) nodes per type. */
  async summary(userId: string): Promise<GraphSummaryResponse> {
    const grouped = await this.rls.withUser(userId, (tx) =>
      tx.node.groupBy({
        by: ['type'],
        where: { userId, deletedAt: null, type: { not: 'capture' } },
        _count: { _all: true },
      }),
    );

    const counts: Record<string, number> = {};
    let total = 0;
    for (const row of grouped) {
      const n = row._count._all;
      counts[row.type] = n;
      total += n;
    }
    return { counts, total };
  }

  /** Cursor-paginated list of the caller's derived nodes of one type. */
  async listNodes(
    userId: string,
    query: ListNodesQueryDto,
  ): Promise<GraphNodeListPage> {
    if (query.type === 'capture') {
      throw new BadRequestException({
        code: 'validation_error',
        message: 'Use /v1/captures to list captures.',
      });
    }

    const take = query.limit;
    const where: Prisma.NodeWhereInput = {
      userId,
      type: query.type,
      deletedAt: null,
    };

    const rows = await this.rls.withUser(userId, (tx) =>
      tx.node.findMany({
        where,
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

    return { data: rows.map(toGraphNode), next_cursor: nextCursor };
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
      if (!capture) {
        throw new NotFoundException({
          code: 'not_found',
          message: 'Capture not found.',
        });
      }

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
}
