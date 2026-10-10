// How urgent a deadline feels: the closer (or later) it is, the louder it gets. Used to colour the next
// deadline and each row's time, and to word the "do this now" nudge.
import 'package:flutter/material.dart';

import 'deadline.dart';
import 'theme.dart';

enum Urgency { later, week, soon, critical, overdue }

Urgency urgencyOf(Deadline d, DateTime now) {
  final left = d.due.difference(now);
  if (left.isNegative) return Urgency.overdue;
  if (left < const Duration(hours: 3)) return Urgency.critical;
  if (left < const Duration(hours: 24)) return Urgency.soon;
  if (left < const Duration(days: 7)) return Urgency.week;
  return Urgency.later;
}

Color urgencyColor(Urgency u) => switch (u) {
      Urgency.overdue || Urgency.critical => NextUpColors.deadline,
      Urgency.soon => NextUpColors.soon,
      Urgency.week => NextUpColors.accent,
      Urgency.later => NextUpColors.muted,
    };

/// A short, direct line for the nudge, e.g. "Due in 2h 10m. Start now."
String urgencyLine(Deadline d, DateTime now) {
  final left = d.due.difference(now);
  String span(Duration x) {
    final m = x.inMinutes.abs();
    if (m >= 2880) return '${m ~/ 1440} days';
    if (m >= 60) return '${m ~/ 60}h ${m % 60}m';
    return '${m}m';
  }

  return switch (urgencyOf(d, now)) {
    Urgency.overdue => '${span(left)} late. Start it now.',
    Urgency.critical => 'Due in ${span(left)}. Start now.',
    Urgency.soon => 'Due in ${span(left)}. Start today.',
    Urgency.week => 'Due in ${span(left)}.',
    Urgency.later => 'Due in ${span(left)}.',
  };
}
