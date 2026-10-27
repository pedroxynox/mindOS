import {
  Body,
  Controller,
  Get,
  HttpCode,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import { CurrentUser } from '../auth/current-user.decorator';
import { AuthenticatedUser, JwtAuthGuard } from '../auth/jwt-auth.guard';
import { FeedbackDto, FeedbackTargetDto } from './dto/feedback.dto';
import {
  FeedbackResponse,
  FeedbackService,
  FeedbackVoteResponse,
} from './feedback.service';

/** `/v1/feedback` — 👍/👎 on captures, answers, the briefing and nodes. */
@UseGuards(JwtAuthGuard)
@Controller('feedback')
export class FeedbackController {
  constructor(private readonly feedback: FeedbackService) {}

  /** Record (or replace) the caller's vote on a target. */
  @Post()
  @HttpCode(201)
  record(
    @CurrentUser() user: AuthenticatedUser,
    @Body() dto: FeedbackDto,
  ): Promise<FeedbackResponse> {
    return this.feedback.record(user.id, dto);
  }

  /** The caller's current vote, so the UI can show it again. */
  @Get()
  vote(
    @CurrentUser() user: AuthenticatedUser,
    @Query() target: FeedbackTargetDto,
  ): Promise<FeedbackVoteResponse> {
    return this.feedback.vote(user.id, target);
  }
}
