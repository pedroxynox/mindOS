import { Transform } from 'class-transformer';
import {
  IsBoolean,
  IsIn,
  IsOptional,
  IsString,
  Matches,
  MaxLength,
} from 'class-validator';
import { NOT_BLANK } from '../../tasks/dto/create-task.dto';

/**
 * How far a correction reaches (FR-2.4):
 *  - `node`   — only this mention (fix what one capture got wrong);
 *  - `entity` — every mention of the same name (rename or forget the person,
 *    project, topic... everywhere). Same as `node` for tasks and notes.
 */
export const CORRECTION_SCOPES = ['node', 'entity'] as const;
export type CorrectionScope = (typeof CORRECTION_SCOPES)[number];

const trim = ({ value }: { value: unknown }): unknown =>
  typeof value === 'string' ? value.trim() : value;

/** Body of `PATCH /v1/graph/nodes/:id`. */
export class RenameNodeDto {
  @IsString()
  @Matches(NOT_BLANK, { message: 'title must not be blank' })
  @MaxLength(500)
  @Transform(trim)
  title!: string;

  @IsOptional()
  @IsIn(CORRECTION_SCOPES)
  scope: CorrectionScope = 'node';
}

/** Query of `DELETE /v1/graph/nodes/:id`. */
export class NodeScopeQueryDto {
  @IsOptional()
  @IsIn(CORRECTION_SCOPES)
  scope: CorrectionScope = 'node';
}

/** Body of `PATCH /v1/graph/edges/:id`: confirm (true) or reject (false). */
export class ReviewEdgeDto {
  @IsBoolean()
  confirmed!: boolean;
}
