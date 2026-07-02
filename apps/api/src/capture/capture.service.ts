import {
  BadRequestException,
  Inject,
  Injectable,
  Logger,
  NotFoundException,
} from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaRlsService } from '../prisma/prisma-rls.service';
import {
  BlobStorageService,
  PresignUploadResult,
} from './blob-storage.service';
import { CaptureResponse, toCaptureResponse } from './capture.mapper';
import { CreateCaptureDto, CaptureType } from './dto/create-capture.dto';
import { ListCapturesQueryDto } from './dto/list-captures-query.dto';
import { PresignAudioDto } from './dto/presign-audio.dto';
import { IdempotencyService } from './idempotency.service';
import {
  UNDERSTANDING_QUEUE_PORT,
  UnderstandingQueuePort,
} from './understanding.queue.port';

/** A page of captures returned by the list endpoint. */
export interface CaptureListPage {
  data: CaptureResponse[];
  next_cursor: string | null;
}

/**
 * Domain service that orchestrates the synchronous capture path
 * (design.md §8): idempotency -> (voice) blob check -> persist -> enqueue.
 *
 * Invariants:
 *  - The capture is persisted BEFORE anything is enqueued; a failed enqueue
 *    never fails the request (the capture is already safe — P2, R5.1/R5.2).
 *  - `user_id` always comes from the verified JWT, never the body (R1.3).
 *  - `occurred_at <= created_at` (temporal coherence — P5, R8).
 */
@Injectable()
export class CaptureService {
  private readonly logger = new Logger(CaptureService.name);

  constructor(
    private readonly rls: PrismaRlsService,
    private readonly idempotency: IdempotencyService,
    private readonly blobs: BlobStorageService,
    @Inject(UNDERSTANDING_QUEUE_PORT)
    private readonly queue: UnderstandingQueuePort,
  ) {}

  /** Create a capture (or return the prior one for an idempotent replay). */
  async create(
    userId: string,
    key: string,
    dto: CreateCaptureDto,
  ): Promise<CaptureResponse> {
    // 1) Idempotency: an exact replay returns the original response; a reuse
    //    with a different payload throws 409 inside lookup.
    const prior = await this.idempotency.lookup(userId, key, dto);
    if (prior) {
      return prior;
    }

    // 2) Payload coherence beyond the DTO shape.
    if (dto.type === CaptureType.text && !dto.content?.trim()) {
      throw new BadRequestException({
        code: 'validation_error',
        message: 'Text captures require non-empty content.',
      });
    }
    const occurredAt = this.resolveOccurredAt(dto.occurred_at);

    // 3) Voice: the referenced audio must belong to this user and exist in S3.
    if (dto.type === CaptureType.voice && dto.audio_ref) {
      await this.blobs.assertOwnedAndExists(userId, dto.audio_ref);
    }

    // 4) Persist the raw capture + idempotency record in ONE RLS transaction.
    //    The capture is safe before anything is enqueued.
    const capture = await this.rls.withUser(userId, async (tx) => {
      const node = await tx.node.create({
        data: {
          userId,
          type: 'capture',
          status: 'raw',
          origin: dto.type === CaptureType.voice ? 'voice' : 'manual_text',
          body: dto.content ?? null,
          attributes: dto.audio_ref
            ? { audio_ref: dto.audio_ref, modality: dto.type }
            : { modality: dto.type },
          occurredAt,
        },
      });
      await this.idempotency.store(tx, {
        userId,
        key,
        captureId: node.id,
        dto,
      });
      return node;
    });

    const response = toCaptureResponse(capture);

    // 5) Hand off to understanding (F2). A failure here must NOT break the 202:
    //    the reconciliation sweep (task 9) re-enqueues raw captures.
    try {
      await this.queue.enqueueUnderstanding({
        schema_version: 1,
        capture_id: capture.id,
        user_id: userId,
        enqueued_at: new Date().toISOString(),
      });
    } catch (error) {
      this.logger.error(
        `Enqueue failed for capture ${capture.id}; it is persisted and will be ` +
          `reconciled. Cause: ${(error as Error).message}`,
      );
    }

    return response;
  }

  /** Mint a presigned upload URL for a voice capture (design.md §7.1). */
  presignAudioUpload(
    userId: string,
    dto: PresignAudioDto,
  ): Promise<PresignUploadResult> {
    return this.blobs.presignUpload(userId, dto.content_type, dto.size_bytes);
  }

  /** Read one own capture; 404 if it is not the caller's (RLS + filter). */
  async findOne(userId: string, id: string): Promise<CaptureResponse> {
    const node = await this.rls.withUser(userId, (tx) =>
      tx.node.findFirst({ where: { id, userId, type: 'capture' } }),
    );
    if (!node) {
      throw new NotFoundException({
        code: 'not_found',
        message: 'Capture not found.',
      });
    }
    return toCaptureResponse(node);
  }

  /** Cursor-paginated list of the caller's own captures (design.md §7.1). */
  async list(
    userId: string,
    query: ListCapturesQueryDto,
  ): Promise<CaptureListPage> {
    const take = query.limit;
    const where: Prisma.NodeWhereInput = {
      userId,
      type: 'capture',
      ...(query.status ? { status: query.status } : {}),
    };

    const rows = await this.rls.withUser(userId, (tx) =>
      tx.node.findMany({
        where,
        orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
        take: take + 1,
        ...(query.cursor ? { cursor: { id: query.cursor }, skip: 1 } : {}),
      }),
    );

    let nextCursor: string | null = null;
    if (rows.length > take) {
      const overflow = rows.pop();
      nextCursor = overflow ? overflow.id : null;
    }

    return { data: rows.map(toCaptureResponse), next_cursor: nextCursor };
  }

  /**
   * Validate and normalise `occurred_at`: absent -> null; present must not be in
   * the future relative to the server clock (so `occurred_at <= created_at`).
   */
  private resolveOccurredAt(occurredAt?: string): Date | null {
    if (!occurredAt) {
      return null;
    }
    const parsed = new Date(occurredAt);
    if (Number.isNaN(parsed.getTime())) {
      throw new BadRequestException({
        code: 'validation_error',
        message: 'occurred_at is not a valid ISO-8601 timestamp.',
      });
    }
    if (parsed.getTime() > Date.now()) {
      throw new BadRequestException({
        code: 'validation_error',
        message: 'occurred_at cannot be in the future.',
      });
    }
    return parsed;
  }
}
