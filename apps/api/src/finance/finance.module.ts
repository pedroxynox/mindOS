import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { FinanceController } from './finance.controller';
import { FinanceService } from './finance.service';

/**
 * Finance bounded context. Exposes `/v1/finance/*`. Depends on `AuthModule` for
 * the JWT guard and the global `PrismaModule` for RLS-scoped access.
 */
@Module({
  imports: [AuthModule],
  controllers: [FinanceController],
  providers: [FinanceService],
})
export class FinanceModule {}
