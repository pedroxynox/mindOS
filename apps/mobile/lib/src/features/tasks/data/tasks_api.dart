import '../../shared/mindos_api.dart';
import 'task_model.dart';

/// Read/write client for `/v1/tasks` (snake_case contract, #04 §5.7).
class TasksApi {
  TasksApi(this._api);
  final MindosApi _api;

  Future<List<Task>> list({bool pendingOnly = false}) async {
    final json = await _api.get(
      '/tasks',
      query: pendingOnly ? {'filter': 'pending'} : null,
    );
    return (json as List<dynamic>)
        .map((e) => Task.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Task> create(
    String title, {
    TaskPriority priority = TaskPriority.medium,
    DateTime? dueAt,
    String? area,
  }) async {
    final json = await _api.post('/tasks', {
      'title': title,
      'priority': priority.wire,
      if (dueAt != null) 'due_at': dueAt.toUtc().toIso8601String(),
      if (area != null && area.isNotEmpty) 'area': area,
    });
    return Task.fromJson(json as Map<String, dynamic>);
  }

  /// Patch a task. Pass [clearDueAt] to remove the due date.
  Future<Task> update(
    String id, {
    bool? done,
    TaskPriority? priority,
    String? title,
    DateTime? dueAt,
    bool clearDueAt = false,
  }) async {
    final json = await _api.patch('/tasks/$id', {
      if (done != null) 'done': done,
      if (priority != null) 'priority': priority.wire,
      if (title != null) 'title': title,
      if (dueAt != null) 'due_at': dueAt.toUtc().toIso8601String(),
      if (clearDueAt && dueAt == null) 'due_at': null,
    });
    return Task.fromJson(json as Map<String, dynamic>);
  }

  Future<void> delete(String id) async {
    await _api.delete('/tasks/$id');
  }
}
