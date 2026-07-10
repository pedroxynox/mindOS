import { Type } from 'class-transformer';
import {
  IsNumber,
  IsOptional,
  IsString,
  Max,
  MaxLength,
  Min,
} from 'class-validator';

/** Body of `POST /v1/finance/expenses` — log a single expense. */
export class CreateExpenseDto {
  @Type(() => Number)
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(0)
  @Max(100000000)
  amount!: number;

  @IsOptional()
  @IsString()
  @MaxLength(40)
  category?: string;

  /** ISO-4217-ish currency code; defaults to USD. */
  @IsOptional()
  @IsString()
  @MaxLength(8)
  currency?: string;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  note?: string;
}
