import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindos/src/features/tasks/data/task_model.dart';
import 'package:mindos/src/features/tasks/data/tasks_api.dart';
import 'package:mindos/src/features/tasks/presentation/tasks_screen.dart';
import 'package:mindos/src/features/tasks/tasks_providers.dart';
import 'package:mindos/src/theme.dart';

import '../helpers.dart';

/// In-memory TasksApi honouring the same contract as the server.
class _FakeTasksApi extends TasksApi {
  _FakeTasksApi() : super(offlineApi());

  final List<Task> tasks = [
    Task(
      id: 't1',
      title: 'Pagar la luz',
      done: false,
      priority: TaskPriority.high,
      origin: 'ai',
      createdAt: DateTime(2026, 7, 1),
    ),
  ];
  final List<String> deleted = [];

  @override
  Future<List<Task>> list({bool pendingOnly = false}) async => List.of(tasks);

  @override
  Future<Task> create(String title,
      {TaskPriority priority = TaskPriority.medium,
      DateTime? dueAt,
      String? area}) async {
    final t = Task(
      id: 'n${tasks.length}',
      title: title,
      done: false,
      priority: priority,
      dueAt: dueAt,
      createdAt: DateTime(2026, 7, 2),
    );
    tasks.add(t);
    return t;
  }

  @override
  Future<Task> update(String id,
      {bool? done,
      TaskPriority? priority,
      String? title,
      DateTime? dueAt,
      bool clearDueAt = false}) async {
    final i = tasks.indexWhere((t) => t.id == id);
    final old = tasks[i];
    final t = Task(
      id: id,
      title: title ?? old.title,
      done: done ?? old.done,
      priority: priority ?? old.priority,
      dueAt: clearDueAt ? null : (dueAt ?? old.dueAt),
      origin: old.origin,
      createdAt: old.createdAt,
    );
    tasks[i] = t;
    return t;
  }

  @override
  Future<void> delete(String id) async {
    deleted.add(id);
    tasks.removeWhere((t) => t.id == id);
  }
}

void main() {
  late _FakeTasksApi api;

  Future<void> pumpScreen(WidgetTester tester) async {
    api = _FakeTasksApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [tasksApiProvider.overrideWithValue(api)],
        child: MaterialApp(theme: AppTheme.dark(), home: const TasksScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('lists tasks and marks AI-detected ones', (tester) async {
    await pumpScreen(tester);
    expect(find.text('Pagar la luz'), findsOneWidget);
    expect(find.textContaining('detectada por mindOS'), findsOneWidget);
    expect(find.text('Alta'), findsOneWidget);
  });

  testWidgets('completing a task updates it', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(api.tasks.single.done, isTrue);
  });

  testWidgets('creates a task from the editor', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.text('Nueva tarea'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Comprar pan');
    await tester.tap(find.text('Crear'));
    await tester.pumpAndSettle();
    expect(api.tasks.map((t) => t.title), contains('Comprar pan'));
    expect(find.text('Comprar pan'), findsOneWidget);
  });

  testWidgets('rejects a blank title in the editor', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.text('Nueva tarea'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.text('Crear'));
    await tester.pumpAndSettle();
    expect(find.text('Escribe qué necesitas hacer'), findsOneWidget);
    expect(api.tasks, hasLength(1));
  });

  testWidgets('deletes a task from the editor', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.text('Pagar la luz'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eliminar'));
    await tester.pumpAndSettle();
    expect(api.deleted, ['t1']);
    expect(find.text('No tienes tareas'), findsOneWidget);
  });
}
