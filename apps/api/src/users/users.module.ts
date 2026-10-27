import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { MeController } from './me.controller';
import { UserSettingsService } from './user-settings.service';

/** User profile + preferences (timezone, currency). Exported for features. */
@Module({
  imports: [AuthModule],
  controllers: [MeController],
  providers: [UserSettingsService],
  exports: [UserSettingsService],
})
export class UsersModule {}
