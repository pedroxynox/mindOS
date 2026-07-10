// Client-side models for personal development (mirrors /v1/growth/*).

class Goal {
  const Goal({
    required this.id,
    required this.title,
    required this.progress,
    required this.done,
    this.targetDate,
    this.area,
  });

  final String id;
  final String? title;
  final int progress; // 0..100
  final bool done;
  final DateTime? targetDate;
  final String? area;

  factory Goal.fromJson(Map<String, dynamic> json) => Goal(
        id: json['id'] as String,
        title: json['title'] as String?,
        progress: (json['progress'] as num?)?.toInt() ?? 0,
        done: json['done'] == true,
        targetDate: json['target_date'] != null
            ? DateTime.tryParse(json['target_date'] as String)
            : null,
        area: json['area'] as String?,
      );
}

class Habit {
  const Habit({
    required this.id,
    required this.title,
    required this.cadence,
    required this.streak,
    required this.doneToday,
    this.area,
  });

  final String id;
  final String? title;
  final String cadence;
  final int streak;
  final bool doneToday;
  final String? area;

  factory Habit.fromJson(Map<String, dynamic> json) => Habit(
        id: json['id'] as String,
        title: json['title'] as String?,
        cadence: (json['cadence'] as String?) ?? 'daily',
        streak: (json['streak'] as num?)?.toInt() ?? 0,
        doneToday: json['done_today'] == true,
        area: json['area'] as String?,
      );
}

class Reflection {
  const Reflection({
    required this.id,
    required this.body,
    this.mood,
    required this.createdAt,
  });

  final String id;
  final String? body;
  final String? mood;
  final DateTime createdAt;

  factory Reflection.fromJson(Map<String, dynamic> json) => Reflection(
        id: json['id'] as String,
        body: json['body'] as String?,
        mood: json['mood'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}
