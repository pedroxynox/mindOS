import {
  IsBoolean,
  IsIn,
  IsISO8601,
  IsOptional,
  IsString,
  MaxLength,
} from 'class-validator';
import { TASK_PRIORITIES, TaskPriority } from './create-task.dto';

/**
 * Body of `PATCH /v1/tasks/:id`. Every field is optional; only the provided
 * fields are changed. `dueAt: null` clears the due date.
 */
export class UpdateTaskDto {
  @IsOptional()
  @IsString()
  @MaxLength(500)
  title?: string;

  @IsOptional()
  @IsBoolean()
  done?: boolean;

  @IsOptional()
  @IsIn(TASK_PRIORITIES)
  priority?: TaskPriority;

  @IsOptional()
  @IsISO8601()
  dueAt?: string | null;

  @IsOptional()
  @IsString()
  @MaxLength(40)
  area?: string | null;
}
