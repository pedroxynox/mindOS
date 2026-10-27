import {
  BadRequestException,
  Body,
  Controller,
  Get,
  Headers,
  HttpCode,
  Param,
  ParseUUIDPipe,
  Post,
  Query,
  Req,
  UseGuards,
} from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { Request } from 'express';
import { isISO8601, isUUID } from 'class-validator';
import { AuthenticatedUser } from '../auth/jwt-auth.guard';
import { CurrentUser } from '../auth/current-user.decorator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { PresignUploadResult } from './blob-storage.service';
import {
  CaptureListPage,
  CaptureService,
  VOICE_MAX_BYTES,
} from './capture.service';
import { readRawBody } from './raw-body';
import { CaptureResponse } from './capture.mapper';
import { CreateCaptureDto } from './dto/create-capture.dto';
import { ListCapturesQueryDto } from './dto/list-captures-query.dto';
import { PresignAudioDto } from './dto/presign-audio.dto';

/**
 * Capture endpoints (design.md §7). All routes require a valid Bearer token via
 * JwtAuthGuard; the owner `user_id` is taken from the token, never the body.
 * The global `v1` prefix makes these `/v1/captures...`.
 */
@UseGuards(JwtAuthGuard)
@Controller('captures')
export class CaptureController {
  constructor(private readonly captures: CaptureService) {}

  /** Create a capture. 202 Accepted (persisted + handed off). p95 target < 300 ms. */
  @Post()
  @HttpCode(202)
  create(
    @CurrentUser() user: AuthenticatedUser,
    @Headers('idempotency-key') idempotencyKey: string | undefined,
    @Body() dto: CreateCaptureDto,
  ): Promise<CaptureResponse> {
    if (!idempotencyKey || idempotencyKey.trim() === '') {
      throw new BadRequestException({
        code: 'missing_idempotency_key',
        message: 'The Idempotency-Key header is required.',
      });
    }
    return this.captures.create(user.id, idempotencyKey, dto);
  }

  /**
   * Create a capture from a VOICE NOTE sent as the raw request body
   * (`Content-Type: audio/*`, ≤ 10 MB). Transcribed and discarded (ADR-021).
   * Metadata travels in the query string: `client_id`, `occurred_at`,
   * `duration_ms`. 202 with the transcript in `content`.
   */
  @Post('voice')
  @HttpCode(202)
  @Throttle({ default: { limit: 20, ttl: 60_000 } })
  async createVoice(
    @CurrentUser() user: AuthenticatedUser,
    @Headers('idempotency-key') idempotencyKey: string | undefined,
    @Headers('content-type') contentType: string | undefined,
    @Query('client_id') clientId: string | undefined,
    @Query('occurred_at') occurredAt: string | undefined,
    @Query('duration_ms') durationMs: string | undefined,
    @Req() req: Request,
  ): Promise<CaptureResponse> {
    if (!idempotencyKey || idempotencyKey.trim() === '') {
      throw new BadRequestException({
        code: 'missing_idempotency_key',
        message: 'The Idempotency-Key header is required.',
      });
    }
    if (clientId !== undefined && !isUUID(clientId)) {
      throw new BadRequestException({
        code: 'validation_error',
        message: 'client_id must be a UUID.',
      });
    }
    if (occurredAt !== undefined && !isISO8601(occurredAt)) {
      throw new BadRequestException({
        code: 'validation_error',
        message: 'occurred_at must be ISO-8601.',
      });
    }
    const duration = durationMs !== undefined ? Number(durationMs) : undefined;
    const audio = await readRawBody(req, VOICE_MAX_BYTES);
    return this.captures.createVoice(user.id, idempotencyKey, {
      audio,
      contentType: contentType ?? '',
      clientId,
      occurredAt,
      durationMs: Number.isFinite(duration) ? duration : undefined,
    });
  }

  /** Presign a direct-to-S3 upload for a voice capture. */
  @Post('audio-upload')
  @HttpCode(200)
  presignAudio(
    @CurrentUser() user: AuthenticatedUser,
    @Body() dto: PresignAudioDto,
  ): Promise<PresignUploadResult> {
    return this.captures.presignAudioUpload(user.id, dto);
  }

  /** Read one own capture. 404 if it is not the caller's; 400 for a bad UUID. */
  @Get(':id')
  findOne(
    @CurrentUser() user: AuthenticatedUser,
    @Param('id', ParseUUIDPipe) id: string,
  ): Promise<CaptureResponse> {
    return this.captures.findOne(user.id, id);
  }

  /** Cursor-paginated list of the caller's own captures. */
  @Get()
  list(
    @CurrentUser() user: AuthenticatedUser,
    @Query() query: ListCapturesQueryDto,
  ): Promise<CaptureListPage> {
    return this.captures.list(user.id, query);
  }
}
