import { Injectable } from '@nestjs/common';
import { PrismaRlsService } from '../prisma/prisma-rls.service';
import { FeedbackDto, FeedbackTargetDto } from './dto/feedback.dto';

export interface FeedbackResponse {
  id: string;
  target_type: string;
  target_id: string;
  useful: boolean;
  reason: string | null;
  updated_at: string;
}

/** The caller's current vote on a target (`useful: null` = not voted). */
export interface FeedbackVoteResponse {
  target_type: string;
  target_id: string;
  useful: boolean | null;
}

/**
 * Stores the user's 👍/👎 on what mindOS produced — the direct source of the
 * North Star metric ("interacciones de valor por usuario y semana", #01 §8).
 * One vote per target: voting again replaces the previous vote. RLS scopes
 * every read and write to the caller.
 */
@Injectable()
export class FeedbackService {
  constructor(private readonly rls: PrismaRlsService) {}

  async record(userId: string, dto: FeedbackDto): Promise<FeedbackResponse> {
    const reason = dto.reason?.trim() || null;
    const row = await this.rls.withUser(userId, (tx) =>
      tx.feedback.upsert({
        where: {
          uq_feedback_user_target: {
            userId,
            targetType: dto.target_type,
            targetId: dto.target_id,
          },
        },
        create: {
          userId,
          targetType: dto.target_type,
          targetId: dto.target_id,
          useful: dto.useful,
          reason,
        },
        update: { useful: dto.useful, reason },
      }),
    );
    return {
      id: row.id,
      target_type: row.targetType,
      target_id: row.targetId,
      useful: row.useful,
      reason: row.reason,
      updated_at: row.updatedAt.toISOString(),
    };
  }

  async vote(
    userId: string,
    target: FeedbackTargetDto,
  ): Promise<FeedbackVoteResponse> {
    const row = await this.rls.withUser(userId, (tx) =>
      tx.feedback.findUnique({
        where: {
          uq_feedback_user_target: {
            userId,
            targetType: target.target_type,
            targetId: target.target_id,
          },
        },
        select: { useful: true },
      }),
    );
    return {
      target_type: target.target_type,
      target_id: target.target_id,
      useful: row ? row.useful : null,
    };
  }
}
