import {
  BadRequestException,
  ForbiddenException,
  Inject,
  Injectable,
  Logger,
  UnprocessableEntityException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import {
  GetObjectCommand,
  HeadObjectCommand,
  PutObjectCommand,
  S3Client,
} from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { randomUUID } from 'node:crypto';

/**
 * DI token for the S3-compatible client. The concrete client (MinIO locally,
 * Cloudflare R2 in production) is provided by CaptureModule from environment
 * configuration, so this service stays backend-agnostic and unit-testable with
 * a substitute client (design.md §9, ADR-012 D6).
 */
export const S3_CLIENT = Symbol('S3_CLIENT');

/** Result of a presigned upload request returned to the mobile client. */
export interface PresignUploadResult {
  upload_url: string;
  audio_ref: string;
  expires_in: number;
}

/**
 * Allowlisted audio content types mapped to their canonical file extension.
 * Anything outside this map is rejected before a URL is ever signed (R2.2).
 */
const CONTENT_TYPE_EXT: Readonly<Record<string, string>> = {
  'audio/m4a': 'm4a',
  'audio/mpeg': 'mp3',
  'audio/webm': 'webm',
};

/** Hard cap on uploadable audio size: 25 MB (design.md §9, R2.2). */
const MAX_AUDIO_BYTES = 25 * 1024 * 1024;

/** Default lifetime of presigned URLs in seconds (short-lived; design.md §9). */
const DEFAULT_PRESIGN_TTL = 300;

/**
 * Voice-blob storage over an S3-compatible backend.
 *
 * Responsibilities (design.md §9):
 *  - `presignUpload`: validate content type / size, mint an object key
 *    namespaced under the owner (`audio/{user_id}/{uuid}.{ext}`) and return a
 *    short-lived presigned PUT URL so the client uploads the binary directly to
 *    S3 (the audio never transits the API — protects the p95 SLO).
 *  - `assertOwnedAndExists`: enforce that an `audio_ref` is namespaced under the
 *    caller's `user_id` AND that the object actually exists (HeadObject).
 *  - `presignDownload`: short-lived presigned GET URL for later playback / F2.
 *
 * The user-id prefix keeps voice blobs isolated even outside PostgreSQL RLS
 * (which only protects the database), satisfying property P6.
 */
@Injectable()
export class BlobStorageService {
  private readonly logger = new Logger(BlobStorageService.name);
  private readonly bucket: string;
  private readonly presignTtl: number;

  constructor(
    @Inject(S3_CLIENT) private readonly s3: S3Client,
    config: ConfigService,
  ) {
    this.bucket = config.get<string>('S3_BUCKET') ?? 'mindos-audio';
    const ttl = Number(config.get<string>('S3_PRESIGN_TTL'));
    this.presignTtl =
      Number.isFinite(ttl) && ttl > 0 ? ttl : DEFAULT_PRESIGN_TTL;
  }

  /**
   * Mint a presigned PUT URL for a new audio object owned by `userId`.
   * Rejects (400) unsupported content types and out-of-range sizes before any
   * key is generated or URL signed.
   */
  async presignUpload(
    userId: string,
    contentType: string,
    sizeBytes: number,
  ): Promise<PresignUploadResult> {
    const ext = CONTENT_TYPE_EXT[contentType];
    if (!ext) {
      throw new BadRequestException({
        code: 'validation_error',
        message: `Unsupported content_type '${contentType}'.`,
      });
    }
    if (!Number.isInteger(sizeBytes) || sizeBytes <= 0) {
      throw new BadRequestException({
        code: 'validation_error',
        message: 'size_bytes must be a positive integer.',
      });
    }
    if (sizeBytes > MAX_AUDIO_BYTES) {
      throw new BadRequestException({
        code: 'validation_error',
        message: `size_bytes exceeds the ${MAX_AUDIO_BYTES}-byte limit.`,
      });
    }

    const audioRef = `audio/${userId}/${randomUUID()}.${ext}`;
    const command = new PutObjectCommand({
      Bucket: this.bucket,
      Key: audioRef,
      ContentType: contentType,
      ContentLength: sizeBytes,
    });
    const uploadUrl = await getSignedUrl(this.s3, command, {
      expiresIn: this.presignTtl,
    });

    return {
      upload_url: uploadUrl,
      audio_ref: audioRef,
      expires_in: this.presignTtl,
    };
  }

  /**
   * Assert that `audioRef` is owned by `userId` (key prefix) and exists in S3.
   * A foreign prefix yields 403; a missing object yields 422 (design.md §13).
   */
  async assertOwnedAndExists(userId: string, audioRef: string): Promise<void> {
    this.assertOwnedPrefix(userId, audioRef);
    try {
      await this.s3.send(
        new HeadObjectCommand({ Bucket: this.bucket, Key: audioRef }),
      );
    } catch (error) {
      this.logger.warn(
        `HeadObject failed for '${audioRef}': ${(error as Error).message}`,
      );
      throw new UnprocessableEntityException({
        code: 'audio_ref_not_found',
        message: 'The referenced audio object does not exist.',
      });
    }
  }

  /** Short-lived presigned GET URL for reading an owned audio object. */
  async presignDownload(userId: string, audioRef: string): Promise<string> {
    this.assertOwnedPrefix(userId, audioRef);
    const command = new GetObjectCommand({
      Bucket: this.bucket,
      Key: audioRef,
    });
    return getSignedUrl(this.s3, command, { expiresIn: this.presignTtl });
  }

  /** Reject any key whose prefix does not namespace it under `userId` (403). */
  private assertOwnedPrefix(userId: string, audioRef: string): void {
    const prefix = `audio/${userId}/`;
    if (!audioRef.startsWith(prefix)) {
      throw new ForbiddenException({
        code: 'forbidden',
        message: 'The audio_ref does not belong to the authenticated user.',
      });
    }
  }
}
