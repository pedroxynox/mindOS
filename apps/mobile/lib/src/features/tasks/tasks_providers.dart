import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/api_providers.dart';
import 'data/task_model.dart';
import 'data/tasks_api.dart';

final tasksApiProvider = Provider<TasksApi>((ref) {
  return TasksApi(ref.watch(mindosApiProvider));
});

/// The user's tasks, ordered by priority (server-side). Invalidate after a
/// mutation to refresh.
final tasksListProvider = FutureProvider.autoDispose<List<Task>>((ref) {
  return ref.watch(tasksApiProvider).list();
});
