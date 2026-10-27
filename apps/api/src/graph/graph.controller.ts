import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  Param,
  ParseUUIDPipe,
  Patch,
  Query,
  UseGuards,
} from '@nestjs/common';
import { AuthenticatedUser } from '../auth/jwt-auth.guard';
import { CurrentUser } from '../auth/current-user.decorator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import {
  NodeScopeQueryDto,
  RenameNodeDto,
  ReviewEdgeDto,
} from './dto/correct-graph.dto';
import { ListNodesQueryDto } from './dto/list-nodes-query.dto';
import {
  CaptureEntitiesResponse,
  EntityDetailResponse,
  GraphEdgeReviewResponse,
  GraphRenameResponse,
  GraphSummaryResponse,
} from './graph.mapper';
import { GraphNodeListPage, GraphService } from './graph.service';

/**
 * Knowledge-graph endpoints (design.md §7) plus the user's corrections
 * (FR-2.4, mejoras-v2 §D). All routes require a valid Bearer token; the owner
 * `user_id` comes from the token, never the request. The global `v1` prefix
 * makes these `/v1/graph/...`.
 */
@UseGuards(JwtAuthGuard)
@Controller('graph')
export class GraphController {
  constructor(private readonly graph: GraphService) {}

  /** Distinct entities per type — powers the home overview. */
  @Get('summary')
  summary(
    @CurrentUser() user: AuthenticatedUser,
  ): Promise<GraphSummaryResponse> {
    return this.graph.summary(user.id);
  }

  /** One type of derived knowledge (?type=task|person|...), people etc. grouped. */
  @Get('nodes')
  listNodes(
    @CurrentUser() user: AuthenticatedUser,
    @Query() query: ListNodesQueryDto,
  ): Promise<GraphNodeListPage> {
    return this.graph.listNodes(user.id, query);
  }

  /** An entity with its captures, related entities and tasks. */
  @Get('nodes/:id')
  entity(
    @CurrentUser() user: AuthenticatedUser,
    @Param('id', ParseUUIDPipe) id: string,
  ): Promise<EntityDetailResponse> {
    return this.graph.entity(user.id, id);
  }

  /** Rename one mention (`scope=node`, default) or the whole entity. */
  @Patch('nodes/:id')
  rename(
    @CurrentUser() user: AuthenticatedUser,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: RenameNodeDto,
  ): Promise<GraphRenameResponse> {
    return this.graph.rename(user.id, id, dto.title, dto.scope);
  }

  /** Forget one mention (`?scope=node`, default) or the whole entity. */
  @Delete('nodes/:id')
  @HttpCode(204)
  remove(
    @CurrentUser() user: AuthenticatedUser,
    @Param('id', ParseUUIDPipe) id: string,
    @Query() query: NodeScopeQueryDto,
  ): Promise<void> {
    return this.graph.remove(user.id, id, query.scope);
  }

  /** Confirm (`true`) or reject (`false`, soft delete) a connection. */
  @Patch('edges/:id')
  reviewEdge(
    @CurrentUser() user: AuthenticatedUser,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: ReviewEdgeDto,
  ): Promise<GraphEdgeReviewResponse> {
    return this.graph.reviewEdge(user.id, id, dto.confirmed);
  }

  /** What the brain extracted from one capture (entities + connections). */
  @Get('captures/:id/entities')
  captureEntities(
    @CurrentUser() user: AuthenticatedUser,
    @Param('id', ParseUUIDPipe) id: string,
  ): Promise<CaptureEntitiesResponse> {
    return this.graph.captureEntities(user.id, id);
  }
}
