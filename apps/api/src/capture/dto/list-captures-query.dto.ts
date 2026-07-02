import { CaptureStatus } from '@prisma/client';
import { Type } from 'class-transformer';
import { IsEnum, IsInt, IsOptional, IsString, Max, Min } from 'class-validator';

/**
 * Query params for `GET /v1/captures` (design.md §7.1, refinement b).
 * `limit` defaults to 20 and is capped at 100 to bound page size.
 */
export class ListCapturesQueryDto {
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(100)
  limit: number = 20;

  /** Opaque cursor (a capture id) for the next page. */
  @IsOptional()
  @IsString()
  cursor?: string;

  /** Optional status filter; only own captures with this status are returned. */
  @IsOptional()
  @IsEnum(CaptureStatus)
  status?: CaptureStatus;
}
