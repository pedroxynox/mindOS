import { NestFactory } from '@nestjs/core';
import { Logger, ValidationPipe } from '@nestjs/common';
import { AppModule } from './app.module';

async function bootstrap(): Promise<void> {
  const app = await NestFactory.create(AppModule);

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
