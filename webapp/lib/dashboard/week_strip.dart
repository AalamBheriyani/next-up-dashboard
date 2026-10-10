// The next seven days at a glance: deadlines due (red dots) and booked calendar time (bar).
// The current site has no week view, so this is where planning ahead starts.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:next_up_core/calendar.dart';
import 'package:next_up_core/deadline.dart';
import 'package:next_up_core/theme.dart';

import 'panel.dart';

class WeekStrip extends StatelessWidget {
  const WeekStrip({super.key, required this.deadlines, required this.events, required this.now});
  final List<Deadline> deadlines;
  final List<CalendarEvent> events;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final today = DateTime(now.year, now.month, now.day);
    final days = [for (var i = 0; i < 7; i++) today.add(Duration(days: i))];
    final booked = [
      for (final d in days) events.where((e) => !e.allDay && e.isOn(d)).fold<Duration>(Duration.zero, (s, e) => s + _within(e, d)),
    ];
    final due = [for (final d in days) deadlines.where((x) => _sameDay(x.due, d)).length];
    final maxBooked = booked.fold<int>(0, (m, b) => b.inMinutes > m ? b.inMinutes : m);
    return Panel(
      title: 'Next 7 days',
      child: Row(children: [
        for (var i = 0; i < 7; i++)
          Expanded(
            child: Column(children: [
              Text(DateFormat('E').format(days[i]).toUpperCase(),
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1, color: i == 0 ? NextUpColors.accent : NextUpColors.muted)),
              Text('${days[i].day}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: i == 0 ? NextUpColors.accent : NextUpColors.ink)),
              const SizedBox(height: 8),
              SizedBox(
                height: 44,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    width: 18,
                    height: maxBooked == 0 ? 3 : 3 + 41 * booked[i].inMinutes / maxBooked,
                    decoration: BoxDecoration(color: NextUpColors.accent.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(4)),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(booked[i].inMinutes == 0 ? '' : '${(booked[i].inMinutes / 60).toStringAsFixed(1)}h', style: const TextStyle(fontSize: 11, color: NextUpColors.muted)),
              const SizedBox(height: 6),
              SizedBox(
                height: 14,
                child: due[i] == 0
                    ? null
                    : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        for (var k = 0; k < due[i].clamp(0, 4); k++)
                          Container(width: 7, height: 7, margin: const EdgeInsets.symmetric(horizontal: 1.5), decoration: const BoxDecoration(color: NextUpColors.deadline, shape: BoxShape.circle)),
                      ]),
              ),
            ]),
          ),
      ]),
    );
  }
}

bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

Duration _within(CalendarEvent e, DateTime day) {
  final a = day, b = day.add(const Duration(days: 1));
  final s = e.start.isAfter(a) ? e.start : a, en = e.end.isBefore(b) ? e.end : b;
  return en.isAfter(s) ? en.difference(s) : Duration.zero;
}
