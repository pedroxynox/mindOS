import {
  IsBoolean,
  IsIn,
  IsISO8601,
  IsOptional,
  IsString,
  Matches,
  MaxLength,
} from 'class-validator';
import { NOT_BLANK, TASK_PRIORITIES, TaskPriority } from './create-task.dto';

/**
 * Body of `PATCH /v1/tasks/:id`. Every field is optional; only the provided
 * fields are changed. `due_at: null` clears the due date and `area: null`
 * clears the area. A provided `title` must not be blank.
 */
export class UpdateTaskDto {
  @IsOptional()
  @IsString()
  @Matches(NOT_BLANK, { message: 'title must not be blank' })
  @MaxLength(500)
  title?: string;

  @IsOptional()
  @IsBoolean()
  done?: boolean;

  @IsOptional()
  @IsIn(TASK_PRIORITIES)
  priority?: TaskPriority;

  /** Canonical snake_case field (#04). `null` clears the due date. */
  @IsOptional()
  @IsISO8601()
  due_at?: string | null;

  /** @deprecated camelCase alias of `due_at`, kept for one release. */
  @IsOptional()
  @IsISO8601()
  dueAt?: string | null;

  @IsOptional()
  @IsString()
  @MaxLength(40)
  area?: string | null;
}

/**
 * Resolve the due date from the canonical field or its deprecated alias.
 * Returns `undefined` when neither was sent (leave unchanged), `null` to clear.
 */
export function resolveDueAt(dto: {
  due_at?: string | null;
  dueAt?: string | null;
}): string | null | undefined {
  if (dto.due_at !== undefined) return dto.due_at;
  return dto.dueAt;
}
