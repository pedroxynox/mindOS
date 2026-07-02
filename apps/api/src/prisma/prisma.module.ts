import { Global, Module } from '@nestjs/common';
import { PrismaService } from './prisma.service';
import { PrismaRlsService } from './prisma-rls.service';

/**
 * Global module so PrismaService (and the RLS helper) are available everywhere
 * without re-importing.
 */
@Global()
@Module({
  providers: [PrismaService, PrismaRlsService],
  exports: [PrismaService, PrismaRlsService],
})
export class PrismaModule {}
