import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { BriefingController } from './briefing.controller';
import { BriefingService } from './briefing.service';

/**
 * Briefing bounded context (read side). Exposes the Daily Briefing via
 * `/v1/briefing`. Depends on `AuthModule` for the JWT guard and the global
 * `PrismaModule` for RLS-scoped reads.
 */
@Module({
  imports: [AuthModule],
  controllers: [BriefingController],
  providers: [BriefingService],
})
export class BriefingModule {}
