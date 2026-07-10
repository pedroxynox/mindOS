import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { GraphController } from './graph.controller';
import { GraphService } from './graph.service';

/**
 * Graph bounded context (read side). Exposes the AI-derived knowledge graph via
 * `/v1/graph/*`. Depends on `AuthModule` for the JWT guard and on the global
 * `PrismaModule` for RLS-scoped reads.
 */
@Module({
  imports: [AuthModule],
  controllers: [GraphController],
  providers: [GraphService],
})
export class GraphModule {}
