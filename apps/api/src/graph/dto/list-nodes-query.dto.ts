import { NodeType } from '@prisma/client';
import { Type } from 'class-transformer';
import { IsEnum, IsInt, IsOptional, IsString, Max, Min } from 'class-validator';

/**
 * Query params for `GET /v1/graph/nodes` — the derived-knowledge list.
 *
 * `type` is REQUIRED: the endpoint lists one node type at a time (tasks,
 * people, projects, ...). `capture` is rejected in the service because captures
 * are raw input, not derived knowledge, and have their own `/v1/captures` API.
 * `limit` defaults to 20 and is capped at 100 to bound page size.
 */
export class ListNodesQueryDto {
  @IsEnum(NodeType)
  type!: NodeType;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(100)
  limit: number = 20;

  /** Opaque cursor (a node id) for the next page. */
  @IsOptional()
  @IsString()
  cursor?: string;
}
