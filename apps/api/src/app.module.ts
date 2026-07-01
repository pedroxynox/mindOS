import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { AuthModule } from './auth/auth.module';
import { HealthModule } from './health/health.module';
import { PrismaModule } from './prisma/prisma.module';

/**
 * Root module of the mindOS business API.
 *
 * Bounded contexts (Identity, Capture, Graph, Realtime) are registered here as
 * they are implemented (see #02 §4 and ADR-010). F1a wires identity (auth).
 */
@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true }),
    PrismaModule,
    HealthModule,
    AuthModule,
  ],
})
export class AppModule {}
