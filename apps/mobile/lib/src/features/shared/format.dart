// Shared, dependency-free Spanish date/number formatting (audit 013 rec. #2):
// one place for the month names and the "hoy / mañana" wording used by Hoy,
// Tareas, Crecimiento and the briefing.

const _months = [
  'ene', 'feb', 'mar', 'abr', 'may', 'jun',
  'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
];

String _two(int n) => n.toString().padLeft(2, '0');

/// "15:00" in local time.
String formatTime(DateTime dt) {
  final l = dt.toLocal();
  return '${_two(l.hour)}:${_two(l.minute)}';
}

/// "12 jul" in local time.
String formatShortDate(DateTime dt) {
  final l = dt.toLocal();
  return '${l.day} ${_months[l.month - 1]}';
}

/// Relative day + time: "hoy 15:00", "mañana 09:30", "ayer 18:00" or
/// "12 jul 15:00". [now] is injectable for tests.
String formatDayTime(DateTime dt, {DateTime? now}) {
  final local = dt.toLocal();
  final n = (now ?? DateTime.now()).toLocal();
  final today = DateTime(n.year, n.month, n.day);
  final day = DateTime(local.year, local.month, local.day);
  final diff = day.difference(today).inDays;
  final time = formatTime(local);
  if (diff == 0) return 'hoy $time';
  if (diff == 1) return 'mañana $time';
  if (diff == -1) return 'ayer $time';
  return '${formatShortDate(local)} $time';
}

/// Greeting by local hour: Buenos días / Buenas tardes / Buenas noches,
/// optionally followed by the user's name.
String greetingFor(DateTime now, {String? name}) {
  final h = now.toLocal().hour;
  final base = h < 12
      ? 'Buenos días'
      : h < 19
          ? 'Buenas tardes'
          : 'Buenas noches';
  return (name == null || name.isEmpty) ? base : '$base, $name';
}

/// "1 tarea" / "3 tareas" style pluralisation.
String plural(int n, String singular, String pluralForm) =>
    '$n ${n == 1 ? singular : pluralForm}';

/// Local calendar day as `YYYY-MM-DD` (e.g. the briefing's feedback key).
String localDayKey(DateTime dt) {
  final l = dt.toLocal();
  return '${l.year.toString().padLeft(4, '0')}-${_two(l.month)}-${_two(l.day)}';
}
