// The big clock, the date and how much of the waking day is left.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:next_up_core/calendar.dart';
import 'package:next_up_core/theme.dart';

/// Wake and wind-down times; the site reads these from each person's profile, here they are fixed
/// until a settings page exists.
const dayStartHour = 7;
const dayEndHour = 22;

class ClockHeader extends StatefulWidget {
  const ClockHeader({super.key, this.now, this.events});
  final List<CalendarEvent>? events; // today's calendar, for the "until free" bar
  final DateTime Function()? now; // for tests

  @override
  State<ClockHeader> createState() => _ClockHeaderState();
}

class _ClockHeaderState extends State<ClockHeader> {
  Timer? _tick;
  DateTime _now() => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = _now();
    final start = DateTime(now.year, now.month, now.day, dayStartHour);
    final end = DateTime(now.year, now.month, now.day, dayEndHour);
    final frac = (now.difference(start).inSeconds / end.difference(start).inSeconds).clamp(0.0, 1.0);
    final left = end.difference(now);
    final label = left.isNegative ? 'Wind-down time. Rest up.' : '${_fmt(left)} left until wind-down';
    final free = freeBar(widget.events, now, start);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.end,
      spacing: 32,
      runSpacing: 12,
      children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(DateFormat('h:mm').format(now) + DateFormat(' a').format(now).toLowerCase(),
              style: const TextStyle(fontSize: NextUpType.clock, fontWeight: FontWeight.w800, height: 1, fontFeatures: monoFeatures)),
          const SizedBox(height: 4),
          Text(DateFormat('EEEE, MMMM d').format(now), style: TextStyle(color: NextUpColors.muted, fontSize: NextUpType.body)),
        ]),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 240, maxWidth: 380),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            if (free != null) ...[
              Text(free.label, style: TextStyle(color: NextUpColors.muted, fontSize: NextUpType.body)),
              const SizedBox(height: 8),
              _Bar(free.fraction),
              const SizedBox(height: 14),
            ],
            Text(label, style: TextStyle(color: NextUpColors.muted, fontSize: NextUpType.body)),
            const SizedBox(height: 8),
            _Bar(frac),
          ]),
        ),
      ],
    );
  }
}

String _fmt(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60;
  return h == 0 ? '${m}m' : '${h}h ${m}m';
}

/// One progress bar, the same look for every indicator in the header.
class _Bar extends StatelessWidget {
  const _Bar(this.value);
  final double value;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(value: value, minHeight: 8, backgroundColor: NextUpColors.raised, color: NextUpColors.accent),
      );
}

/// The time until you are free: while an event is on, how far through it you are; while free, how far
/// through the gap before the next event. Null when there is nothing left on today's calendar.
({String label, double fraction})? freeBar(List<CalendarEvent>? events, DateTime now, DateTime dayStart) {
  if (events == null) return null;
  final day = DaySchedule(events, now);
  final cur = day.current;
  if (cur != null) {
    final f = (now.difference(cur.start).inSeconds / cur.length.inSeconds).clamp(0.0, 1.0);
    return (label: '${_fmt(cur.end.difference(now))} until free, ${cur.title} ends ${DateFormat('h:mm a').format(cur.end)}', fraction: f);
  }
  final next = day.next;
  if (next == null) return null;
  var from = dayStart;
  for (final e in day.timed) {
    if (!e.end.isAfter(now) && e.end.isAfter(from)) from = e.end;
  }
  if (from.isAfter(now)) from = now;
  final span = next.start.difference(from).inSeconds;
  final f = span <= 0 ? 0.0 : (now.difference(from).inSeconds / span).clamp(0.0, 1.0);
  return (label: 'Free for ${_fmt(next.start.difference(now))} until ${next.title}', fraction: f);
}
