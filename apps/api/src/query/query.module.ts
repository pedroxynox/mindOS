import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { QueryController } from './query.controller';
import { QueryService } from './query.service';

/**
 * Query bounded context. Exposes `POST /v1/query`, bridging the authenticated
 * request to the AI service's RAG endpoint. Depends on `AuthModule` for the JWT
 * guard; `ConfigService` (global) supplies the AI URL and shared secret.
 */
@Module({
  imports: [AuthModule],
  controllers: [QueryController],
  providers: [QueryService],
})
export class QueryModule {}
