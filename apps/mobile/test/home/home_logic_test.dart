import 'package:flutter_test/flutter_test.dart';
import 'package:mindos/src/features/graph/data/briefing_models.dart';
import 'package:mindos/src/features/home/briefing_hero.dart';
import 'package:mindos/src/features/home/focus_score.dart';
import 'package:mindos/src/features/shared/format.dart';
import 'package:mindos/src/features/tasks/data/task_model.dart';

// Pure logic behind Hoy: the focus score, the briefing sentences and the
// greeting/date formatting (D-015 fixes: greeting by hour, done-today only).
void main() {
  final now = DateTime(2026, 7, 10, 15, 0);

  Task task({
    bool done = false,
    DateTime? doneAt,
    DateTime? dueAt,
  }) =>
      Task(
        id: 'x',
        title: 't',
        done: done,
        priority: TaskPriority.medium,
        doneAt: doneAt,
        dueAt: dueAt,
        createdAt: DateTime(2026, 7, 1),
      );

  group('computeFocusScore', () {
    test('is a calm default with no tasks', () {
      expect(computeFocusScore(const [], now: now), 78);
    });

    test('rewards only tasks completed TODAY', () {
      final today = computeFocusScore(
          [task(done: true, doneAt: now.subtract(const Duration(hours: 1)))],
          now: now);
      final lastWeek = computeFocusScore(
          [task(done: true, doneAt: now.subtract(const Duration(days: 7)))],
          now: now);
      expect(today, 89);
      expect(lastWeek, 85);
    });

    test('penalises overdue open work and stays within 40..99', () {
      final overdue = List.generate(
          10, (_) => task(dueAt: now.subtract(const Duration(days: 1))));
      expect(computeFocusScore(overdue, now: now), 45);
    });
  });

  group('composeBriefingLines', () {
    test('says everything is clear when there is nothing pending', () {
      final b = Briefing(
        generatedAt: now,
        taskTotal: 0,
        tasks: const [],
        upcomingEvents: const [],
      );
      expect(composeBriefingLines(b, now: now).single,
          contains('Todo despejado'));
    });

    test('summarises pending, overdue, people and the next event', () {
      final b = Briefing(
        generatedAt: now,
        taskTotal: 3,
        overdueCount: 1,
        dueTodayCount: 2,
        tasks: const [],
        upcomingEvents: [
          BriefingEvent(
              id: 'e', title: 'Reunión pitch', occurredAt: DateTime(2026, 7, 11, 9, 30)),
        ],
        people: const [BriefingPerson(name: 'Marcos', pendingCount: 2)],
      );
      expect(composeBriefingLines(b, now: now), [
        'Tienes 3 pendientes (1 vencida, 2 para hoy).',
        'Marcos espera 2 cosas de ti.',
        'Próximo: Reunión pitch, mañana 09:30.',
      ]);
    });
  });

  group('format', () {
    test('greets by local hour, with the name when known', () {
      expect(greetingFor(DateTime(2026, 7, 10, 8)), 'Buenos días');
      expect(greetingFor(DateTime(2026, 7, 10, 15), name: 'Pedro'),
          'Buenas tardes, Pedro');
      expect(greetingFor(DateTime(2026, 7, 10, 21)), 'Buenas noches');
    });

    test('formats relative days', () {
      expect(formatDayTime(DateTime(2026, 7, 10, 18, 5), now: now), 'hoy 18:05');
      expect(formatDayTime(DateTime(2026, 7, 9, 8), now: now), 'ayer 08:00');
      expect(formatDayTime(DateTime(2026, 8, 2, 8), now: now), '2 ago 08:00');
    });
  });
}
