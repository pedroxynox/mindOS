import 'capture_api_client.dart';
import 'local/app_database.dart';
import 'local/capture_tables.dart';

/// Reads the bytes of a locally recorded audio file. Injected so tests do not
/// touch the real filesystem.
typedef AudioBytesReader = Future<List<int>> Function(String localPath);

/// Content-type used when presigning voice uploads. The device records m4a.
const String _voiceContentType = 'audio/m4a';

/// Summary of a single drain pass, useful for logging/telemetry and tests.
class SyncReport {
  const SyncReport({
    required this.attempted,
    required this.synced,
    required this.failed,
    required this.retried,
  });

  final int attempted;
  final int synced;
  final int failed;
  final int retried;

  @override
  String toString() =>
      'SyncReport(attempted: $attempted, synced: $synced, '
      'failed: $failed, retried: $retried)';
}

/// Drains the offline outbox to the Capture API (design.md §3.3, §11.2).
///
/// Invariants:
///  * FIFO order (R6.2): the oldest pending capture is sent first.
///  * Idempotent (P9 / R6.4): `Idempotency-Key = clientId`, so re-sending the
///    same capture N times still yields exactly one server capture.
///  * Non-lossy (R6.5): transient errors (5xx/timeout/no-net) increment
///    `retryCount` and reschedule with exponential backoff — nothing is dropped.
///  * Validation errors (R6.6): a 4xx marks the row `failed` with no auto-retry.
class SyncService {
  SyncService({
    required AppDatabase db,
    required CaptureApiClient api,
    required AudioBytesReader audioReader,
    this.batchSize = 50,
    this.baseBackoff = const Duration(seconds: 2),
    this.maxBackoff = const Duration(hours: 1),
  })  : _db = db,
        _api = api,
        _audioReader = audioReader;

  final AppDatabase _db;
  final CaptureApiClient _api;
  final AudioBytesReader _audioReader;

  /// Maximum captures processed per drain pass.
  final int batchSize;

  /// Base delay for exponential backoff (delay = base * 2^retryCount).
  final Duration baseBackoff;

  /// Upper bound for a single backoff delay.
  final Duration maxBackoff;

  bool _draining = false;

  /// Drain one FIFO batch of eligible captures. Safe to call on connectivity
  /// regain, periodically, or on app start. Re-entrancy is guarded so
  /// overlapping triggers do not double-send.
  Future<SyncReport> drainOnce({DateTime? now}) async {
    if (_draining) {
      return const SyncReport(attempted: 0, synced: 0, failed: 0, retried: 0);
    }
    _draining = true;
    try {
      final at = (now ?? DateTime.now()).toUtc();
      final batch = await _db.pendingBatch(at, batchSize);
      var synced = 0;
      var failed = 0;
      var retried = 0;
      for (final capture in batch) {
        final outcome = await _syncOne(capture, at);
        switch (outcome) {
          case _Outcome.synced:
            synced++;
          case _Outcome.failed:
            failed++;
          case _Outcome.retry:
            retried++;
        }
      }
      return SyncReport(
        attempted: batch.length,
        synced: synced,
        failed: failed,
        retried: retried,
      );
    } finally {
      _draining = false;
    }
  }

  /// Sync a single capture through the state machine.
  Future<_Outcome> _syncOne(LocalCapture capture, DateTime now) async {
    try {
      var audioRef = capture.audioRef;

      // Voice captures without an audio_ref: presign + upload first.
      if (capture.type == CaptureKind.voice && audioRef == null) {
        final localPath = capture.audioLocalPath;
        if (localPath == null) {
          // A voice capture with neither audio_ref nor a local file cannot be
          // completed — terminal validation error.
          await _db.markFailed(capture.clientId);
          return _Outcome.failed;
        }
        await _db.setSyncState(capture.clientId, SyncState.uploadingAudio);
        final bytes = await _audioReader(localPath);
        final presign = await _api.presignAudio(
          contentType: _voiceContentType,
          sizeBytes: bytes.length,
        );
        await _api.uploadAudio(
          uploadUrl: presign.uploadUrl,
          bytes: bytes,
          contentType: _voiceContentType,
        );
        audioRef = presign.audioRef;
        await _db.setAudioRef(capture.clientId, audioRef);
      }

      await _db.setSyncState(capture.clientId, SyncState.syncing);

      final result = await _api.createCapture(
        idempotencyKey: capture.clientId,
        body: _buildBody(capture, audioRef),
      );

      // 202 created / 200 already existed -> synced (R6.3).
      await _db.markSynced(capture.clientId, result.captureId);
      return _Outcome.synced;
    } on CaptureValidationException {
      // 4xx -> terminal, no automatic retry (R6.6).
      await _db.markFailed(capture.clientId);
      return _Outcome.failed;
    } on CaptureTransientException {
      // 5xx / timeout / no network -> backoff + retry (R6.5).
      await _scheduleBackoff(capture, now);
      return _Outcome.retry;
    }
  }

  /// Build the `POST /v1/captures` body from the local row.
  Map<String, dynamic> _buildBody(LocalCapture capture, String? audioRef) {
    return <String, dynamic>{
      'type': capture.type,
      'client_id': capture.clientId,
      if (capture.content != null) 'content': capture.content,
      if (audioRef != null) 'audio_ref': audioRef,
      if (capture.occurredAt != null)
        'occurred_at': capture.occurredAt!.toUtc().toIso8601String(),
    };
  }

  /// Increment the retry counter and set the next eligible attempt time using
  /// exponential backoff, capped at [maxBackoff].
  Future<void> _scheduleBackoff(LocalCapture capture, DateTime now) async {
    final nextRetry = capture.retryCount + 1;
    // delay = base * 2^(retryCount)  (capped).
    final factor = 1 << capture.retryCount; // 2^retryCount
    var delayMs = baseBackoff.inMilliseconds * factor;
    if (delayMs > maxBackoff.inMilliseconds || delayMs < 0) {
      delayMs = maxBackoff.inMilliseconds;
    }
    final nextAttemptAt = now.add(Duration(milliseconds: delayMs));
    await _db.scheduleRetry(capture.clientId, nextRetry, nextAttemptAt);
  }
}

enum _Outcome { synced, failed, retry }
