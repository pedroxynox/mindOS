import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'local/app_database.dart';
import 'local/capture_tables.dart';

/// Offline-first write path for captures (design.md §11.2, layering per #07 §4).
///
/// The repository is the ONLY component the UI talks to for captures. It writes
/// optimistically to the local Drift outbox and never performs network I/O —
/// syncing is the [SyncService]'s job. Each capture is stamped with a
/// device-generated UUID v4 `clientId` that is reused as the API
/// `Idempotency-Key`, so retries can never duplicate the capture (R6.1, R6.4).
class CaptureRepository {
  CaptureRepository(this._db, {Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final AppDatabase _db;
  final Uuid _uuid;

  /// Persist a text capture optimistically. Returns the generated `clientId`.
  Future<String> saveText({
    required String content,
    DateTime? occurredAt,
    DateTime? createdAtLocal,
  }) async {
    final clientId = _uuid.v4();
    await _db.insertCapture(
      LocalCapturesCompanion.insert(
        clientId: clientId,
        type: CaptureKind.text,
        content: Value(content),
        occurredAt: Value(occurredAt),
        createdAtLocal: createdAtLocal ?? DateTime.now(),
      ),
    );
    return clientId;
  }

  /// Persist a voice capture optimistically. The audio lives on disk at
  /// [audioLocalPath] and is uploaded later by the [SyncService]; `content`
  /// may hold a client-side transcription if one is available.
  Future<String> saveVoice({
    required String audioLocalPath,
    String? content,
    DateTime? occurredAt,
    DateTime? createdAtLocal,
  }) async {
    final clientId = _uuid.v4();
    await _db.insertCapture(
      LocalCapturesCompanion.insert(
        clientId: clientId,
        type: CaptureKind.voice,
        content: Value(content),
        audioLocalPath: Value(audioLocalPath),
        occurredAt: Value(occurredAt),
        createdAtLocal: createdAtLocal ?? DateTime.now(),
      ),
    );
    return clientId;
  }

  /// Observable stream of all local captures (newest first) for the UI.
  Stream<List<LocalCapture>> watchCaptures() => _db.watchAllCaptures();

  /// One-shot read of all local captures (newest first).
  Future<List<LocalCapture>> listCaptures() => _db.allCaptures();

  /// Read a single capture by its client id.
  Future<LocalCapture?> findByClientId(String clientId) =>
      _db.captureByClientId(clientId);
}
