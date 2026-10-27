import {
  IsIn,
  IsInt,
  IsISO8601,
  IsOptional,
  IsString,
  Matches,
  Max,
  MaxLength,
  Min,
} from 'class-validator';
import { NOT_BLANK } from '../../tasks/dto/create-task.dto';

export const HABIT_CADENCES = ['daily', 'weekly'] as const;
export type HabitCadence = (typeof HABIT_CADENCES)[number];

/** `POST /v1/growth/goals` */
export class CreateGoalDto {
  @IsString()
  @Matches(NOT_BLANK, { message: 'title must not be blank' })
  @MaxLength(300)
  title!: string;

  /** Canonical snake_case field (#04). */
  @IsOptional()
  @IsISO8601()
  target_date?: string;

  /** @deprecated camelCase alias of `target_date`, kept for one release. */
  @IsOptional()
  @IsISO8601()
  targetDate?: string;

  @IsOptional()
  @IsString()
  @MaxLength(40)
  area?: string;
}

/** `PATCH /v1/growth/goals/:id` */
export class UpdateGoalDto {
  @IsOptional()
  @IsString()
  @Matches(NOT_BLANK, { message: 'title must not be blank' })
  @MaxLength(300)
  title?: string;

  @IsOptional()
  @IsInt()
  @Min(0)
  @Max(100)
  progress?: number;

  /** Canonical snake_case field (#04). `null` clears it. */
  @IsOptional()
  @IsISO8601()
  target_date?: string | null;

  /** @deprecated camelCase alias of `target_date`, kept for one release. */
  @IsOptional()
  @IsISO8601()
  targetDate?: string | null;
}

/** Resolve the target date from the canonical field or its deprecated alias. */
export function resolveTargetDate(dto: {
  target_date?: string | null;
  targetDate?: string | null;
}): string | null | undefined {
  if (dto.target_date !== undefined) return dto.target_date;
  return dto.targetDate;
}

/** `POST /v1/growth/habits` */
export class CreateHabitDto {
  @IsString()
  @Matches(NOT_BLANK, { message: 'title must not be blank' })
  @MaxLength(200)
  title!: string;

  @IsOptional()
  @IsIn(HABIT_CADENCES)
  cadence?: HabitCadence;

  @IsOptional()
  @IsString()
  @MaxLength(40)
  area?: string;
}

/** `POST /v1/growth/reflections` */
export class CreateReflectionDto {
  @IsString()
  @Matches(NOT_BLANK, { message: 'body must not be blank' })
  @MaxLength(2000)
  body!: string;

  @IsOptional()
  @IsString()
  @MaxLength(30)
  mood?: string;
}
