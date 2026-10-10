// Now and next: what is on this minute, the gap until the next thing, and the rest of today.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:next_up_core/calendar.dart';
import 'package:next_up_core/theme.dart';

import 'panel.dart';

class CalendarPanel extends StatelessWidget {
  const CalendarPanel({super.key, required this.events, required this.now, this.error, this.onSignIn});
  final List<CalendarEvent>? events;
  final DateTime now;
  final String? error;
  final VoidCallback? onSignIn;

  @override
  Widget build(BuildContext context) {
    return Panel(title: 'Now and next', child: _body());
  }

  Widget _body() {
    if (error != null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(error!, style: const TextStyle(color: NextUpColors.muted)),
        if (onSignIn != null) Padding(padding: const EdgeInsets.only(top: 12), child: FilledButton(onPressed: onSignIn, child: const Text('Sign in with Google'))),
      ]);
    }
    final all = events;
    if (all == null) return const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
    final day = DaySchedule(all, now);
    final current = day.current, next = day.next;
    final t = DateFormat('h:mm a');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (day.allDay.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Wrap(spacing: 8, runSpacing: 6, children: [
            for (final e in day.allDay)
              Chip(label: Text(e.title), visualDensity: VisualDensity.compact, backgroundColor: NextUpColors.raised, side: BorderSide.none),
          ]),
        ),
      if (current != null) _Now(event: current, now: now) else _Free(next: next, now: now),
      if (day.upcoming.isNotEmpty) ...[
        const SizedBox(height: 14),
        for (final e in day.upcoming)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 72, child: Text(t.format(e.start), style: const TextStyle(color: NextUpColors.muted, fontSize: 12, fontFeatures: monoFeatures))),
              Expanded(child: Text(e.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
            ]),
          ),
      ] else if (current == null && day.allDay.isEmpty && all.isEmpty)
        const Padding(padding: EdgeInsets.only(top: 8), child: Text('Nothing booked today.', style: TextStyle(color: NextUpColors.muted))),
      if (day.timed.isNotEmpty) ...[
        const SizedBox(height: 14),
        Text('${_len(day.bookedLeft)} booked for the rest of today', style: const TextStyle(color: NextUpColors.muted, fontSize: 12)),
      ],
    ]);
  }
}

class _Now extends StatelessWidget {
  const _Now({required this.event, required this.now});
  final CalendarEvent event;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final done = (now.difference(event.start).inSeconds / event.length.inSeconds).clamp(0.0, 1.0);
    final left = event.end.difference(now);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: NextUpColors.accent.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('NOW', style: TextStyle(color: NextUpColors.accent, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.4)),
        const SizedBox(height: 4),
        Text(event.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        if (event.location.isNotEmpty) Text(event.location, style: const TextStyle(color: NextUpColors.muted, fontSize: 12)),
        const SizedBox(height: 10),
        ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: done, minHeight: 6, backgroundColor: NextUpColors.raised, color: NextUpColors.accent)),
        const SizedBox(height: 6),
        Text('${_len(left)} left, until ${DateFormat('h:mm a').format(event.end)}', style: const TextStyle(color: NextUpColors.muted, fontSize: 12)),
      ]),
    );
  }
}

class _Free extends StatelessWidget {
  const _Free({required this.next, required this.now});
  final CalendarEvent? next;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final n = next;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: NextUpColors.raised, borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('FREE', style: TextStyle(color: NextUpColors.ok, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.4)),
        const SizedBox(height: 4),
        Text(n == null ? 'Nothing else today.' : '${_len(n.start.difference(now))} until ${n.title}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

String _len(Duration d) {
  if (d.inMinutes < 1) return 'under a minute';
  final h = d.inHours, m = d.inMinutes % 60;
  if (h == 0) return '${m}m';
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}
