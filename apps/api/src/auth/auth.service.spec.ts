import { ConflictException, UnauthorizedException } from '@nestjs/common';
import { Test, TestingModule } from '@nestjs/testing';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import * as bcrypt from 'bcryptjs';
import { PrismaService } from '../prisma/prisma.service';
import { AuthService } from './auth.service';

// Wrap bcryptjs so `compare` is a spy-able jest.fn that still delegates to the
// real implementation (the module namespace is otherwise non-configurable, so a
// plain jest.spyOn cannot redefine it).
jest.mock('bcryptjs', () => {
  const actual = jest.requireActual('bcryptjs');
  return {
    ...actual,
    compare: jest.fn((data: string, hash: string) =>
      actual.compare(data, hash),
    ),
  };
});

describe('AuthService', () => {
  let service: AuthService;
  let jwt: { signAsync: jest.Mock; verifyAsync: jest.Mock };
  let prisma: {
    user: {
      findUnique: jest.Mock;
      create: jest.Mock;
    };
    refreshToken: {
      create: jest.Mock;
      findUnique: jest.Mock;
      update: jest.Mock;
      updateMany: jest.Mock;
    };
  };

  beforeEach(async () => {
    prisma = {
      user: {
        findUnique: jest.fn(),
        create: jest.fn(),
      },
      refreshToken: {
        create: jest.fn().mockResolvedValue({ id: 'rt_new' }),
        findUnique: jest.fn(),
        update: jest.fn().mockResolvedValue({}),
        updateMany: jest.fn().mockResolvedValue({ count: 0 }),
      },
    };

    jwt = {
      signAsync: jest.fn().mockResolvedValue('signed.jwt.token'),
      verifyAsync: jest.fn(),
    };

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        AuthService,
        { provide: PrismaService, useValue: prisma },
        { provide: JwtService, useValue: jwt },
        { provide: ConfigService, useValue: { get: jest.fn() } },
      ],
    }).compile();

    service = module.get<AuthService>(AuthService);
  });

  afterEach(() => {
    jest.clearAllMocks();
  });

  it('registers a new user and returns tokens', async () => {
    prisma.user.findUnique.mockResolvedValue(null);
    prisma.user.create.mockResolvedValue({ id: 'u_1', email: 'a@b.com' });

    const tokens = await service.register({
      email: 'a@b.com',
      password: 'supersecret',
    });

    expect(prisma.user.create).toHaveBeenCalled();
    // A refresh token hash is persisted on registration.
    expect(prisma.refreshToken.create).toHaveBeenCalled();
    expect(tokens.accessToken).toBe('signed.jwt.token');
    expect(tokens.refreshToken).toBe('signed.jwt.token');
  });

  it('rejects registration when the email already exists', async () => {
    prisma.user.findUnique.mockResolvedValue({ id: 'u_1', email: 'a@b.com' });

    await expect(
      service.register({ email: 'a@b.com', password: 'supersecret' }),
    ).rejects.toBeInstanceOf(ConflictException);
  });

  it('rejects login with a wrong password', async () => {
    const passwordHash = await bcrypt.hash('correct-password', 12);
    prisma.user.findUnique.mockResolvedValue({
      id: 'u_1',
      email: 'a@b.com',
      passwordHash,
    });

    await expect(
      service.login({ email: 'a@b.com', password: 'wrong-password' }),
    ).rejects.toBeInstanceOf(UnauthorizedException);
  });

  // --- Anti-enumeration by timing (D-003) --------------------------------
  describe('login anti-enumeration', () => {
    it('runs a dummy bcrypt.compare and returns the same error for an unknown email', async () => {
      prisma.user.findUnique.mockResolvedValue(null);

      let unknownError: unknown;
      try {
        await service.login({ email: 'ghost@b.com', password: 'whatever12' });
      } catch (err) {
        unknownError = err;
      }

      // A compare MUST run even when the user does not exist (constant-time path).
      expect(bcrypt.compare as jest.Mock).toHaveBeenCalledTimes(1);
      expect(unknownError).toBeInstanceOf(UnauthorizedException);
      expect((unknownError as UnauthorizedException).message).toBe(
        'Credenciales inválidas.',
      );
    });

    it('returns an identical error for an unknown email and a wrong password', async () => {
      // Unknown email path.
      prisma.user.findUnique.mockResolvedValueOnce(null);
      const unknown = await service
        .login({ email: 'ghost@b.com', password: 'whatever12' })
        .catch((e: UnauthorizedException) => e);

      // Wrong password path.
      const passwordHash = await bcrypt.hash('correct-password', 12);
      prisma.user.findUnique.mockResolvedValueOnce({
        id: 'u_1',
        email: 'a@b.com',
        passwordHash,
      });
      const wrong = await service
        .login({ email: 'a@b.com', password: 'wrong-password' })
        .catch((e: UnauthorizedException) => e);

      expect(unknown).toBeInstanceOf(UnauthorizedException);
      expect(wrong).toBeInstanceOf(UnauthorizedException);
      expect((unknown as UnauthorizedException).message).toBe(
        (wrong as UnauthorizedException).message,
      );
    });
  });

  // --- Refresh-token rotation + reuse detection (R-002) -------------------
  describe('refresh rotation', () => {
    const validPayload = {
      sub: 'u_1',
      type: 'refresh' as const,
      jti: 'jti_1',
      family: 'fam_1',
    };

    it('rotates a valid token: old revoked (linked to successor), new pair issued', async () => {
      jwt.verifyAsync.mockResolvedValue(validPayload);
      prisma.refreshToken.findUnique.mockResolvedValue({
        id: 'rt_old',
        userId: 'u_1',
        family: 'fam_1',
        revoked: false,
        expiresAt: new Date(Date.now() + 60_000),
      });

      const tokens = await service.refresh('some.refresh.jwt');

      expect(tokens.accessToken).toBe('signed.jwt.token');
      expect(tokens.refreshToken).toBe('signed.jwt.token');
      // The presented token is revoked and linked to its successor.
      expect(prisma.refreshToken.update).toHaveBeenCalledWith({
        where: { id: 'rt_old' },
        data: { revoked: true, replacedById: 'rt_new' },
      });
    });

    it('rejects an unknown refresh token', async () => {
      jwt.verifyAsync.mockResolvedValue(validPayload);
      prisma.refreshToken.findUnique.mockResolvedValue(null);

      await expect(service.refresh('some.refresh.jwt')).rejects.toBeInstanceOf(
        UnauthorizedException,
      );
      expect(prisma.refreshToken.create).not.toHaveBeenCalled();
    });

    it('rejects an expired refresh token and revokes it', async () => {
      jwt.verifyAsync.mockResolvedValue(validPayload);
      prisma.refreshToken.findUnique.mockResolvedValue({
        id: 'rt_old',
        userId: 'u_1',
        family: 'fam_1',
        revoked: false,
        expiresAt: new Date(Date.now() - 1_000),
      });

      await expect(service.refresh('some.refresh.jwt')).rejects.toBeInstanceOf(
        UnauthorizedException,
      );
      expect(prisma.refreshToken.update).toHaveBeenCalledWith({
        where: { id: 'rt_old' },
        data: { revoked: true },
      });
    });

    it('detects reuse of a revoked token and revokes the whole family', async () => {
      jwt.verifyAsync.mockResolvedValue(validPayload);
      prisma.refreshToken.findUnique.mockResolvedValue({
        id: 'rt_old',
        userId: 'u_1',
        family: 'fam_1',
        revoked: true,
        expiresAt: new Date(Date.now() + 60_000),
      });

      await expect(service.refresh('some.refresh.jwt')).rejects.toBeInstanceOf(
        UnauthorizedException,
      );
      // The entire family is revoked on reuse (theft signal).
      expect(prisma.refreshToken.updateMany).toHaveBeenCalledWith({
        where: { family: 'fam_1', revoked: false },
        data: { revoked: true },
      });
      expect(prisma.refreshToken.create).not.toHaveBeenCalled();
    });

    it('rejects a token whose type is not refresh', async () => {
      jwt.verifyAsync.mockResolvedValue({ sub: 'u_1', type: 'access' });

      await expect(service.refresh('an.access.jwt')).rejects.toBeInstanceOf(
        UnauthorizedException,
      );
      expect(prisma.refreshToken.findUnique).not.toHaveBeenCalled();
    });
  });

  // --- Logout -------------------------------------------------------------
  describe('logout', () => {
    it('revokes the presented refresh token', async () => {
      jwt.verifyAsync.mockResolvedValue({
        sub: 'u_1',
        type: 'refresh',
        family: 'fam_1',
      });
      prisma.refreshToken.findUnique.mockResolvedValue({
        id: 'rt_1',
        userId: 'u_1',
        family: 'fam_1',
        revoked: false,
        expiresAt: new Date(Date.now() + 60_000),
      });

      await service.logout('some.refresh.jwt');

      expect(prisma.refreshToken.update).toHaveBeenCalledWith({
        where: { id: 'rt_1' },
        data: { revoked: true },
      });
    });

    it('revokes every session when allSessions is true', async () => {
      jwt.verifyAsync.mockResolvedValue({
        sub: 'u_1',
        type: 'refresh',
        family: 'fam_1',
      });
      prisma.refreshToken.findUnique.mockResolvedValue({
        id: 'rt_1',
        userId: 'u_1',
        family: 'fam_1',
        revoked: false,
        expiresAt: new Date(Date.now() + 60_000),
      });

      await service.logout('some.refresh.jwt', true);

      expect(prisma.refreshToken.updateMany).toHaveBeenCalledWith({
        where: { userId: 'u_1', revoked: false },
        data: { revoked: true },
      });
    });

    it('resolves quietly for an invalid token', async () => {
      jwt.verifyAsync.mockRejectedValue(new Error('bad token'));

      await expect(service.logout('garbage')).resolves.toBeUndefined();
      expect(prisma.refreshToken.update).not.toHaveBeenCalled();
    });
  });
});
