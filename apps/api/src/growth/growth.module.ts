import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { GrowthController } from './growth.controller';
import { GrowthService } from './growth.service';

/**
 * Growth bounded context (personal development): goals, habits, reflections.
 * Depends on `AuthModule` for the JWT guard and the global `PrismaModule` for
 * RLS-scoped access.
 */
@Module({
  imports: [AuthModule],
  controllers: [GrowthController],
  providers: [GrowthService],
})
export class GrowthModule {}
