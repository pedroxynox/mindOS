import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindos/src/features/capture/capture_providers.dart';
import 'package:mindos/src/features/capture/data/capture_api_client.dart';
import 'package:mindos/src/features/capture/data/local/app_database.dart';
import 'package:mindos/src/features/capture/data/sync_service.dart';
import 'package:mindos/src/features/capture/presentation/capture_screen.dart';

import 'fake_capture_api.dart';

// Feature: capture-engine — capture screen wiring (R6.1).
//
// NOTE: This widget test requires a Flutter SDK (`flutter test`) with the
// native sqlite3 library available to `NativeDatabase`. It was written but NOT
// executed here (the sandbox has no Flutter SDK). Run with:
//   cd apps/mobile && flutter test
//
// The test is intentionally deterministic: it NEVER calls `pumpAndSettle()`.
// The screen shows a `CircularProgressIndicator` while the Drift stream is
// loading (and inside the Guardar button while saving); that indicator animates
// forever, so `pumpAndSettle()` would spin until its timeout and hang CI. We
// instead drive the frames explicitly with bounded `pump()` calls, and we
// override the sync service with a no-op so no background network / backoff
// work is scheduled — the capture simply stays `pending`, which is exactly what
// these assertions verify.

/// A [SyncService] whose drain does nothing and returns immediately. This
/// removes all asynchronous sync noise (network calls, backoff scheduling) from
/// the widget test: the optimistic local write is exercised for real, but the
/// capture is left in the `pending` state and no timers are left dangling.
class _NoopSyncService extends SyncService {
  _NoopSyncService({required AppDatabase db, required CaptureApiClient api})
      : super(db: db, api: api, audioReader: _noAudio);

  static Future<List<int>> _noAudio(String path) async => const <int>[];

  @override
  Future<SyncReport> drainOnce({DateTime? now}) async {
    return const SyncReport(attempted: 0, synced: 0, failed: 0, retried: 0);
  }
}

void main() {
  late AppDatabase db;
  late FakeCaptureApi api;

  setUp(() {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
    api = FakeCaptureApi();
  });

  tearDown(() async {
    await db.close();
  });

  Widget buildHarness() {
    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        // Defensive: never let a real HTTP client be built for this test.
        captureApiClientProvider.overrideWith((ref) => api),
        // Keep the capture `pending`: the drain is a no-op, so there is no
        // async sync work and no pending timers at teardown.
        syncServiceProvider
            .overrideWithValue(_NoopSyncService(db: db, api: api)),
      ],
      child: const MaterialApp(home: CaptureScreen()),
    );
  }

  testWidgets(
      'typing text and tapping Guardar shows the capture as pending in the list',
      (tester) async {
    await tester.pumpWidget(buildHarness());
    // First frame builds the loading spinner; a short bounded pump lets the
    // in-memory Drift stream emit its first (empty) value and clear it.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Aún no hay capturas'), findsOneWidget);

    const content = 'una idea offline-first';
    await tester.enterText(find.byType(TextField), content);
    // Tap the button by its label so the finder is robust to the private
    // FilledButton.icon subtype.
    await tester.tap(find.text('Guardar'));

    // Let the optimistic local write land and the Drift stream re-emit.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // The saved capture appears in the list with a `pending` status.
    expect(find.text(content), findsOneWidget);
    expect(find.text('Pendiente'), findsOneWidget);

    // The input was cleared after a successful save.
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, isEmpty);

    // A success SnackBar arms a ~4s auto-dismiss timer. Drain it explicitly so
    // the test tears down without any pending timers (no pumpAndSettle needed).
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 750));
  });

  testWidgets('empty input is rejected with a validation error',
      (tester) async {
    await tester.pumpWidget(buildHarness());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.text('Guardar'));
    // Validation is synchronous (no save, no sync, no SnackBar); a couple of
    // bounded pumps flush the resulting rebuild.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Escribe algo antes de guardar'), findsOneWidget);
    expect(find.text('Aún no hay capturas'), findsOneWidget);
  });
}
