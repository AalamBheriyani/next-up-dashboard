// The big clock, the date and how much of the waking day is left.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:next_up_core/theme.dart';

/// Wake and wind-down times; the site reads these from each person's profile, here they are fixed
/// until a settings page exists.
const dayStartHour = 7;
const dayEndHour = 22;

class ClockHeader extends StatefulWidget {
  const ClockHeader({super.key, this.now});
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
            Text(label, style: TextStyle(color: NextUpColors.muted, fontSize: NextUpType.body)),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: frac, minHeight: 8, backgroundColor: NextUpColors.raised, color: NextUpColors.accent),
            ),
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
