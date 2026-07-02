import { Body, Controller, HttpCode, HttpStatus, Post } from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { AuthService } from './auth.service';
import {
  AuthTokens,
  CredentialsDto,
  LogoutDto,
  RefreshDto,
} from './dto/auth.dto';

/**
 * Authentication endpoints (API #04 §5.1). JWT built in-house (#07 / ADR-010).
 *
 * Rate limiting (R-002): the global ThrottlerModule (app.module.ts) applies a
 * generous default to the whole API; this controller overrides it with a much
 * STRICTER per-IP budget of 5 requests / 60 s across all auth routes to blunt
 * credential stuffing and brute-force attempts against login/register/refresh.
 */
@Throttle({ default: { limit: 5, ttl: 60_000 } })
@Controller('auth')
export class AuthController {
  constructor(private readonly authService: AuthService) {}

  @Post('register')
  register(@Body() dto: CredentialsDto): Promise<AuthTokens> {
    return this.authService.register(dto);
  }

  @Post('login')
  @HttpCode(HttpStatus.OK)
  login(@Body() dto: CredentialsDto): Promise<AuthTokens> {
    return this.authService.login(dto);
  }

  @Post('refresh')
  @HttpCode(HttpStatus.OK)
  refresh(@Body() dto: RefreshDto): Promise<AuthTokens> {
    return this.authService.refresh(dto.refreshToken);
  }

  /** Revoke the presented refresh token (optionally every session of the user). */
  @Post('logout')
  @HttpCode(HttpStatus.NO_CONTENT)
  async logout(@Body() dto: LogoutDto): Promise<void> {
    await this.authService.logout(dto.refreshToken, dto.allSessions ?? false);
  }
}
