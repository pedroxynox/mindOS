import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindos/src/features/auth/auth_providers.dart';
import 'package:mindos/src/features/finance/data/finance_models.dart';
import 'package:mindos/src/features/finance/finance_providers.dart';
import 'package:mindos/src/features/graph/data/briefing_models.dart';
import 'package:mindos/src/features/graph/graph_providers.dart';
import 'package:mindos/src/features/growth/data/growth_models.dart';
import 'package:mindos/src/features/growth/growth_providers.dart';
import 'package:mindos/src/features/home/home_screen.dart';
import 'package:mindos/src/features/tasks/data/task_model.dart';
import 'package:mindos/src/features/tasks/tasks_providers.dart';
import 'package:mindos/src/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Hoy renders the briefing ("mindOS te habla primero"), the user's name in the
// greeting, the top priorities and the summary cards — with "Metas" (not the
// old mislabelled "Proyectos"). Providers are overridden; no network. The
// PresenceOrb animates forever, so frames are driven with bounded pumps.
void main() {
  Future<void> pumpHome(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'mindos.auth.access': 'a',
      'mindos.auth.email': 'pedro@example.com',
    });
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();

    await tester.binding.setSurfaceSize(const Size(430, 1400));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          tasksListProvider.overrideWith((ref) async => [
                Task(
                  id: 't1',
                  title: 'Llamar a Marcos',
                  done: false,
                  priority: TaskPriority.high,
                  createdAt: now,
                ),
              ]),
          briefingProvider.overrideWith((ref) async => Briefing(
                generatedAt: now,
                taskTotal: 1,
                tasks: const [],
                upcomingEvents: const [],
                people: const [BriefingPerson(name: 'Marcos', pendingCount: 1)],
              )),
          financeSummaryProvider.overrideWith((ref) async =>
              FinanceSummary.fromJson(const {'week_total': 0, 'prev_week_total': 0})),
          habitsProvider.overrideWith((ref) async => const <Habit>[]),
          goalsProvider.overrideWith((ref) async => const [
                Goal(id: 'g', title: 'Correr 10K', progress: 40, done: false),
              ]),
        ],
        child: MaterialApp(theme: AppTheme.dark(), home: const HomeScreen()),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  testWidgets('shows the briefing, the name and the goals card', (tester) async {
    await pumpHome(tester);

    expect(find.textContaining('Pedro'), findsOneWidget);
    expect(find.text('Tienes 1 pendiente.'), findsOneWidget);
    expect(find.text('Marcos espera algo de ti.'), findsOneWidget);
    expect(find.text('Llamar a Marcos'), findsOneWidget);
    expect(find.text('Metas'), findsOneWidget);
    expect(find.text('Proyectos'), findsNothing);
    expect(find.text('Correr 10K'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 600));
  });
}
