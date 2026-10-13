// The big clock, the date and how much of the waking day is left.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:next_up_core/calendar.dart';
import 'package:next_up_core/theme.dart';
import 'package:next_up_core/worker_api.dart' show defaultWakeMinutes, defaultWindDownMinutes;

import '../motion.dart';

class ClockHeader extends StatefulWidget {
  const ClockHeader({super.key, this.now, this.events, this.wakeMinutes = defaultWakeMinutes, this.windDownMinutes = defaultWindDownMinutes, this.place = '', this.sleepMinutes, this.tools, this.centre, this.jump, this.doNow});
  /// The waking day, as minutes after midnight (from the person's settings).
  final int wakeMinutes, windDownMinutes;
  final String place;
  final int? sleepMinutes;
  /// The updated stamp and the page's buttons, shown under the time.
  final Widget? tools;
  /// The next deadline (and quick links), shown between the clock and the bars.
  final Widget? centre;
  /// Quick links: under the buttons beside the next deadline, or last on a phone.
  final Widget? jump;
  /// "Do this first": the one task to start, under the bars on the right.
  final Widget? doNow;
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
    final time = Wrap(crossAxisAlignment: WrapCrossAlignment.end, spacing: 14, runSpacing: 4, children: [
      Text(DateFormat('h:mm a').format(now), style: const TextStyle(fontSize: NextUpType.clock, fontWeight: FontWeight.w800, height: 1, fontFeatures: monoFeatures)),
      Padding(padding: const EdgeInsets.only(bottom: 6), child: Text([DateFormat('EEEE, MMMM d').format(now), if (widget.place.isNotEmpty) widget.place].join('  ·  '), style: muted)),
    ]);
    // The time, the date and the page's buttons share one card, like the panels around it.
    final head = Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 10, 8),
      decoration: BoxDecoration(color: NextUpColors.panel, borderRadius: BorderRadius.circular(18), border: Border.all(color: NextUpColors.line)),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [time, if (widget.tools != null) ...[const SizedBox(height: 6), Transform.translate(offset: const Offset(-4, 0), child: widget.tools!)]]),
    );
    final clock = SizedBox(
      width: 460,
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [head, if (widget.jump != null) ...[const SizedBox(height: 12), widget.jump!]]),
    );
    final work = _Card(
      label: 'Work time left today',
      value: left.isNegative ? 'Wind-down time. Log XP and rest.' : '${_fmt(left)} until wind-down',
      fraction: frac,
      from: 'Wake ${_hm(start)}',
      to: ['Wind-down ${_hm(end)}', if (widget.sleepMinutes != null) 'Sleep ${_hm(DateTime(now.year, now.month, now.day, 0, widget.sleepMinutes!))}'].join('  ·  '),
    );
    final freeCard = free == null ? null : _Card(label: free.title, value: free.value, fraction: free.fraction, from: free.from, to: free.to);
    final cards = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (freeCard != null) ...[freeCard, const SizedBox(height: 8)],
      work,
      if (widget.doNow != null) ...[const SizedBox(height: 8), widget.doNow!],
    ]);
    final centre = widget.centre;
    return LayoutBuilder(builder: (context, box) {
      // Wide: the clock, the next deadline in the centre and the progress bars on the right, as three columns.
      if (box.maxWidth >= 1100 && centre != null) {
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          clock,
          const SizedBox(width: 28),
          Expanded(child: centre),
          const SizedBox(width: 16),
          Expanded(child: cards),
        ]);
      }
      // Medium: the clock on its own line, then the next deadline and the bars side by side.
      if (box.maxWidth >= 640 && centre != null) {
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          clock,
          const SizedBox(height: 12),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: centre), const SizedBox(width: 16), Expanded(child: cards)]),
        ]);
      }
      // Phone: everything stacks.
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        head,
        if (centre != null) ...[const SizedBox(height: 12), centre],
        const SizedBox(height: 12),
        cards,
        if (widget.jump != null) ...[const SizedBox(height: 12), widget.jump!],
      ]);
    });
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
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Flexible(child: Text(from!, maxLines: 1, overflow: TextOverflow.ellipsis, style: small)), const SizedBox(width: 8), Flexible(child: Text(to ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.end, style: small))]),
        ],
      ]),
    );
  }
}

/// The time until you are free: while an event is on, how far through it you are; while free, how far
/// through the gap before the next event. Null when there is nothing left on today's calendar.
({String title, String value, double fraction, String from, String to})? freeBar(List<CalendarEvent>? events, DateTime now, DateTime dayStart) {
  if (events == null) return null;
  final day = DaySchedule(events, now);
  final cur = day.current;
  if (cur != null) {
    final f = (now.difference(cur.start).inSeconds / cur.length.inSeconds).clamp(0.0, 1.0);
    return (title: 'Until free', value: '${_fmt(cur.end.difference(now))} · ${cur.title} ends ${DateFormat('h:mm a').format(cur.end)}', fraction: f, from: 'Started ${_hm(cur.start)}', to: 'Free ${_hm(cur.end)}');
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
  return (title: 'Free until ${next.title}', value: _fmt(next.start.difference(now)), fraction: f, from: 'Free since ${_hm(from)}', to: '${next.title} ${_hm(next.start)}');
}
