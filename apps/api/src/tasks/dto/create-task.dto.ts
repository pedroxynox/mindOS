import { Type } from 'class-transformer';
import {
  IsIn,
  IsISO8601,
  IsNotEmpty,
  IsOptional,
  IsString,
  MaxLength,
} from 'class-validator';

/** Allowed task priorities (highest to lowest). */
export const TASK_PRIORITIES = ['high', 'medium', 'low'] as const;
export type TaskPriority = (typeof TASK_PRIORITIES)[number];

/** Body of `POST /v1/tasks` — create a task manually. */
export class CreateTaskDto {
  @IsString()
  @IsNotEmpty()
  @MaxLength(500)
  @Type(() => String)
  title!: string;

  @IsOptional()
  @IsIn(TASK_PRIORITIES)
  priority?: TaskPriority;

  /** ISO-8601 due date/time (optional). */
  @IsOptional()
  @IsISO8601()
  dueAt?: string;

  /** Optional life-area tag (e.g. trabajo, salud, finanzas). */
  @IsOptional()
  @IsString()
  @MaxLength(40)
  area?: string;
}
