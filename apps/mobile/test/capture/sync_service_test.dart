import 'dart:math';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindos/src/features/capture/data/capture_repository.dart';
import 'package:mindos/src/features/capture/data/local/app_database.dart';
import 'package:mindos/src/features/capture/data/local/capture_tables.dart';
import 'package:mindos/src/features/capture/data/sync_service.dart';

import 'fake_capture_api.dart';

// Feature: capture-engine, Property 9: Sync offline idempotente
//
// NOTE: These tests require a Flutter/Dart SDK with the native sqlite3 library.
// They were written but NOT executed in this environment (no Flutter SDK).
// Run with: `cd apps/mobile && flutter test`.
void main() {
  late AppDatabase db;
  late CaptureRepository repo;
  late FakeCaptureApi api;
  late SyncService sync;

  // Deterministic audio reader — never touches the filesystem.
  Future<List<int>> fakeAudioReader(String _) async => List<int>.filled(16, 7);

  SyncService buildSync() => SyncService(
        db: db,
        api: api,
        audioReader: fakeAudioReader,
        baseBackoff: const Duration(seconds: 2),
      );

  setUp(() {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
    repo = CaptureRepository(db);
    api = FakeCaptureApi();
    sync = buildSync();
  });

  tearDown(() async {
    await db.close();
  });

  group('SyncService state machine', () {
    test('text capture happy path -> synced + server_id', () async {
      final clientId = await repo.saveText(content: 'sync me');

      final report = await sync.drainOnce();

      expect(report.synced, 1);
      final row = await repo.findByClientId(clientId);
      expect(row!.syncState, SyncState.synced);
      expect(row.serverId, isNotNull);
      expect(api.createCount, 1);
    });

    test('4xx validation error -> failed with no auto-retry (R6.6)', () async {
      final clientId = await repo.saveText(content: 'bad');
      api.nextIsValidationError = true;

      final report = await sync.drainOnce();
      expect(report.failed, 1);

      final row = await repo.findByClientId(clientId);
      expect(row!.syncState, SyncState.failed);
      expect(row.nextAttemptAt, isNull);

      // A subsequent drain must NOT pick the failed row back up.
      final second = await sync.drainOnce();
      expect(second.attempted, 0);
    });

    test('5xx/transient -> stays pending, retry_count++ and backoff (R6.5)',
        () async {
      final now = DateTime.utc(2026, 1, 1, 12);
      final clientId = await repo.saveText(content: 'flaky');
      api.transientBeforeCreate = 1;

      final report = await sync.drainOnce(now: now);
      expect(report.retried, 1);

      final row = await repo.findByClientId(clientId);
      expect(row!.syncState, SyncState.pending);
      expect(row.retryCount, 1);
      expect(row.nextAttemptAt, isNotNull);
      // base * 2^0 = 2s after now.
      expect(
        row.nextAttemptAt!.isAtSameMomentAs(now.add(const Duration(seconds: 2))),
        isTrue,
      );
      expect(api.createCount, 0);
    });

    test('backoff grows exponentially with retry_count', () async {
      final now = DateTime.utc(2026, 1, 1, 12);
      final clientId = await repo.saveText(content: 'flaky');

      // First failure: delay = 2s * 2^0 = 2s.
      api.transientBeforeCreate = 1;
      await sync.drainOnce(now: now);
      var row = await repo.findByClientId(clientId);
      expect(row!.retryCount, 1);
      expect(
        row.nextAttemptAt!.isAtSameMomentAs(now.add(const Duration(seconds: 2))),
        isTrue,
      );

      // Second failure (attempt after it is due): delay = 2s * 2^1 = 4s.
      final later = now.add(const Duration(seconds: 3));
      api.transientBeforeCreate = 1;
      await sync.drainOnce(now: later);
      row = await repo.findByClientId(clientId);
      expect(row!.retryCount, 2);
      expect(
        row.nextAttemptAt!.isAtSameMomentAs(later.add(const Duration(seconds: 4))),
        isTrue,
      );
    });

    test('a not-yet-due retry is skipped by the batch', () async {
      final now = DateTime.utc(2026, 1, 1, 12);
      await repo.saveText(content: 'flaky');
      api.transientBeforeCreate = 1;
      await sync.drainOnce(now: now); // schedules retry at now+2s

      // Draining before the backoff elapses picks up nothing.
      final tooEarly = await sync.drainOnce(now: now.add(const Duration(seconds: 1)));
      expect(tooEarly.attempted, 0);

      // After the backoff, it is eligible again and succeeds.
      final later = await sync.drainOnce(now: now.add(const Duration(seconds: 5)));
      expect(later.synced, 1);
    });

    test('captures are drained in FIFO order (R6.2)', () async {
      final base = DateTime.utc(2026, 1, 1, 12);
      final first =
          await repo.saveText(content: '1', createdAtLocal: base);
      final second = await repo.saveText(
        content: '2',
        createdAtLocal: base.add(const Duration(minutes: 1)),
      );

      await sync.drainOnce();

      // Both synced; the server assigns ids in the order it received them.
      final rowFirst = await repo.findByClientId(first);
      final rowSecond = await repo.findByClientId(second);
      expect(rowFirst!.serverId, 'srv-0');
      expect(rowSecond!.serverId, 'srv-1');
    });

    test('voice capture presigns, uploads and stores audio_ref', () async {
      final clientId =
          await repo.saveVoice(audioLocalPath: '/tmp/rec.m4a');

      final report = await sync.drainOnce();
      expect(report.synced, 1);
      expect(api.presignCalls, 1);
      expect(api.uploadCalls, 1);

      final row = await repo.findByClientId(clientId);
      expect(row!.audioRef, isNotNull);
      expect(row.syncState, SyncState.synced);
    });
  });

  group('Property 9: resend N times with same client_id -> one server capture',
      () {
    test('idempotent under repeated lost responses (>=100 iterations)',
        () async {
      final rng = Random(20260702);
      const iterations = 120;

      for (var i = 0; i < iterations; i++) {
        // Fresh state per iteration.
        await db.close();
        db = AppDatabase.withExecutor(NativeDatabase.memory());
        repo = CaptureRepository(db);
        api = FakeCaptureApi();
        sync = buildSync();

        final isVoice = rng.nextBool();
        final clientId = isVoice
            ? await repo.saveVoice(audioLocalPath: '/tmp/a-$i.m4a')
            : await repo.saveText(content: 'note-$i');

        // Random number of dropped responses (server created it, client never
        // saw the ack) forcing 1..N resends of the SAME client_id.
        final drops = rng.nextInt(5); // 0..4
        api.dropResponses = drops;

        // Drain repeatedly, always advancing well past any backoff window,
        // until the capture is synced (or a safety cap is hit).
        var now = DateTime.utc(2026, 1, 1, 12);
        var guard = 0;
        while (guard < drops + 5) {
          final report = await sync.drainOnce(now: now);
          if (report.attempted == 0 && report.retried == 0) {
            // nothing left eligible
          }
          final row = await repo.findByClientId(clientId);
          if (row!.syncState == SyncState.synced) break;
          now = now.add(const Duration(days: 1));
          guard++;
        }

        final row = await repo.findByClientId(clientId);
        expect(row!.syncState, SyncState.synced,
            reason: 'iteration $i (drops=$drops) should end synced');
        // The core invariant: exactly ONE server capture regardless of resends.
        expect(api.createCount, 1,
            reason: 'iteration $i created ${api.createCount} captures for '
                'client_id $clientId (drops=$drops)');
        // And the create endpoint was hit at least (drops + 1) times.
        expect(api.createRequests, greaterThanOrEqualTo(drops + 1));
      }
    });
  });
}
