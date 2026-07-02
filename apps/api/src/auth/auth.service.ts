import {
  ConflictException,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { createHash, randomUUID } from 'crypto';
import * as bcrypt from 'bcryptjs';
import { PrismaService } from '../prisma/prisma.service';
import { AuthTokens, CredentialsDto } from './dto/auth.dto';

interface TokenPayload {
  sub: string;
  type: 'access' | 'refresh';
  /** Unique token id — guarantees each issued refresh token string is distinct. */
  jti?: string;
  /** Session/family id — reuse of any member revokes the whole family. */
  family?: string;
}

/**
 * Precomputed bcrypt hash used ONLY for the constant-time dummy compare on the
 * login "user not found" path (anti-enumeration, closes D-003). It never
 * matches any real password; its sole purpose is to spend the same CPU as a
 * genuine `bcrypt.compare` so the response time does not reveal whether an
 * email is registered. Computed once at module load with the same cost factor
 * (12) as real password hashes.
 */
const DUMMY_PASSWORD_HASH = bcrypt.hashSync(
  'timing-equalizer-not-a-real-password',
  12,
);

@Injectable()
export class AuthService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly jwt: JwtService,
    private readonly config: ConfigService,
  ) {}

  async register(dto: CredentialsDto): Promise<AuthTokens> {
    const existing = await this.prisma.user.findUnique({
      where: { email: dto.email },
    });
    if (existing) {
      throw new ConflictException('El email ya está registrado.');
    }

    const passwordHash = await bcrypt.hash(dto.password, 12);
    const user = await this.prisma.user.create({
      data: { email: dto.email, passwordHash },
    });

    return (await this.issueTokens(user.id)).tokens;
  }

  async login(dto: CredentialsDto): Promise<AuthTokens> {
    const user = await this.prisma.user.findUnique({
      where: { email: dto.email },
    });

    // Anti-enumeration (D-003): always run a bcrypt.compare, even when the user
    // does not exist, so the "unknown email" and "wrong password" paths take the
    // same time. A fixed dummy hash is compared on the not-found path; the result
    // is discarded. Both failures surface the SAME generic error so no signal
    // (timing or message) reveals whether an email is registered.
    if (!user) {
      await bcrypt.compare(dto.password, DUMMY_PASSWORD_HASH);
      throw new UnauthorizedException('Credenciales inválidas.');
    }

    const valid = await bcrypt.compare(dto.password, user.passwordHash);
    if (!valid) {
      throw new UnauthorizedException('Credenciales inválidas.');
    }

    return (await this.issueTokens(user.id)).tokens;
  }

  /**
   * Exchange a refresh token for a fresh token pair (single-use rotation).
   *
   * - A valid, non-revoked, non-expired token rotates: the presented token is
   *   marked revoked (with `replacedById` linking to its successor) and a new
   *   pair is issued within the SAME family.
   * - Presenting an already revoked/used token (reuse) is treated as a theft
   *   signal: the WHOLE family is revoked and the request is rejected.
   * - An unknown, expired or malformed token is rejected.
   */
  async refresh(refreshToken: string): Promise<AuthTokens> {
    let payload: TokenPayload;
    try {
      payload = await this.jwt.verifyAsync<TokenPayload>(refreshToken);
    } catch {
      throw new UnauthorizedException('Refresh token inválido o expirado.');
    }
    if (payload.type !== 'refresh') {
      throw new UnauthorizedException('Tipo de token incorrecto.');
    }

    const tokenHash = this.hashToken(refreshToken);
    const stored = await this.prisma.refreshToken.findUnique({
      where: { tokenHash },
    });

    // Unknown token: signature was valid but it is not (or no longer) in the
    // ledger. Reject without leaking why.
    if (!stored) {
      throw new UnauthorizedException('Refresh token inválido o expirado.');
    }

    // Reuse detection: a revoked token being presented again means the token was
    // captured/replayed. Revoke the entire family (all sessions in that chain)
    // and reject — this also invalidates whatever token the attacker rotated to.
    if (stored.revoked) {
      await this.prisma.refreshToken.updateMany({
        where: { family: stored.family, revoked: false },
        data: { revoked: true },
      });
      throw new UnauthorizedException(
        'Refresh token reutilizado: sesión revocada.',
      );
    }

    if (stored.expiresAt.getTime() <= Date.now()) {
      await this.prisma.refreshToken.update({
        where: { id: stored.id },
        data: { revoked: true },
      });
      throw new UnauthorizedException('Refresh token inválido o expirado.');
    }

    // Happy path: rotate within the same family.
    const next = await this.issueTokens(stored.userId, stored.family);
    await this.prisma.refreshToken.update({
      where: { id: stored.id },
      data: { revoked: true, replacedById: next.refreshTokenId },
    });

    return next.tokens;
  }

  /**
   * Revoke the presented refresh token. When `allSessions` is true, every
   * non-revoked token of the same user is revoked (global logout). Idempotent
   * and non-revealing: an invalid/unknown token still resolves quietly.
   */
  async logout(refreshToken: string, allSessions = false): Promise<void> {
    let payload: TokenPayload;
    try {
      payload = await this.jwt.verifyAsync<TokenPayload>(refreshToken);
    } catch {
      return; // nothing actionable; do not leak whether the token existed
    }
    if (payload.type !== 'refresh') {
      return;
    }

    const tokenHash = this.hashToken(refreshToken);
    const stored = await this.prisma.refreshToken.findUnique({
      where: { tokenHash },
    });
    if (!stored) {
      return;
    }

    if (allSessions) {
      await this.prisma.refreshToken.updateMany({
        where: { userId: stored.userId, revoked: false },
        data: { revoked: true },
      });
      return;
    }

    if (!stored.revoked) {
      await this.prisma.refreshToken.update({
        where: { id: stored.id },
        data: { revoked: true },
      });
    }
  }

  /**
   * Sign an access + refresh pair and persist the HASH of the refresh token in
   * the ledger. Reuses `family` on rotation so a whole session can be revoked at
   * once; a fresh login/register starts a new family.
   */
  private async issueTokens(
    userId: string,
    family?: string,
  ): Promise<{ tokens: AuthTokens; refreshTokenId: string }> {
    const accessTtl = Number(this.config.get('JWT_ACCESS_TTL') ?? 3600);
    const refreshTtl = Number(this.config.get('JWT_REFRESH_TTL') ?? 1209600);
    const familyId = family ?? randomUUID();
    const jti = randomUUID();

    const accessToken = await this.jwt.signAsync(
      { sub: userId, type: 'access' } satisfies TokenPayload,
      { expiresIn: accessTtl },
    );
    const refreshToken = await this.jwt.signAsync(
      {
        sub: userId,
        type: 'refresh',
        jti,
        family: familyId,
      } satisfies TokenPayload,
      { expiresIn: refreshTtl },
    );

    const created = await this.prisma.refreshToken.create({
      data: {
        userId,
        tokenHash: this.hashToken(refreshToken),
        family: familyId,
        expiresAt: new Date(Date.now() + refreshTtl * 1000),
      },
    });

    return {
      tokens: { accessToken, refreshToken, expiresIn: accessTtl },
      refreshTokenId: created.id,
    };
  }

  /**
   * One-way hash of a refresh token for storage/lookup. SHA-256 (not bcrypt) is
   * used deliberately: the token is high-entropy and opaque, so a fast digest is
   * safe and enables O(1) lookup by hash. The plaintext token is never stored.
   */
  private hashToken(token: string): string {
    return createHash('sha256').update(token).digest('hex');
  }
}
