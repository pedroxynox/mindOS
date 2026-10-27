import { Transform } from 'class-transformer';
import {
  IsBoolean,
  IsIn,
  IsOptional,
  IsString,
  Matches,
  MaxLength,
} from 'class-validator';

export const FEEDBACK_TARGETS = [
  'capture',
  'query',
  'briefing',
  'node',
] as const;
export type FeedbackTarget = (typeof FEEDBACK_TARGETS)[number];

const trim = ({ value }: { value: unknown }): unknown =>
  typeof value === 'string' ? value.trim() : value;

/** Identifies what was rated. */
export class FeedbackTargetDto {
  @IsIn(FEEDBACK_TARGETS)
  target_type!: FeedbackTarget;

  /**
   * Capture/node id, the question asked (same 1000-char cap as `/v1/query`),
   * or the local day `YYYY-MM-DD` (briefing).
   */
  @IsString()
  @Matches(/\S/, { message: 'target_id must not be blank' })
  @MaxLength(1000)
  @Transform(trim)
  target_id!: string;
}

/** Body of `POST /v1/feedback` (FR-3.5). */
export class FeedbackDto extends FeedbackTargetDto {
  @IsBoolean()
  useful!: boolean;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  reason?: string;
}
