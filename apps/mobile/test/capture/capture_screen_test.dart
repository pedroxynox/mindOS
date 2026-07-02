import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindos/src/features/capture/capture_providers.dart';
import 'package:mindos/src/features/capture/data/local/app_database.dart';
import 'package:mindos/src/features/capture/data/sync_service.dart';
import 'package:mindos/src/features/capture/presentation/capture_screen.dart';

import 'fake_capture_api.dart';

// Feature: capture-engine — capture screen wiring (R6.1).
//
// Run with: cd apps/mobile && flutter test
//
// The test is intentionally deterministic: it NEVER calls `pumpAndSettle()`.
// The screen shows a `CircularProgressIndicator` while the Drift stream is
// loading (and inside the Guardar button while saving); that indicator animates
// forever, so `pumpAndSettle()` would spin until its timeout and hang CI. We
// instead drive the frames explicitly with bounded `pump()` calls, and we
// override the sync service with a no-op so no background network / backoff
// work is scheduled — the capture simply stays `pending`, which is exactly what
// these assertions verify.
//
// Root cause of the historic CI hang (debt D-009), diagnosed once a local
// Flutter SDK was available: when the widget tree is disposed at the end of a
// test, Riverpod tears down the `capturesStreamProvider`, which cancels the
// Drift query stream. Drift's `StreamQueryStore.markAsClosed` schedules a
// zero-duration `Timer` to actually release the stream. Under `testWidgets`
// fake-async that timer is created *after* the body finishes, so it is still
// pending when the framework verifies invariants — tripping the "A Timer is
// still pending even after the widget tree was disposed" assertion and leaving
// the test isolate alive (the ~10-min CI hang). The fix is to tear the tree
// down explicitly with `pumpWidget(const SizedBox())` and then flush that
// zero-duration close timer with a single bounded `pump()` — all while we can
// still advance the fake clock. See `_disposeTree` below.

/// A [SyncService] whose drain does nothing and returns immediately. This
/// removes all asynchronous sync noise (network calls, backoff scheduling) from
/// the widget test: the optimistic local write is exercised for real, but the
/// capture is left in the `pending` state and no timers are left dangling.
class _NoopSyncService extends SyncService {
  _NoopSyncService({required super.db, required super.api})
      : super(audioReader: _noAudio);

  static Future<List<int>> _noAudio(String path) async => const <int>[];

  @override
  Future<SyncReport> drainOnce({DateTime? now}) async {
    return const SyncReport(attempted: 0, synced: 0, failed: 0, retried: 0);
  }
}

// Both widget tests below run for real against an in-memory Drift database
// (`NativeDatabase.memory`). Previously they were skipped (debt D-009); they
// are now re-enabled after diagnosing and fixing the stream-close timer leak
// described above.
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

  // Dispose the widget tree deterministically. Replacing it with an empty
  // widget unmounts the `ProviderScope`, which cancels the Drift query stream
  // and schedules Drift's zero-duration stream-close timer. A bare `pump()`
  // does NOT advance the fake clock, so that timer (a real `Timer`, not a
  // microtask) would never fire; we therefore `pump` a tiny non-zero duration
  // to elapse the fake clock and flush it while it is still under our control,
  // so nothing lingers past teardown. No `pumpAndSettle()`.
  Future<void> disposeTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
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

    await disposeTree(tester);
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

    await disposeTree(tester);
  });
}
