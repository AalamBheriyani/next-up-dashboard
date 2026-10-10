// A TickTick task with a due date, shaped for the Today screen.
class Deadline {
  const Deadline({
    required this.id,
    required this.projectId,
    required this.title,
    required this.due,
    required this.allDay,
    required this.priority,
    required this.list,
    this.raw = '',
  });

  final String id;
  final String projectId;
  final String title;
  // When it counts as late: the exact time, or the end of the day for all-day tasks.
  final DateTime due;
  final bool allDay;
  final int priority; // TickTick: 0 none, 1 low, 3 medium, 5 high
  final String list;
  final String raw; // TickTick's own dueDate text, so an edit can change the day and keep the rest

  /// The dueDate text for moving this deadline to [day], keeping its time of day (or all-day-ness).
  String dueOn(DateTime day) {
    if (allDay) {
      final suffix = RegExp(r'T.*$').firstMatch(raw)?.group(0) ?? 'T00:00:00+0000';
      return '${_ymd(day)}$suffix';
    }
    final local = DateTime(day.year, day.month, day.day, due.hour, due.minute, due.second).toUtc();
    return '${_ymd(local)}T${_hms(local)}+0000';
  }

  bool isLate(DateTime now) => due.isBefore(now);

  /// Parses one task from `/ticktick/tasks`. Returns null when it has no usable due date.
  static Deadline? fromTask(Map<String, dynamic> t, Map<String, String> listNames) {
    final raw = t['dueDate'];
    if (raw is! String) return null;
    final allDay = t['isAllDay'] == true;
    DateTime? due;
    if (allDay) {
      // All-day dates are midnight in the task's own zone; the date part is what matters.
      final m = RegExp(r'^(\d{4})-(\d\d)-(\d\d)').firstMatch(raw);
      if (m != null) due = DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!), 23, 59, 59);
    } else {
      // TickTick writes offsets as +0000; Dart wants +00:00.
      due = DateTime.tryParse(raw.replaceFirstMapped(RegExp(r'([+-]\d\d)(\d\d)$'), (m) => '${m[1]}:${m[2]}'))?.toLocal();
    }
    if (due == null) return null;
    final projectId = '${t['projectId'] ?? ''}';
    return Deadline(
      id: '${t['id'] ?? ''}',
      projectId: projectId,
      title: '${t['title'] ?? 'Untitled'}',
      due: due,
      allDay: allDay,
      priority: (t['priority'] as num?)?.toInt() ?? 0,
      list: listNames[projectId] ?? '',
      raw: raw,
    );
  }
}

/// Deadlines split the way the Today screen shows them.
class DeadlineGroups {
  DeadlineGroups(List<Deadline> all, DateTime now)
      : overdue = all.where((d) => d.isLate(now)).toList()..sort((a, b) => a.due.compareTo(b.due)),
        upcoming = all.where((d) => !d.isLate(now)).toList()..sort((a, b) => a.due.compareTo(b.due));

  /// Oldest first: these have waited longest.
  final List<Deadline> overdue;
  final List<Deadline> upcoming;

  Deadline? get next => upcoming.isEmpty ? null : upcoming.first;

  List<Deadline> today(DateTime now) => upcoming.where((d) => _sameDay(d.due, now)).toList();

  List<Deadline> thisWeek(DateTime now) {
    final end = DateTime(now.year, now.month, now.day).add(const Duration(days: 8));
    return upcoming.where((d) => !_sameDay(d.due, now) && d.due.isBefore(end)).toList();
  }

  List<Deadline> later(DateTime now) {
    final end = DateTime(now.year, now.month, now.day).add(const Duration(days: 8));
    return upcoming.where((d) => !d.due.isBefore(end)).toList();
  }

  static bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
}

String _two(int n) => n.toString().padLeft(2, '0');
String _ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}';
String _hms(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}:${_two(d.second)}';

/// TickTick's dueDate text for a new timed deadline, or an all-day one at local midnight.
String newDueText(DateTime when, {required bool allDay}) {
  if (allDay) return '${_ymd(when)}T00:00:00+0000';
  final u = when.toUtc();
  return '${_ymd(u)}T${_hms(u)}+0000';
}
