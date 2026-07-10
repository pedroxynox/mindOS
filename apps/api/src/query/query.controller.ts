import { Body, Controller, Post, UseGuards } from '@nestjs/common';
import { CurrentUser } from '../auth/current-user.decorator';
import { AuthenticatedUser, JwtAuthGuard } from '../auth/jwt-auth.guard';
import { AskDto } from './dto/ask.dto';
import { QueryResponse } from './query.mapper';
import { QueryService } from './query.service';

/**
 * Ask-mindOS endpoint (`POST /v1/query`). Requires a valid Bearer token; the
 * owner comes from the token and is forwarded to the AI service, never trusted
 * from the request body.
 */
@UseGuards(JwtAuthGuard)
@Controller('query')
export class QueryController {
  constructor(private readonly query: QueryService) {}

  @Post()
  ask(
    @CurrentUser() user: AuthenticatedUser,
    @Body() dto: AskDto,
  ): Promise<QueryResponse> {
    return this.query.ask(user.id, dto.question);
  }
}
