import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from './prisma.service';

/**
 * Establishes the per-request user context that drives PostgreSQL Row Level
 * Security (RLS). See design.md §6 and §6.1.
 *
 * Prisma uses a connection pool, so the `SET`/`set_config` of
 * `app.current_user_id` and the request's queries MUST run on the same
 * connection. This is guaranteed by running them inside a single interactive
 * transaction.
 */
@Injectable()
export class PrismaRlsService {
  constructor(private readonly prisma: PrismaService) {}

  /**
   * Runs `work` inside a transaction where `app.current_user_id` is set, so the
   * RLS policies filter every read/write by that user.
   *
   * `set_config(..., true)` makes the setting transaction-local: it is cleared
   * automatically when the transaction ends, so a pooled connection never leaks
   * one user's context into another user's request.
   *
   * Precondition: `userId` comes from the JWT verified by `JwtAuthGuard`, never
   *   from the request body.
   * Postcondition: every read or write performed inside `work` is restricted to
   *   rows owned by `userId` by RLS (fail-closed if the context is missing).
   *
   * @param userId owner id (UUID string) extracted from the verified JWT
   * @param work   callback receiving the transaction client bound to the context
   */
  async withUser<T>(
    userId: string,
    work: (tx: Prisma.TransactionClient) => Promise<T>,
  ): Promise<T> {
    return this.prisma.$transaction(async (tx) => {
      // Parameterized via the template tag: the userId is bound as a query
      // parameter, never string-interpolated, so it cannot be used for injection.
      await tx.$executeRaw`SELECT set_config('app.current_user_id', ${userId}, true)`;
      return work(tx);
    });
  }
}
