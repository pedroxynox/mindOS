import 'package:mindos/src/features/capture/data/capture_api_client.dart';

/// In-memory [CaptureApiClient] that mirrors the server's idempotency contract:
/// creation is keyed by the `Idempotency-Key` (the outbox `clientId`), so the
/// same key never produces a second capture — exactly the guarantee behind
/// Property 9.
class FakeCaptureApi implements CaptureApiClient {
  FakeCaptureApi();

  /// Maps idempotency key -> the single server capture id created for it.
  final Map<String, String> _byKey = {};

  /// Number of distinct server-side captures actually created.
  int createCount = 0;

  /// Total create requests received (including idempotent repeats).
  int createRequests = 0;

  int presignCalls = 0;
  int uploadCalls = 0;

  int _seq = 0;

  /// If > 0, the next N create requests DROP their response after persisting
  /// server-side (simulates a lost 2xx / timeout). This forces the client to
  /// retry against an already-created capture — the classic duplicate risk.
  int dropResponses = 0;

  /// If > 0, the next N create requests fail transiently BEFORE reaching the
  /// server (nothing created). Simulates 5xx / no network.
  int transientBeforeCreate = 0;

  /// If set, the next create request fails with a 4xx validation error.
  bool nextIsValidationError = false;

  @override
  Future<PresignResult> presignAudio({
    required String contentType,
    required int sizeBytes,
  }) async {
    presignCalls++;
    return PresignResult(
      uploadUrl: 'https://s3.local/upload/${_seq++}',
      audioRef: 'audio/user/$_seq.m4a',
      expiresIn: 900,
    );
  }

  @override
  Future<void> uploadAudio({
    required String uploadUrl,
    required List<int> bytes,
    required String contentType,
  }) async {
    uploadCalls++;
  }

  @override
  Future<CreateCaptureResult> createCapture({
    required String idempotencyKey,
    required Map<String, dynamic> body,
  }) async {
    createRequests++;

    if (nextIsValidationError) {
      nextIsValidationError = false;
      throw const CaptureValidationException(400, 'validation_error');
    }

    if (transientBeforeCreate > 0) {
      transientBeforeCreate--;
      throw const CaptureTransientException('server error', 503);
    }

    // Idempotent create keyed by (idempotency key). First time -> create;
    // afterwards -> return the same capture id.
    final existing = _byKey[idempotencyKey];
    final id = existing ?? 'srv-${_seq++}';
    if (existing == null) {
      _byKey[idempotencyKey] = id;
      createCount++;
    }

    if (dropResponses > 0) {
      // Server created (or already had) the capture, but the client never sees
      // the response -> retryable from the client's point of view.
      dropResponses--;
      throw const CaptureTransientException('response lost', null);
    }

    return CreateCaptureResult(captureId: id, status: 'raw');
  }
}
