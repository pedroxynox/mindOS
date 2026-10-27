import { Body, Controller, Get, Patch, UseGuards } from '@nestjs/common';
import { CurrentUser } from '../auth/current-user.decorator';
import { AuthenticatedUser, JwtAuthGuard } from '../auth/jwt-auth.guard';
import { UpdateMeDto } from './dto/update-me.dto';
import { MeResponse, UserSettingsService } from './user-settings.service';

/**
 * The signed-in user's profile and preferences (`/v1/me`). The app sends the
 * device timezone on start and lets the user pick a currency; every "today" and
 * every money total is then computed in the user's terms (D-013 / D-014).
 */
@UseGuards(JwtAuthGuard)
@Controller('me')
export class MeController {
  constructor(private readonly settings: UserSettingsService) {}

  @Get()
  me(@CurrentUser() user: AuthenticatedUser): Promise<MeResponse> {
    return this.settings.me(user.id);
  }

  @Patch()
  update(
    @CurrentUser() user: AuthenticatedUser,
    @Body() dto: UpdateMeDto,
  ): Promise<MeResponse> {
    return this.settings.update(user.id, dto);
  }
}
