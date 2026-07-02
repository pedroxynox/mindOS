import 'package:drift/drift.dart';

/// Sync-state machine values for a locally stored capture (design.md §11.1/§11.2).
///
/// Lifecycle:
///   pending -> uploadingAudio -> syncing -> synced      (happy path)
///   pending -> ... -> failed                            (terminal validation error, 4xx)
///
/// Transient errors (5xx / timeout / no network) keep the row in [pending] with
/// an incremented `retryCount` and a future `nextAttemptAt` (exponential
/// backoff), so it is re-read by the outbox drain. [failed] is terminal for the
/// automatic drain: a 4xx validation error is not retried automatically (R6.6)
/// and is surfaced for manual review.
abstract class SyncState {
  static const String pending = 'pending';
  static const String uploadingAudio = 'uploading_audio';
  static const String syncing = 'syncing';
  static const String synced = 'synced';
  static const String failed = 'failed';
}

/// Capture modality values persisted locally. Mirrors the API `type` field.
abstract class CaptureKind {
  static const String text = 'text';
  static const String voice = 'voice';
}

/// Local outbox table for offline-first captures (design.md §11.1).
///
/// Every capture is written here first (optimistic save) and later drained to
/// the API by the [SyncService]. `clientId` is a device-generated UUID v4 that
/// doubles as the API `Idempotency-Key`, guaranteeing that re-sending the same
/// capture never creates a duplicate server-side (P9 / R6.4).
@DataClassName('LocalCapture')
class LocalCaptures extends Table {
  /// UUID v4 generated on the device. Used as the API `Idempotency-Key`.
  TextColumn get clientId => text()();

  /// 'text' | 'voice' (see [CaptureKind]).
  TextColumn get type => text()();

  /// Raw text or (optional) voice transcription.
  TextColumn get content => text().nullable()();

  /// Local filesystem path to the recorded audio, before it is uploaded.
  TextColumn get audioLocalPath => text().nullable()();

  /// S3 object key returned by the presign step, once the audio is uploaded.
  TextColumn get audioRef => text().nullable()();

  /// When the event actually happened, if the user knows it (#03 §9).
  DateTimeColumn get occurredAt => dateTime().nullable()();

  /// When the capture was saved on the device (drives FIFO ordering).
  DateTimeColumn get createdAtLocal => dateTime()();

  /// Current sync-state (see [SyncState]). Defaults to `pending`.
  TextColumn get syncState =>
      text().withDefault(const Constant(SyncState.pending))();

  /// The server `capture_id` returned once synced.
  TextColumn get serverId => text().nullable()();

  /// Number of transient sync failures so far (drives the backoff).
  IntColumn get retryCount => integer().withDefault(const Constant(0))();

  /// Earliest time the row is eligible for a (re)attempt. `null` == eligible now
  /// for `pending` rows; used to space out retries with exponential backoff.
  DateTimeColumn get nextAttemptAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {clientId};
}
