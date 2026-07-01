import { Injectable, OnModuleInit } from '@nestjs/common';
import { PrismaClient } from '@prisma/client';

/**
 * Thin wrapper around the generated Prisma client so it can be injected as a
 * NestJS provider and its lifecycle tied to the module.
 */
@Injectable()
export class PrismaService extends PrismaClient implements OnModuleInit {
  async onModuleInit(): Promise<void> {
    await this.$connect();
  }
}
