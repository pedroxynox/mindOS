import { ConflictException, UnauthorizedException } from '@nestjs/common';
import { Test, TestingModule } from '@nestjs/testing';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import * as bcrypt from 'bcryptjs';
import { PrismaService } from '../prisma/prisma.service';
import { AuthService } from './auth.service';

describe('AuthService', () => {
  let service: AuthService;
  let prisma: {
    user: {
      findUnique: jest.Mock;
      create: jest.Mock;
    };
  };

  beforeEach(async () => {
    prisma = {
      user: {
        findUnique: jest.fn(),
        create: jest.fn(),
      },
    };

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        AuthService,
        { provide: PrismaService, useValue: prisma },
        {
          provide: JwtService,
          useValue: {
            signAsync: jest.fn().mockResolvedValue('signed.jwt.token'),
            verifyAsync: jest.fn(),
          },
        },
        { provide: ConfigService, useValue: { get: jest.fn() } },
      ],
    }).compile();

    service = module.get<AuthService>(AuthService);
  });

  it('registers a new user and returns tokens', async () => {
    prisma.user.findUnique.mockResolvedValue(null);
    prisma.user.create.mockResolvedValue({ id: 'u_1', email: 'a@b.com' });

    const tokens = await service.register({
      email: 'a@b.com',
      password: 'supersecret',
    });

    expect(prisma.user.create).toHaveBeenCalled();
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
});
