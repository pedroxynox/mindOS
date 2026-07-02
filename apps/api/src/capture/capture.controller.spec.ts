import { BadRequestException } from '@nestjs/common';
import { AuthenticatedUser } from '../auth/jwt-auth.guard';
import { CaptureController } from './capture.controller';
import { CaptureService } from './capture.service';
import { CaptureType, CreateCaptureDto } from './dto/create-capture.dto';
import { ListCapturesQueryDto } from './dto/list-captures-query.dto';
import { PresignAudioDto } from './dto/presign-audio.dto';

/**
 * Unit tests for CaptureController (task 6.5): the missing-Idempotency-Key
 * guard and delegation to CaptureService with the token's user id.
 */
const USER: AuthenticatedUser = { id: '11111111-1111-1111-1111-111111111111' };

interface ServiceMock {
  create: jest.Mock;
  presignAudioUpload: jest.Mock;
  findOne: jest.Mock;
  list: jest.Mock;
}

function build(): { controller: CaptureController; service: ServiceMock } {
  const service: ServiceMock = {
    create: jest.fn().mockResolvedValue({ capture_id: 'c1' }),
    presignAudioUpload: jest.fn().mockResolvedValue({ upload_url: 'u' }),
    findOne: jest.fn().mockResolvedValue({ capture_id: 'c1' }),
    list: jest.fn().mockResolvedValue({ data: [], next_cursor: null }),
  };
  const controller = new CaptureController(
    service as unknown as CaptureService,
  );
  return { controller, service };
}

const dto: CreateCaptureDto = { type: CaptureType.text, content: 'hi' };

describe('CaptureController', () => {
  it('rejects a request without an Idempotency-Key (400)', async () => {
    const { controller } = build();
    expect(() => controller.create(USER, undefined, dto)).toThrow(
      BadRequestException,
    );
    expect(() => controller.create(USER, '  ', dto)).toThrow(
      BadRequestException,
    );
  });

  it('delegates create to the service with the token user id and key', async () => {
    const { controller, service } = build();
    await controller.create(USER, 'key-1', dto);
    expect(service.create).toHaveBeenCalledWith(USER.id, 'key-1', dto);
  });

  it('delegates audio-upload presign to the service', async () => {
    const { controller, service } = build();
    const body: PresignAudioDto = {
      content_type: 'audio/m4a',
      size_bytes: 1024,
    };
    await controller.presignAudio(USER, body);
    expect(service.presignAudioUpload).toHaveBeenCalledWith(USER.id, body);
  });

  it('delegates findOne to the service with the token user id', async () => {
    const { controller, service } = build();
    await controller.findOne(USER, 'capture-uuid');
    expect(service.findOne).toHaveBeenCalledWith(USER.id, 'capture-uuid');
  });

  it('delegates list to the service with the token user id', async () => {
    const { controller, service } = build();
    const query: ListCapturesQueryDto = { limit: 20 };
    await controller.list(USER, query);
    expect(service.list).toHaveBeenCalledWith(USER.id, query);
  });
});
