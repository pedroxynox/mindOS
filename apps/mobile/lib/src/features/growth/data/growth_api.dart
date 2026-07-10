import '../../shared/mindos_api.dart';
import 'growth_models.dart';

/// Read/write client for the Growth endpoints (`/v1/growth/*`).
class GrowthApi {
  GrowthApi(this._api);
  final MindosApi _api;

  // Goals
  Future<List<Goal>> listGoals() async {
    final json = await _api.get('/growth/goals');
    return (json as List<dynamic>)
        .map((e) => Goal.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Goal> createGoal(String title, {String? area}) async {
    final json = await _api.post('/growth/goals', {
      'title': title,
      if (area != null && area.isNotEmpty) 'area': area,
    });
    return Goal.fromJson(json as Map<String, dynamic>);
  }

  Future<Goal> updateGoalProgress(String id, int progress) async {
    final json = await _api.patch('/growth/goals/$id', {'progress': progress});
    return Goal.fromJson(json as Map<String, dynamic>);
  }

  // Habits
  Future<List<Habit>> listHabits() async {
    final json = await _api.get('/growth/habits');
    return (json as List<dynamic>)
        .map((e) => Habit.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Habit> createHabit(String title, {String cadence = 'daily'}) async {
    final json = await _api.post('/growth/habits', {
      'title': title,
      'cadence': cadence,
    });
    return Habit.fromJson(json as Map<String, dynamic>);
  }

  Future<Habit> checkHabit(String id) async {
    final json = await _api.post('/growth/habits/$id/check');
    return Habit.fromJson(json as Map<String, dynamic>);
  }

  // Reflections
  Future<List<Reflection>> listReflections() async {
    final json = await _api.get('/growth/reflections');
    return (json as List<dynamic>)
        .map((e) => Reflection.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Reflection> createReflection(String body, {String? mood}) async {
    final json = await _api.post('/growth/reflections', {
      'body': body,
      if (mood != null && mood.isNotEmpty) 'mood': mood,
    });
    return Reflection.fromJson(json as Map<String, dynamic>);
  }
}
