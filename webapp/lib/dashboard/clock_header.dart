// The big clock, the date and how much of the waking day is left.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:next_up_core/calendar.dart';
import 'package:next_up_core/theme.dart';
import 'package:next_up_core/worker_api.dart' show defaultWakeMinutes, defaultWindDownMinutes;

import '../motion.dart';

class ClockHeader extends StatefulWidget {
  const ClockHeader({super.key, this.now, this.events, this.wakeMinutes = defaultWakeMinutes, this.windDownMinutes = defaultWindDownMinutes, this.place = '', this.sleepMinutes});
  /// The waking day, as minutes after midnight (from the person's settings).
  final int wakeMinutes, windDownMinutes;
  final String place;
  final int? sleepMinutes;
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
    final start = DateTime(now.year, now.month, now.day, 0, widget.wakeMinutes);
    final end = DateTime(now.year, now.month, now.day, 0, widget.windDownMinutes);
    final span = end.difference(start).inSeconds;
    final frac = span <= 0 ? 1.0 : (now.difference(start).inSeconds / span).clamp(0.0, 1.0);
    final left = end.difference(now);
    final free = freeBar(widget.events, now, start);
    final muted = TextStyle(color: NextUpColors.muted, fontSize: NextUpType.body);
    // The same arrangement as the current site: a bold clock with the date on its baseline, then small cards
    // with a label, a value on the right, a bar and the day's anchors.
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 32,
      runSpacing: 12,
      children: [
        Wrap(crossAxisAlignment: WrapCrossAlignment.end, spacing: 14, runSpacing: 4, children: [
          Text(DateFormat('h:mm a').format(now), style: const TextStyle(fontSize: NextUpType.clock, fontWeight: FontWeight.w800, height: 1, fontFeatures: monoFeatures)),
          Padding(padding: const EdgeInsets.only(bottom: 6), child: Text([DateFormat('EEEE, MMMM d').format(now), if (widget.place.isNotEmpty) widget.place].join('  ·  '), style: muted)),
        ]),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (free != null) ...[
              _Card(label: free.title, value: free.value, fraction: free.fraction),
              const SizedBox(height: 8),
            ],
            _Card(
              label: 'Work time left today',
              value: left.isNegative ? 'Wind-down time. Log XP and rest.' : '${_fmt(left)} until wind-down',
              fraction: frac,
              from: 'Wake ${_hm(start)}',
              to: ['Wind-down ${_hm(end)}', if (widget.sleepMinutes != null) 'Sleep ${_hm(DateTime(now.year, now.month, now.day, 0, widget.sleepMinutes!))}'].join('  ·  '),
            ),
          ]),
        ),
      ],
    );
  }
}

String _hm(DateTime t) => DateFormat('h:mm a').format(t);

String _fmt(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60;
  return h == 0 ? '${m}m' : '${h}h ${m}m';
}

/// A small card: label on the left, value on the right, a progress bar and optional anchors under it.
class _Card extends StatelessWidget {
  const _Card({required this.label, required this.value, required this.fraction, this.from, this.to});
  final String label, value;
  final double fraction;
  final String? from, to;

  @override
  Widget build(BuildContext context) {
    final small = TextStyle(color: NextUpColors.muted, fontSize: NextUpType.caption);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: NextUpColors.raised, borderRadius: BorderRadius.circular(10)),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Label left, value right; on a narrow card the value goes under the label instead of squeezing it.
        LayoutBuilder(builder: (context, box) {
          final v = Text(value, textAlign: TextAlign.end, style: const TextStyle(fontSize: NextUpType.caption, fontWeight: FontWeight.w600, fontFeatures: monoFeatures));
          if (box.maxWidth < 380) return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: small), const SizedBox(height: 2), v]);
          return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            Flexible(flex: 3, child: Text(label, overflow: TextOverflow.ellipsis, style: small)),
            const SizedBox(width: 12),
            Flexible(flex: 2, child: v),
          ]);
        }),
        const SizedBox(height: 8),
        GrowBar(value: fraction, color: NextUpColors.accent, height: 8, track: NextUpColors.line),
        if (from != null) ...[
          const SizedBox(height: 6),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(from!, style: small), Text(to ?? '', style: small)]),
        ],
      ]),
    );
  }
}

/// The time until you are free: while an event is on, how far through it you are; while free, how far
/// through the gap before the next event. Null when there is nothing left on today's calendar.
({String title, String value, double fraction})? freeBar(List<CalendarEvent>? events, DateTime now, DateTime dayStart) {
  if (events == null) return null;
  final day = DaySchedule(events, now);
  final cur = day.current;
  if (cur != null) {
    final f = (now.difference(cur.start).inSeconds / cur.length.inSeconds).clamp(0.0, 1.0);
    return (title: 'Until free', value: '${_fmt(cur.end.difference(now))} · ${cur.title} ends ${DateFormat('h:mm a').format(cur.end)}', fraction: f);
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
  return (title: 'Free until ${next.title}', value: _fmt(next.start.difference(now)), fraction: f);
}
