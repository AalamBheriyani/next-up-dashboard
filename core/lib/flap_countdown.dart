// The flip-board countdown: split-flap style digits for days, hours, minutes and seconds.
import 'dart:async';

import 'package:flutter/material.dart';

import 'theme.dart';

class FlapCountdown extends StatefulWidget {
  const FlapCountdown({super.key, required this.target, this.now});
  final DateTime target;
  final DateTime Function()? now; // for tests

  @override
  State<FlapCountdown> createState() => _FlapCountdownState();
}

class _FlapCountdownState extends State<FlapCountdown> {
  Timer? _timer;
  late Duration _left;

  DateTime _now() => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(_tick));
  }

  void _tick() {
    final d = widget.target.difference(_now());
    _left = d.isNegative ? Duration.zero : d;
  }

  @override
  void didUpdateWidget(FlapCountdown old) {
    super.didUpdateWidget(old);
    _tick();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final units = <(String, int)>[
      if (_left.inDays > 0) ('d', _left.inDays),
      ('h', _left.inHours % 24),
      ('m', _left.inMinutes % 60),
      ('s', _left.inSeconds % 60),
    ];
    return Semantics(
      label: '${_left.inDays} days ${_left.inHours % 24} hours ${_left.inMinutes % 60} minutes left',
      excludeSemantics: true,
      // Scales down in narrow cards instead of overflowing.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final u in units) ...[
              _Flap(u.$2.toString().padLeft(2, '0')),
              Padding(
                padding: const EdgeInsets.only(left: 3, right: 10, bottom: 6),
                child: Text(u.$1, style: const TextStyle(color: NextUpColors.muted, fontSize: NextUpType.caption, fontWeight: FontWeight.w600)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Flap extends StatelessWidget {
  const _Flap(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(color: NextUpColors.raised, borderRadius: BorderRadius.circular(6)),
      child: Stack(alignment: Alignment.center, children: [
        Text(
          text,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 30,
            fontWeight: FontWeight.w700,
            fontFeatures: monoFeatures,
            height: 1,
          ),
        ),
        // The hinge line across the middle of a split flap.
        Positioned.fill(child: Center(child: Container(height: 1, color: Colors.black.withValues(alpha: 0.7)))),
      ]),
    );
  }
}
