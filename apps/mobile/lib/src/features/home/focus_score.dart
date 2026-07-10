import '../tasks/data/task_model.dart';

/// A gentle, deterministic "focus score" (0–100) shown on the Hoy screen.
///
/// It rewards momentum (tasks completed today) and penalises overdue work, so
/// it nudges without being noisy. With no data it returns a calm default. This
/// is intentionally simple and client-side; a richer, learned score is a future
/// step.
int computeFocusScore(List<Task> tasks, {DateTime? now}) {
  if (tasks.isEmpty) return 78;
  final t = now ?? DateTime.now();

  var score = 85;
  var overduePenalty = 0;
  var doneBonus = 0;

  for (final task in tasks) {
    if (!task.done && task.dueAt != null && task.dueAt!.isBefore(t)) {
      overduePenalty += 8;
    }
    if (task.done) doneBonus += 4;
  }

  score -= overduePenalty.clamp(0, 40);
  score += doneBonus.clamp(0, 12);
  return score.clamp(40, 99);
}
