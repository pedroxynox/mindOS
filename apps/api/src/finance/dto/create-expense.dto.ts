import { Transform, Type } from 'class-transformer';
import {
  IsISO4217CurrencyCode,
  IsISO8601,
  IsNumber,
  IsOptional,
  IsPositive,
  IsString,
  Max,
  MaxLength,
} from 'class-validator';

/** Body of `POST /v1/finance/expenses` — log a single expense. */
export class CreateExpenseDto {
  @Type(() => Number)
  @IsNumber({ maxDecimalPlaces: 2 })
  @IsPositive()
  @Max(100000000)
  amount!: number;

  /**
   * Canonical key (food, transport, home, health, leisure, shopping, bills,
   * education, other). Legacy free text ("comida") is mapped to its key;
   * anything unknown is stored as `other`.
   */
  @IsOptional()
  @IsString()
  @MaxLength(40)
  category?: string;

  /** ISO-4217 code; defaults to the user's currency (or USD). */
  @IsOptional()
  @Transform(({ value }) =>
    typeof value === 'string' ? value.toUpperCase() : value,
  )
  @IsISO4217CurrencyCode()
  currency?: string;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  note?: string;

  /** When the money was spent (ISO-8601); defaults to now. */
  @IsOptional()
  @IsISO8601()
  spent_at?: string;
}
