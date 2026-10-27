// Client-side task model (mirrors /v1/tasks).

enum TaskPriority { high, medium, low }

/// Parse a wire priority; unknown or missing values read as medium.
TaskPriority taskPriorityFrom(String? v) {
  switch (v) {
    case 'high':
      return TaskPriority.high;
    case 'low':
      return TaskPriority.low;
    default:
      return TaskPriority.medium;
  }
}

extension TaskPriorityX on TaskPriority {
  String get wire => switch (this) {
        TaskPriority.high => 'high',
        TaskPriority.medium => 'medium',
        TaskPriority.low => 'low',
      };

  String get label => switch (this) {
        TaskPriority.high => 'Alta',
        TaskPriority.medium => 'Media',
        TaskPriority.low => 'Baja',
      };
}

class Task {
  const Task({
    required this.id,
    required this.title,
    required this.done,
    required this.priority,
    this.doneAt,
    this.dueAt,
    this.area,
    this.origin = 'manual_text',
    required this.createdAt,
  });

  final String id;
  final String? title;
  final bool done;
  final TaskPriority priority;
  final DateTime? doneAt;
  final DateTime? dueAt;
  final String? area;

  /// 'ai' when mindOS extracted it from a capture, 'manual_text' when created.
  final String origin;
  final DateTime createdAt;

  bool get fromAi => origin == 'ai';

  factory Task.fromJson(Map<String, dynamic> json) => Task(
        id: json['id'] as String,
        title: json['title'] as String?,
        done: json['done'] == true,
        priority: taskPriorityFrom(json['priority'] as String?),
        doneAt: json['done_at'] != null
            ? DateTime.tryParse(json['done_at'] as String)
            : null,
        dueAt: json['due_at'] != null
            ? DateTime.tryParse(json['due_at'] as String)
            : null,
        area: json['area'] as String?,
        origin: (json['origin'] as String?) ?? 'manual_text',
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}
