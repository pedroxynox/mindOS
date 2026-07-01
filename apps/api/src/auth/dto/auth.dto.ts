import { IsEmail, IsString, MinLength } from 'class-validator';

/** Payload for registration and login. */
export class CredentialsDto {
  @IsEmail()
  email!: string;

  @IsString()
  @MinLength(8, { message: 'La contraseña debe tener al menos 8 caracteres.' })
  password!: string;
}

/** Payload to exchange a refresh token for a new access token. */
export class RefreshDto {
  @IsString()
  refreshToken!: string;
}

/** Tokens returned to the client after authentication. */
export interface AuthTokens {
  accessToken: string;
  refreshToken: string;
  expiresIn: number;
}
