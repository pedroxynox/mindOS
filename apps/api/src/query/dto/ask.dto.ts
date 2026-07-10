import { IsNotEmpty, IsString, MaxLength } from 'class-validator';

/** Body of `POST /v1/query` — the user's natural-language question. */
export class AskDto {
  @IsString()
  @IsNotEmpty()
  @MaxLength(1000)
  question!: string;
}
