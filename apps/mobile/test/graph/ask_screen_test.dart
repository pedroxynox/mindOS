import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindos/src/features/graph/data/graph_api_client.dart';
import 'package:mindos/src/features/graph/data/query_models.dart';
import 'package:mindos/src/features/graph/graph_providers.dart';
import 'package:mindos/src/features/graph/presentation/ask_screen.dart';
import 'package:mindos/src/features/shared/mindos_api.dart';
import 'package:mindos/src/theme.dart';

import '../helpers.dart';

class _FakeGraphApi extends GraphApiClient {
  _FakeGraphApi({this.fail = false}) : super(offlineApi());
  final bool fail;
  String? asked;

  @override
  Future<QueryAnswer> ask(String question) async {
    asked = question;
    if (fail) {
      throw const ApiException(
          'El asistente está despertando. Espera unos segundos e inténtalo de nuevo.',
          503);
    }
    return const QueryAnswer(
      answer: 'Tienes que llamar a Marcos mañana [1].',
      sources: [AnswerSource(captureId: 'c1', snippet: 'Llamar a Marcos mañana')],
    );
  }
}

// Conversar: a question is sent, the grounded answer and its cited notes are
// shown; a 503 (AI waking up) is shown as a friendly error, not a crash.
void main() {
  Future<_FakeGraphApi> pumpAsk(WidgetTester tester, {bool fail = false}) async {
    final api = _FakeGraphApi(fail: fail);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [graphApiClientProvider.overrideWithValue(api)],
        child: MaterialApp(theme: AppTheme.dark(), home: const AskScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    return api;
  }

  Future<void> send(WidgetTester tester, String q) async {
    await tester.enterText(find.byType(TextField), q);
    await tester.tap(find.byIcon(Icons.arrow_upward));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('shows the grounded answer and its sources', (tester) async {
    final api = await pumpAsk(tester);
    await send(tester, '¿Qué tengo con Marcos?');

    expect(api.asked, '¿Qué tengo con Marcos?');
    expect(find.text('Tienes que llamar a Marcos mañana [1].'), findsOneWidget);
    expect(find.text('En qué me baso'), findsOneWidget);
    expect(find.text('Llamar a Marcos mañana'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('shows a friendly message when the assistant is waking up',
      (tester) async {
    await pumpAsk(tester, fail: true);
    await send(tester, 'hola');

    expect(find.textContaining('despertando'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 400));
  });
}
