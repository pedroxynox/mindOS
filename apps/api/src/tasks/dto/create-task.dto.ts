import { Type } from 'class-transformer';
import {
  IsIn,
  IsISO8601,
  IsOptional,
  IsString,
  Matches,
  MaxLength,
} from 'class-validator';

/** Allowed task priorities (highest to lowest). */
export const TASK_PRIORITIES = ['high', 'medium', 'low'] as const;
export type TaskPriority = (typeof TASK_PRIORITIES)[number];

/** At least one non-whitespace character (rejects '' and '   '). */
export const NOT_BLANK = /\S/;

/** Body of `POST /v1/tasks` — create a task manually. */
export class CreateTaskDto {
  @IsString()
  @Matches(NOT_BLANK, { message: 'title must not be blank' })
  @MaxLength(500)
  @Type(() => String)
  title!: string;

  @IsOptional()
  @IsIn(TASK_PRIORITIES)
  priority?: TaskPriority;

  /** ISO-8601 due date/time (optional). Canonical snake_case field (#04). */
  @IsOptional()
  @IsISO8601()
  due_at?: string;

  /** @deprecated camelCase alias of `due_at`, kept for one release. */
  @IsOptional()
  @IsISO8601()
  dueAt?: string;

  /** Optional life-area tag (e.g. trabajo, salud, finanzas). */
  @IsOptional()
  @IsString()
  @MaxLength(40)
  area?: string;
}
