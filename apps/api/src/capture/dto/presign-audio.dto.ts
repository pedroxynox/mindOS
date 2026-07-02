import { Type } from 'class-transformer';
import { IsInt, IsNotEmpty, IsString, Min } from 'class-validator';

/**
 * Body of `POST /v1/captures/audio-upload` (design.md §7.1). The content-type
 * allowlist and the maximum size are enforced authoritatively by
 * BlobStorageService so there is a single source of truth (R2.2).
 */
export class PresignAudioDto {
  @IsString()
  @IsNotEmpty()
  content_type!: string;

  @Type(() => Number)
  @IsInt()
  @Min(1)
  size_bytes!: number;
}
