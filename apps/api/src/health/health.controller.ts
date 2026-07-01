import { Controller, Get } from '@nestjs/common';

export interface HealthStatus {
  status: 'ok';
  service: 'api';
  timestamp: string;
}

/**
 * Liveness endpoint. Confirms the API process is up.
 * Exposed at GET /v1/health (global prefix applied in main.ts).
 */
@Controller('health')
export class HealthController {
  @Get()
  check(): HealthStatus {
    return {
      status: 'ok',
      service: 'api',
      timestamp: new Date().toISOString(),
    };
  }
}
