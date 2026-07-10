import { NestFactory } from '@nestjs/core';
import { Logger, ValidationPipe } from '@nestjs/common';
import { AppModule } from './app.module';

async function bootstrap(): Promise<void> {
  const app = await NestFactory.create(AppModule);

  // Cross-origin access for the web app (served from a different Render host).
  // Origins are configurable via CORS_ORIGIN (comma-separated); defaults cover
  // the Render web service and local development. Auth uses Bearer tokens.
  const corsOrigins = (
    process.env.CORS_ORIGIN ??
    'https://mindos-web.onrender.com,http://localhost:8080,http://localhost:3000'
  )
    .split(',')
    .map((origin) => origin.trim())
    .filter((origin) => origin.length > 0);
  app.enableCors({
    origin: corsOrigins,
    methods: ['GET', 'POST', 'PATCH', 'PUT', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization', 'Idempotency-Key'],
    credentials: true,
  });

  // Global input validation (Engineering Standards #05 §8). `transform` coerces
  // query/body primitives (e.g. list pagination `limit`) to their DTO types.
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
    }),
  );

  // API versioning via path prefix (API Design #04 §3).
  app.setGlobalPrefix('v1');

  const port = process.env.PORT ? Number(process.env.PORT) : 3000;
  await app.listen(port);

  Logger.log(`mindOS API running on http://localhost:${port}/v1`, 'Bootstrap');
}

void bootstrap();
