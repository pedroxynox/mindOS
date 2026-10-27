import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { isValidTimeZone } from '../common/tz';

/** The per-user preferences every day-bucketed feature needs. */
export interface UserSettings {
  timezone: string;
  /** ISO-4217 code, or null when the user has not chosen one yet. */
  currency: string | null;
}

/** Public profile returned by `GET /v1/me`. */
export interface MeResponse extends UserSettings {
  id: string;
  email: string;
  /** Effective currency for display/defaults (falls back to USD). */
  effective_currency: string;
  created_at: string;
}

export const DEFAULT_CURRENCY = 'USD';

/**
 * Reads/writes the user's settings. `users` is the identity table (no RLS by
 * design, F1); every query is explicitly scoped to the authenticated id.
 */
@Injectable()
export class UserSettingsService {
  constructor(private readonly prisma: PrismaService) {}

  /** Settings for a user; a corrupt/unknown zone degrades safely to UTC. */
  async get(userId: string): Promise<UserSettings> {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { timezone: true, currency: true },
    });
    const timezone =
      user?.timezone && isValidTimeZone(user.timezone) ? user.timezone : 'UTC';
    return { timezone, currency: user?.currency ?? null };
  }

  async me(userId: string): Promise<MeResponse> {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: {
        id: true,
        email: true,
        timezone: true,
        currency: true,
        createdAt: true,
      },
    });
    if (!user) {
      throw new NotFoundException({ code: 'not_found', message: 'User not found.' });
    }
    return {
      id: user.id,
      email: user.email,
      timezone: isValidTimeZone(user.timezone) ? user.timezone : 'UTC',
      currency: user.currency,
      effective_currency: user.currency ?? DEFAULT_CURRENCY,
      created_at: user.createdAt.toISOString(),
    };
  }

  async update(
    userId: string,
    patch: { timezone?: string; currency?: string | null },
  ): Promise<MeResponse> {
    const data: { timezone?: string; currency?: string | null } = {};
    if (patch.timezone !== undefined) data.timezone = patch.timezone;
    if (patch.currency !== undefined) data.currency = patch.currency;
    if (Object.keys(data).length > 0) {
      await this.prisma.user.update({ where: { id: userId }, data });
    }
    return this.me(userId);
  }
}
