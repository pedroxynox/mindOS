import {
  Controller,
  Get,
  Param,
  ParseUUIDPipe,
  Query,
  UseGuards,
} from '@nestjs/common';
import { AuthenticatedUser } from '../auth/jwt-auth.guard';
import { CurrentUser } from '../auth/current-user.decorator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { ListNodesQueryDto } from './dto/list-nodes-query.dto';
import {
  CaptureEntitiesResponse,
  GraphSummaryResponse,
} from './graph.mapper';
import { GraphNodeListPage, GraphService } from './graph.service';

/**
 * Read-only knowledge-graph endpoints (design.md §7). All routes require a valid
 * Bearer token; the owner `user_id` comes from the token, never the request.
 * The global `v1` prefix makes these `/v1/graph/...`.
 */
@UseGuards(JwtAuthGuard)
@Controller('graph')
export class GraphController {
  constructor(private readonly graph: GraphService) {}

  /** Counts of derived nodes per type — powers the home overview. */
  @Get('summary')
  summary(
    @CurrentUser() user: AuthenticatedUser,
  ): Promise<GraphSummaryResponse> {
    return this.graph.summary(user.id);
  }

  /** Cursor-paginated list of derived nodes of one type (?type=task|person|...). */
  @Get('nodes')
  listNodes(
    @CurrentUser() user: AuthenticatedUser,
    @Query() query: ListNodesQueryDto,
  ): Promise<GraphNodeListPage> {
    return this.graph.listNodes(user.id, query);
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
