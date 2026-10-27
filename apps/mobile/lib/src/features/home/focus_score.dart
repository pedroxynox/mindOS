import '../tasks/data/task_model.dart';

/// A gentle, deterministic "focus score" (40–99) shown on the Hoy screen.
///
/// It rewards momentum — tasks completed TODAY (local day) — and penalises
/// overdue open work, so it nudges without being noisy. With no tasks it
/// returns a calm default. Intentionally simple and client-side; a richer,
/// learned score is a future step.
int computeFocusScore(List<Task> tasks, {DateTime? now}) {
  if (tasks.isEmpty) return 78;
  final t = (now ?? DateTime.now()).toLocal();

  var score = 85;
  var overduePenalty = 0;
  var doneBonus = 0;

  for (final task in tasks) {
    if (!task.done && task.dueAt != null && task.dueAt!.isBefore(t)) {
      overduePenalty += 8;
    }
    if (task.done && task.doneAt != null && _sameDay(task.doneAt!.toLocal(), t)) {
      doneBonus += 4;
    }
  }

  score -= overduePenalty.clamp(0, 40);
  score += doneBonus.clamp(0, 12);
  return score.clamp(40, 99);
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
