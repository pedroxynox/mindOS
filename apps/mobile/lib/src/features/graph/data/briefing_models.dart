// Client-side model for the Daily Briefing (mirrors GET /v1/briefing).

import '../../tasks/data/task_model.dart';

/// A pending task shown in the briefing.
class BriefingTask {
  const BriefingTask({
    required this.id,
    this.title,
    this.priority = TaskPriority.medium,
    this.dueAt,
  });

  final String id;
  final String? title;
  final TaskPriority priority;
  final DateTime? dueAt;

  factory BriefingTask.fromJson(Map<String, dynamic> json) => BriefingTask(
        id: json['id'] as String,
        title: json['title'] as String?,
        priority: taskPriorityFrom(json['priority'] as String?),
        dueAt: json['due_at'] != null
            ? DateTime.tryParse(json['due_at'] as String)
            : null,
      );
}

/// An upcoming event with its date.
class BriefingEvent {
  const BriefingEvent({required this.id, this.title, required this.occurredAt});

  final String id;
  final String? title;
  final DateTime occurredAt;

  factory BriefingEvent.fromJson(Map<String, dynamic> json) => BriefingEvent(
        id: json['id'] as String,
        title: json['title'] as String?,
        occurredAt: DateTime.parse(json['occurred_at'] as String),
      );
}

/// Someone the user has pending tasks with.
class BriefingPerson {
  const BriefingPerson({required this.name, required this.pendingCount});

  final String name;
  final int pendingCount;

  factory BriefingPerson.fromJson(Map<String, dynamic> json) => BriefingPerson(
        name: json['name'] as String,
        pendingCount: (json['pending_count'] as num?)?.toInt() ?? 0,
      );
}

/// The proactive summary mindOS shows first on Hoy.
class Briefing {
  const Briefing({
    required this.generatedAt,
    required this.taskTotal,
    this.overdueCount = 0,
    this.dueTodayCount = 0,
    required this.tasks,
    required this.upcomingEvents,
    this.people = const [],
  });

  final DateTime generatedAt;

  /// Number of PENDING tasks.
  final int taskTotal;
  final int overdueCount;
  final int dueTodayCount;
  final List<BriefingTask> tasks;
  final List<BriefingEvent> upcomingEvents;
  final List<BriefingPerson> people;

  bool get isEmpty => taskTotal == 0 && upcomingEvents.isEmpty;

  factory Briefing.fromJson(Map<String, dynamic> json) => Briefing(
        generatedAt: DateTime.parse(json['generated_at'] as String),
        taskTotal: (json['task_total'] as num?)?.toInt() ?? 0,
        overdueCount: (json['overdue_count'] as num?)?.toInt() ?? 0,
        dueTodayCount: (json['due_today_count'] as num?)?.toInt() ?? 0,
        tasks: (json['tasks'] as List<dynamic>? ?? [])
            .map((e) => BriefingTask.fromJson(e as Map<String, dynamic>))
            .toList(),
        upcomingEvents: (json['upcoming_events'] as List<dynamic>? ?? [])
            .map((e) => BriefingEvent.fromJson(e as Map<String, dynamic>))
            .toList(),
        people: (json['people'] as List<dynamic>? ?? [])
            .map((e) => BriefingPerson.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
