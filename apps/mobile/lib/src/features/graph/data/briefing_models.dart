// Client-side model for the Daily Briefing (mirrors GET /v1/briefing).

/// A minimal knowledge item shown in the briefing.
class BriefingItem {
  const BriefingItem({required this.id, this.title});

  final String id;
  final String? title;

  factory BriefingItem.fromJson(Map<String, dynamic> json) => BriefingItem(
        id: json['id'] as String,
        title: json['title'] as String?,
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

/// The proactive summary shown at the top of the home screen.
class Briefing {
  const Briefing({
    required this.generatedAt,
    required this.taskTotal,
    required this.tasks,
    required this.upcomingEvents,
  });

  final DateTime generatedAt;
  final int taskTotal;
  final List<BriefingItem> tasks;
  final List<BriefingEvent> upcomingEvents;

  bool get isEmpty => taskTotal == 0 && upcomingEvents.isEmpty;

  factory Briefing.fromJson(Map<String, dynamic> json) => Briefing(
        generatedAt: DateTime.parse(json['generated_at'] as String),
        taskTotal: (json['task_total'] as num?)?.toInt() ?? 0,
        tasks: (json['tasks'] as List<dynamic>? ?? [])
            .map((e) => BriefingItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        upcomingEvents: (json['upcoming_events'] as List<dynamic>? ?? [])
            .map((e) => BriefingEvent.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
