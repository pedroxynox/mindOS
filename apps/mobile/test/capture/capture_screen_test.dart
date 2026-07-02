import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindos/src/features/capture/capture_providers.dart';
import 'package:mindos/src/features/capture/data/local/app_database.dart';
import 'package:mindos/src/features/capture/presentation/capture_screen.dart';

import 'fake_capture_api.dart';

// Feature: capture-engine — capture screen wiring (R6.1)
//
// NOTE: This widget test requires a Flutter SDK (`flutter test`) with the
// native sqlite3 library available to `NativeDatabase`. It was written but NOT
// executed here (the sandbox has no Flutter SDK). Run with:
//   cd apps/mobile && flutter test
void main() {
  late AppDatabase db;
  late FakeCaptureApi api;

  setUp(() {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
    // Keep every drain a transient no-op so the capture stays `pending`,
    // exercising the real repository + sync code paths without a network.
    api = FakeCaptureApi()..transientBeforeCreate = 1000;
  });

  tearDown(() async {
    await db.close();
  });

  Widget buildHarness() {
    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        captureApiClientProvider.overrideWith((ref) => api),
      ],
      child: const MaterialApp(home: CaptureScreen()),
    );
  }

  testWidgets(
      'typing text and tapping Guardar shows the capture as pending in the list',
      (tester) async {
    await tester.pumpWidget(buildHarness());
    await tester.pumpAndSettle();

    const content = 'una idea offline-first';
    await tester.enterText(find.byType(TextField), content);
    await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));

    // Let the optimistic write land and the Drift stream re-emit.
    await tester.pump();
    await tester.pump();

    // The saved capture appears in the list with a `pending` status.
    expect(find.text(content), findsOneWidget);
    expect(find.text('Pendiente'), findsOneWidget);

    // The input was cleared after a successful save.
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, isEmpty);
  });

  testWidgets('empty input is rejected with a validation error', (tester) async {
    await tester.pumpWidget(buildHarness());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
    await tester.pump();

    expect(find.text('Escribe algo antes de guardar'), findsOneWidget);
    expect(find.text('Aún no hay capturas'), findsOneWidget);
  });
}
