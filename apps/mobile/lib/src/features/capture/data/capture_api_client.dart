import 'dart:convert';

import 'package:http/http.dart' as http;

/// Result of a successful `POST /v1/captures` (2xx).
class CreateCaptureResult {
  const CreateCaptureResult({required this.captureId, required this.status});

  final String captureId;
  final String status;

  factory CreateCaptureResult.fromJson(Map<String, dynamic> json) {
    return CreateCaptureResult(
      captureId: json['capture_id'] as String,
      status: json['status'] as String,
    );
  }
}

/// Result of `POST /v1/captures/audio-upload` (presign).
class PresignResult {
  const PresignResult({
    required this.uploadUrl,
    required this.audioRef,
    required this.expiresIn,
  });

  final String uploadUrl;
  final String audioRef;
  final int expiresIn;

  factory PresignResult.fromJson(Map<String, dynamic> json) {
    return PresignResult(
      uploadUrl: json['upload_url'] as String,
      audioRef: json['audio_ref'] as String,
      expiresIn: json['expires_in'] as int,
    );
  }
}

/// Thrown for non-retryable `4xx` validation errors (design.md §11.2, R6.6).
/// The [SyncService] marks the capture `failed` without retrying.
class CaptureValidationException implements Exception {
  const CaptureValidationException(this.statusCode, [this.body]);

  final int statusCode;
  final String? body;

  @override
  String toString() => 'CaptureValidationException($statusCode): $body';
}

/// Thrown for retryable failures: `5xx`, timeouts or no network (design.md
/// §11.2, R6.5). The [SyncService] applies exponential backoff and retries.
class CaptureTransientException implements Exception {
  const CaptureTransientException(this.message, [this.statusCode]);

  final String message;
  final int? statusCode;

  @override
  String toString() => 'CaptureTransientException($statusCode): $message';
}

/// Contract the [SyncService] depends on. Kept as an interface so tests can
/// substitute an in-memory fake that honours idempotency by `(user, key)`.
abstract class CaptureApiClient {
  /// Presign a direct-to-S3 upload for a voice capture.
  Future<PresignResult> presignAudio({
    required String contentType,
    required int sizeBytes,
  });

  /// Upload the audio bytes to the presigned S3 URL (PUT).
  Future<void> uploadAudio({
    required String uploadUrl,
    required List<int> bytes,
    required String contentType,
  });

  /// Create a capture. `idempotencyKey` is the outbox `clientId`.
  ///
  /// Returns a [CreateCaptureResult] on `2xx`; throws
  /// [CaptureValidationException] on `4xx`; throws [CaptureTransientException]
  /// on `5xx` / timeout / network failure.
  Future<CreateCaptureResult> createCapture({
    required String idempotencyKey,
    required Map<String, dynamic> body,
  });
}

/// HTTP implementation talking to the NestJS Capture API (design.md §7).
///
/// The bearer token is resolved lazily via [tokenProvider] so the client always
/// uses the current access token.
class HttpCaptureApiClient implements CaptureApiClient {
  HttpCaptureApiClient({
    required Future<String?> Function() tokenProvider,
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
  })  : _tokenProvider = tokenProvider,
        _client = client ?? http.Client();

  final Future<String?> Function() _tokenProvider;
  final http.Client _client;
  final Duration timeout;

  static const String _baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:3000/v1',
  );

  Future<Map<String, String>> _authHeaders() async {
    final token = await _tokenProvider();
    return {
      'content-type': 'application/json',
      if (token != null) 'authorization': 'Bearer $token',
    };
  }

  @override
  Future<PresignResult> presignAudio({
    required String contentType,
    required int sizeBytes,
  }) async {
    try {
      final response = await _client
          .post(
            Uri.parse('$_baseUrl/captures/audio-upload'),
            headers: await _authHeaders(),
            body: jsonEncode({
              'content_type': contentType,
              'size_bytes': sizeBytes,
            }),
          )
          .timeout(timeout);

      if (response.statusCode == 200) {
        return PresignResult.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>,
        );
      }
      _throwForStatus(response.statusCode, response.body);
    } on CaptureValidationException {
      rethrow;
    } on CaptureTransientException {
      rethrow;
    } catch (e) {
      // SocketException, TimeoutException, etc. -> retryable.
      throw CaptureTransientException('presignAudio failed: $e');
    }
  }

  @override
  Future<void> uploadAudio({
    required String uploadUrl,
    required List<int> bytes,
    required String contentType,
  }) async {
    try {
      final response = await _client
          .put(
            Uri.parse(uploadUrl),
            headers: {'content-type': contentType},
            body: bytes,
          )
          .timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        // A failed upload is transient — the audio can be re-uploaded later.
        throw CaptureTransientException(
          'audio upload failed',
          response.statusCode,
        );
      }
    } on CaptureTransientException {
      rethrow;
    } catch (e) {
      throw CaptureTransientException('uploadAudio failed: $e');
    }
  }

  @override
  Future<CreateCaptureResult> createCapture({
    required String idempotencyKey,
    required Map<String, dynamic> body,
  }) async {
    try {
      final headers = await _authHeaders();
      headers['idempotency-key'] = idempotencyKey;
      final response = await _client
          .post(
            Uri.parse('$_baseUrl/captures'),
            headers: headers,
            body: jsonEncode(body),
          )
          .timeout(timeout);

      // 202 Accepted (created) or 200 OK (already existed) -> success.
      if (response.statusCode == 202 || response.statusCode == 200) {
        return CreateCaptureResult.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>,
        );
      }
      _throwForStatus(response.statusCode, response.body);
    } on CaptureValidationException {
      rethrow;
    } on CaptureTransientException {
      rethrow;
    } catch (e) {
      throw CaptureTransientException('createCapture failed: $e');
    }
  }

  /// Map an HTTP error status onto the right exception type. Never returns.
  Never _throwForStatus(int statusCode, String body) {
    if (statusCode >= 400 && statusCode < 500) {
      // 409 idempotency_key_reuse is a client bug (distinct payload, same key);
      // treat as terminal so we do not spin on it.
      throw CaptureValidationException(statusCode, body);
    }
    throw CaptureTransientException('server error', statusCode);
  }
}
