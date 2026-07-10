// Client-side task model (mirrors /v1/tasks).

enum TaskPriority { high, medium, low }

TaskPriority _priorityFrom(String? v) {
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
    this.dueAt,
    this.area,
    required this.createdAt,
  });

  final String id;
  final String? title;
  final bool done;
  final TaskPriority priority;
  final DateTime? dueAt;
  final String? area;
  final DateTime createdAt;

  factory Task.fromJson(Map<String, dynamic> json) => Task(
        id: json['id'] as String,
        title: json['title'] as String?,
        done: json['done'] == true,
        priority: _priorityFrom(json['priority'] as String?),
        dueAt: json['due_at'] != null
            ? DateTime.tryParse(json['due_at'] as String)
            : null,
        area: json['area'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}
