import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindos/src/features/capture/capture_providers.dart';
import 'package:mindos/src/features/capture/data/local/app_database.dart';
import 'package:mindos/src/features/capture/data/local/capture_tables.dart';
import 'package:mindos/src/features/capture/data/sync_service.dart';
import 'package:mindos/src/features/capture/presentation/capture_screen.dart';
import 'package:mindos/src/features/capture/voice/voice_record_sheet.dart';
import 'package:mindos/src/features/capture/voice/voice_recorder.dart';
import 'package:mindos/src/theme.dart';

import 'fake_capture_api.dart';

/// A recorder that "hears" a fixed clip, or refuses the microphone.
class _FakeRecorder implements VoiceRecorder {
  _FakeRecorder({this.denied = false});
  final bool denied;
  bool started = false;

  @override
  Future<void> start() async {
    if (denied) {
      throw const MicrophoneUnavailable('Necesito permiso para usar el micrófono.');
    }
    started = true;
  }

  @override
  Future<RecordedAudio?> stop() async => RecordedAudio(
        bytes: Uint8List.fromList(List.filled(64, 3)),
        mimeType: 'audio/webm',
        durationMs: 3200,
      );

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() async {}
}

class _NoopSync extends SyncService {
  _NoopSync({required super.db, required super.api})
      : super(audioReader: (_) async => const <int>[]);

  @override
  Future<SyncReport> drainOnce({DateTime? now}) async =>
      const SyncReport(attempted: 0, synced: 0, failed: 0, retried: 0);
}

// Recording a voice note stores it in the offline outbox (bytes + MIME +
// duration) and shows it in the list; a refused microphone explains why.
// Bounded pumps only: the presence sphere animates forever.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.withExecutor(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<void> pumpScreen(WidgetTester tester, _FakeRecorder recorder) async {
    final api = FakeCaptureApi();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        captureApiClientProvider.overrideWith((ref) => api),
        syncServiceProvider.overrideWithValue(_NoopSync(db: db, api: api)),
        voiceRecorderFactoryProvider.overrideWithValue(() => recorder),
      ],
      child: MaterialApp(theme: AppTheme.dark(), home: const CaptureScreen()),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> teardown(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5)); // snackbar timer
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 600));
  }

  testWidgets('records a voice note into the offline outbox', (tester) async {
    final recorder = _FakeRecorder();
    await pumpScreen(tester, recorder);

    await tester.tap(find.byTooltip('Grabar nota de voz'));
    await settle(tester);
    expect(recorder.started, isTrue);
    expect(find.text('Te escucho…'), findsOneWidget);

    await tester.tap(find.text('Guardar').last);
    await settle(tester);

    final rows = await db.allCaptures();
    expect(rows, hasLength(1));
    expect(rows.single.type, CaptureKind.voice);
    expect(rows.single.audioData, hasLength(64));
    expect(rows.single.audioMime, 'audio/webm');
    expect(rows.single.audioDurationMs, 3200);
    expect(find.text('Nota de voz · 0:03'), findsOneWidget);

    await teardown(tester);
  });

  testWidgets('explains when the microphone is not allowed', (tester) async {
    await pumpScreen(tester, _FakeRecorder(denied: true));

    await tester.tap(find.byTooltip('Grabar nota de voz'));
    await settle(tester);

    expect(find.textContaining('permiso para usar el micrófono'), findsOneWidget);
    await tester.tap(find.text('Cerrar'));
    await settle(tester);
    expect(await db.allCaptures(), isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 600));
  });
}
