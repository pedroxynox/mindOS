import {
  IsOptional,
  IsString,
  ValidationArguments,
  ValidatorConstraint,
  ValidatorConstraintInterface,
  Validate,
} from 'class-validator';
import { isValidCurrency, isValidTimeZone } from '../../common/tz';

@ValidatorConstraint({ name: 'ianaTimeZone' })
class IanaTimeZone implements ValidatorConstraintInterface {
  validate(value: unknown): boolean {
    return typeof value === 'string' && isValidTimeZone(value);
  }
  defaultMessage(args: ValidationArguments): string {
    return `${args.property} must be an IANA timezone (e.g. America/Mexico_City)`;
  }
}

@ValidatorConstraint({ name: 'iso4217Currency' })
class Iso4217Currency implements ValidatorConstraintInterface {
  validate(value: unknown): boolean {
    return typeof value === 'string' && isValidCurrency(value);
  }
  defaultMessage(args: ValidationArguments): string {
    return `${args.property} must be an ISO-4217 code (e.g. BRL, MXN, USD)`;
  }
}

/** Body of `PATCH /v1/me`. `currency: null` resets to "not chosen". */
export class UpdateMeDto {
  @IsOptional()
  @IsString()
  @Validate(IanaTimeZone)
  timezone?: string;

  @IsOptional()
  @IsString()
  @Validate(Iso4217Currency)
  currency?: string | null;
}
