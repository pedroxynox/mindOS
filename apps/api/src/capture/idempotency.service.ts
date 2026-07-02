import { ConflictException, Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { createHash } from 'node:crypto';
import { PrismaRlsService } from '../prisma/prisma-rls.service';
import { CaptureResponse, toCaptureResponse } from './capture.mapper';
import { CreateCaptureDto } from './dto/create-capture.dto';

/** Parameters to persist an idempotency record inside the capture transaction. */
export interface StoreIdempotencyParams {
  userId: string;
  key: string;
  captureId: string;
  dto: CreateCaptureDto;
}

/**
 * Resolves `Idempotency-Key` semantics for `POST /v1/captures`
 * (design.md §7.2, §8):
 *
 *  - new key                       -> `lookup` returns null (caller proceeds).
 *  - repeated key, same payload    -> returns the original CaptureResponse.
 *  - repeated key, different payload -> throws 409 (idempotency_key_reuse).
 *
 * Uniqueness is `(user_id, key)`; `request_hash` is a deterministic hash of the
 * payload used to detect reuse with a different body. `store` runs inside the
 * same RLS transaction that creates the capture (wired by CaptureService), so
 * the capture and its idempotency record commit atomically (R3.4).
 */
@Injectable()
export class IdempotencyService {
  constructor(private readonly rls: PrismaRlsService) {}

  /**
   * Deterministic hash of the request payload. Canonicalises the fields that
   * define a capture so semantically-equal payloads hash equally regardless of
   * key order or absent-vs-undefined fields.
   */
  hashPayload(dto: CreateCaptureDto): string {
    const canonical = JSON.stringify({
      type: dto.type,
      content: dto.content ?? null,
      audio_ref: dto.audio_ref ?? null,
      occurred_at: dto.occurred_at ?? null,
      client_id: dto.client_id ?? null,
    });
    return createHash('sha256').update(canonical).digest('hex');
  }

  /**
   * Look up a prior capture for `(userId, key)`.
   * @returns the original response for an exact replay, or null for a new key.
   * @throws ConflictException (409) when the key was used with a different body.
   */
  async lookup(
    userId: string,
    key: string,
    dto: CreateCaptureDto,
  ): Promise<CaptureResponse | null> {
    const requestHash = this.hashPayload(dto);
    return this.rls.withUser(userId, async (tx) => {
      const existing = await tx.idempotencyKey.findUnique({
        where: { uq_idempotency_user_key: { userId, key } },
      });
      if (!existing) {
        return null;
      }
      if (existing.requestHash !== requestHash) {
        throw new ConflictException({
          code: 'idempotency_key_reuse',
          message:
            'This Idempotency-Key was already used with a different payload.',
        });
      }
      const capture = await tx.node.findUnique({
        where: { id: existing.captureId },
      });
      // Defensive: the FK cascade keeps these in sync, but treat a missing
      // capture as a new key rather than returning a broken response.
      return capture ? toCaptureResponse(capture) : null;
    });
  }

  /**
   * Persist the idempotency record for a freshly created capture. MUST be
   * called with the transaction client from the capture-creation transaction so
   * both rows commit together.
   */
  async store(
    tx: Prisma.TransactionClient,
    params: StoreIdempotencyParams,
  ): Promise<void> {
    const { userId, key, captureId, dto } = params;
    await tx.idempotencyKey.create({
      data: {
        userId,
        key,
        captureId,
        requestHash: this.hashPayload(dto),
      },
    });
  }
}
