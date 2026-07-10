import {
  IsIn,
  IsInt,
  IsISO8601,
  IsNotEmpty,
  IsOptional,
  IsString,
  Max,
  MaxLength,
  Min,
} from 'class-validator';

export const HABIT_CADENCES = ['daily', 'weekly'] as const;
export type HabitCadence = (typeof HABIT_CADENCES)[number];

/** `POST /v1/growth/goals` */
export class CreateGoalDto {
  @IsString()
  @IsNotEmpty()
  @MaxLength(300)
  title!: string;

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
  @MaxLength(300)
  title?: string;

  @IsOptional()
  @IsInt()
  @Min(0)
  @Max(100)
  progress?: number;

  @IsOptional()
  @IsISO8601()
  targetDate?: string | null;
}

/** `POST /v1/growth/habits` */
export class CreateHabitDto {
  @IsString()
  @IsNotEmpty()
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
  @IsNotEmpty()
  @MaxLength(2000)
  body!: string;

  @IsOptional()
  @IsString()
  @MaxLength(30)
  mood?: string;
}
