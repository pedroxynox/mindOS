import {
  IsEnum,
  IsISO8601,
  IsOptional,
  IsString,
  IsUUID,
  MaxLength,
  MinLength,
} from 'class-validator';

/** Modality of a capture creation request. */
export enum CaptureType {
  text = 'text',
  voice = 'voice',
}

/**
 * Body of `POST /v1/captures` (design.md §7.1). `user_id` is never accepted
 * here — it is always derived from the verified JWT (R1.3).
 */
export class CreateCaptureDto {
  @IsEnum(CaptureType)
  type!: CaptureType;

  /**
   * Raw text or voice transcription. Required and non-empty for text captures
   * (enforced in CaptureService); optional for voice pending transcription.
   */
  @IsOptional()
  @IsString()
  @MinLength(1)
  @MaxLength(20_000)
  content?: string;

  /** S3 object key obtained from `/audio-upload`. Voice captures only. */
  @IsOptional()
  @IsString()
  @MaxLength(512)
  audio_ref?: string;

  /** When the event actually happened, if the client knows it (#03 §9). */
  @IsOptional()
  @IsISO8601()
  occurred_at?: string;

  /** Drift outbox client_id; traces the original offline capture. */
  @IsOptional()
  @IsUUID()
  client_id?: string;
}
