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
  UseGuards,
} from '@nestjs/common';
import { AuthenticatedUser } from '../auth/jwt-auth.guard';
import { CurrentUser } from '../auth/current-user.decorator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { PresignUploadResult } from './blob-storage.service';
import { CaptureListPage, CaptureService } from './capture.service';
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
