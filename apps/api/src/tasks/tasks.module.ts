import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { TasksController } from './tasks.controller';
import { TasksService } from './tasks.service';

/**
 * Tasks bounded context. Exposes `/v1/tasks` for listing (priority-ordered),
 * creating and updating tasks. Depends on `AuthModule` for the JWT guard and the
 * global `PrismaModule` for RLS-scoped access.
 */
@Module({
  imports: [AuthModule],
  controllers: [TasksController],
  providers: [TasksService],
})
export class TasksModule {}
