import { Type } from 'class-transformer';
import { IsInt, IsOptional, IsUUID, Max, Min } from 'class-validator';

/** Query of `GET /v1/finance/expenses`. */
export class ListExpensesQueryDto {
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(100)
  limit: number = 50;

  /** `next_cursor` of the previous page (an expense id). */
  @IsOptional()
  @IsUUID()
  cursor?: string;
}
