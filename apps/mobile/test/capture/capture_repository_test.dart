import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindos/src/features/capture/data/capture_repository.dart';
import 'package:mindos/src/features/capture/data/local/app_database.dart';
import 'package:mindos/src/features/capture/data/local/capture_tables.dart';

// Feature: capture-engine — offline outbox (R6.1)
//
// NOTE: These tests require a Flutter/Dart SDK with the native sqlite3 library
// available to `NativeDatabase`. They were written but NOT executed here (the
// sandbox has no Flutter SDK). Run with: `cd apps/mobile && flutter test`.
void main() {
  late AppDatabase db;
  late CaptureRepository repo;

  setUp(() {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
    repo = CaptureRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('CaptureRepository (optimistic offline write)', () {
    test('saveText inserts a pending row with a generated client_id', () async {
      final clientId = await repo.saveText(content: 'hello world');

      final row = await repo.findByClientId(clientId);
      expect(row, isNotNull);
      expect(row!.type, CaptureKind.text);
      expect(row.content, 'hello world');
      expect(row.syncState, SyncState.pending);
      expect(row.serverId, isNull);
      expect(row.retryCount, 0);
    });

    test('saveVoice stores the local audio path and no audio_ref yet',
        () async {
      final clientId =
          await repo.saveVoice(audioLocalPath: '/tmp/rec-1.m4a');

      final row = await repo.findByClientId(clientId);
      expect(row!.type, CaptureKind.voice);
      expect(row.audioLocalPath, '/tmp/rec-1.m4a');
      expect(row.audioRef, isNull);
      expect(row.syncState, SyncState.pending);
    });

    test('client_ids are unique across captures', () async {
      final a = await repo.saveText(content: 'a');
      final b = await repo.saveText(content: 'b');
      expect(a, isNot(equals(b)));
    });

    test('watchCaptures emits newest-first', () async {
      final base = DateTime.utc(2026, 1, 1, 12);
      await repo.saveText(content: 'old', createdAtLocal: base);
      await repo.saveText(
        content: 'new',
        createdAtLocal: base.add(const Duration(minutes: 5)),
      );

      final captures = await repo.watchCaptures().first;
      expect(captures.map((c) => c.content).toList(), ['new', 'old']);
    });
  });

  group('offline persistence across app restarts (R6.1)', () {
    test('captures survive closing and reopening the database', () async {
      final dir = await Directory.systemTemp.createTemp('mindos_test');
      final file = File('${dir.path}/mindos.sqlite');
      try {
        final first = AppDatabase.withExecutor(NativeDatabase(file));
        final repoA = CaptureRepository(first);
        final clientId = await repoA.saveText(content: 'persist me');
        await first.close();

        // Reopen a fresh database over the same file (simulates app restart).
        final second = AppDatabase.withExecutor(NativeDatabase(file));
        final repoB = CaptureRepository(second);
        final row = await repoB.findByClientId(clientId);
        expect(row, isNotNull);
        expect(row!.content, 'persist me');
        expect(row.syncState, SyncState.pending);
        await second.close();
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });
}
