import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { HealthModule } from './health/health.module';

/**
 * Root module of the mindOS business API.
 *
 * Bounded contexts (Identity, Capture, Graph, Realtime) will be registered
 * here as they are implemented in later phases (see #02 §4 and ADR-010).
 * F0 wires only configuration and the health check.
 */
@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true }),
    HealthModule,
  ],
})
export class AppModule {}
