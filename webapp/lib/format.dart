// Shared formatting for durations and times.
import 'package:intl/intl.dart';

/// 45m, 2h 05m.
String hm(Duration d) {
  final m = d.inMinutes;
  return m < 60 ? '${m}m' : '${m ~/ 60}h ${(m % 60).toString().padLeft(2, '0')}m';
}

/// 1:02:09 style for running timers.
String clockDuration(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  String p(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${p(m)}:${p(s)}' : '${p(m)}:${p(s)}';
}

String dayLabel(DateTime day, DateTime now) {
  final a = DateTime(day.year, day.month, day.day), t = DateTime(now.year, now.month, now.day);
  final diff = a.difference(t).inDays;
  if (diff == 0) return 'Today';
  if (diff == -1) return 'Yesterday';
  return DateFormat('EEE, MMM d').format(day);
}
