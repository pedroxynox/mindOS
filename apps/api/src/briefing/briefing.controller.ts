import { Controller, Get, UseGuards } from '@nestjs/common';
import { CurrentUser } from '../auth/current-user.decorator';
import { AuthenticatedUser, JwtAuthGuard } from '../auth/jwt-auth.guard';
import { BriefingResponse } from './briefing.mapper';
import { BriefingService } from './briefing.service';

/**
 * Daily Briefing endpoint (`GET /v1/briefing`). Requires a valid Bearer token;
 * the owner comes from the token, never the request body.
 */
@UseGuards(JwtAuthGuard)
@Controller('briefing')
export class BriefingController {
  constructor(private readonly briefing: BriefingService) {}

  @Get()
  get(@CurrentUser() user: AuthenticatedUser): Promise<BriefingResponse> {
    return this.briefing.build(user.id);
  }
}
