import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { APP_GUARD } from '@nestjs/core';
import { ThrottlerGuard, ThrottlerModule } from '@nestjs/throttler';
import { AuthModule } from './auth/auth.module';
import { CaptureModule } from './capture/capture.module';
import { GraphModule } from './graph/graph.module';
import { HealthModule } from './health/health.module';
import { PrismaModule } from './prisma/prisma.module';

/**
 * Root module of the mindOS business API.
 *
 * Bounded contexts (Identity, Capture, Graph, Realtime) are registered here as
 * they are implemented (see #02 §4 and ADR-010). F1a wires identity (auth).
 *
 * Rate limiting (R-002): `ThrottlerModule` installs a global, per-IP budget as
 * a baseline anti-abuse control across the whole API (default: 100 requests /
 * 60 s). The `ThrottlerGuard` is registered as an APP_GUARD so it applies to
 * every route without per-controller wiring. Sensitive auth routes tighten this
 * further with a per-controller `@Throttle` override (see AuthController).
 */
@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true }),
    ThrottlerModule.forRoot([
      {
        name: 'default',
        ttl: 60_000, // window in milliseconds
        limit: 100, // requests per IP per window (generous global baseline)
      },
    ]),
    PrismaModule,
    HealthModule,
    AuthModule,
    CaptureModule,
    GraphModule,
  ],
  providers: [
    {
      provide: APP_GUARD,
      useClass: ThrottlerGuard,
    },
  ],
})
export class AppModule {}
