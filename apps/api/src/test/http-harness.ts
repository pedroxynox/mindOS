import {
  CanActivate,
  ExecutionContext,
  INestApplication,
  Provider,
  Type,
  ValidationPipe,
} from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';

/** Fixed caller injected by the fake guard in controller tests. */
export const TEST_USER_ID = '11111111-1111-1111-1111-111111111111';

/** Replaces JwtAuthGuard: authenticates every request as TEST_USER_ID. */
class FakeAuthGuard implements CanActivate {
  canActivate(context: ExecutionContext): boolean {
    const req = context.switchToHttp().getRequest();
    req.user = { id: TEST_USER_ID };
    return true;
  }
}

/**
 * Boot a minimal Nest HTTP app for controller tests: the given controllers and
 * (mocked) providers, the SAME global ValidationPipe and `v1` prefix as
 * `main.ts`, and a fake auth guard. Lets tests assert DTO validation, status
 * codes and wiring without a database (D-012).
 */
export async function createHttpHarness(
  controllers: Type<unknown>[],
  providers: Provider[],
): Promise<INestApplication> {
  const moduleRef = await Test.createTestingModule({
    controllers,
    providers,
  })
    .overrideGuard(JwtAuthGuard)
    .useClass(FakeAuthGuard)
    .compile();

  const app = moduleRef.createNestApplication();
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
    }),
  );
  app.setGlobalPrefix('v1');
  await app.init();
  return app;
}
