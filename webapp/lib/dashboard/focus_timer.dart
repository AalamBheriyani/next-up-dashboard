// A focus timer with a dial: 25 min focus, 5 min break, or a long 50. Runs in the page, so keep the tab
// open; a "finished" notification needs the phone app.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:next_up_core/theme.dart';

import 'focus_controller.dart';
import 'panel.dart';

class FocusTimer extends StatefulWidget {
  const FocusTimer({super.key, required this.controller});
  final FocusController controller;

  @override
  State<FocusTimer> createState() => _FocusTimerState();
}

class _FocusTimerState extends State<FocusTimer> {
  FocusController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.addListener(_changed);
  }

  @override
  void dispose() {
    c.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final left = c.left;
    final mm = left.inSeconds ~/ 60, ss = left.inSeconds % 60;
    const modes = [(FocusMode.focus, 'Focus'), (FocusMode.shortBreak, 'Break'), (FocusMode.longBreak, 'Long')];
    return Panel(
      title: 'Focus timer',
      trailing: Text('${c.done} finished', style: TextStyle(color: NextUpColors.muted, fontSize: NextUpType.caption)),
      child: Column(children: [
        SegmentedButton<FocusMode>(
          showSelectedIcon: false,
          segments: [for (final m in modes) ButtonSegment(value: m.$1, label: Text('${m.$2} ${switch (m.$1) { FocusMode.focus => c.focusMin, FocusMode.shortBreak => c.shortMin, FocusMode.longBreak => c.longMin }}'))],
          selected: {c.mode},
          onSelectionChanged: (s) => c.setMode(s.first),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: 170,
          height: 170,
          child: CustomPaint(
            painter: _DialPainter(c.fraction, c.mode == FocusMode.focus ? NextUpColors.accent : NextUpColors.ok),
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('${mm.toString().padLeft(2, '0')}:${ss.toString().padLeft(2, '0')}', style: const TextStyle(fontSize: NextUpType.display, fontWeight: FontWeight.w800, fontFeatures: monoFeatures)),
                if (c.label.isNotEmpty) Text(c.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: NextUpColors.muted, fontSize: NextUpType.caption)),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          FilledButton(onPressed: c.running ? c.pause : c.start, child: Text(c.running ? 'Pause' : 'Start')),
          const SizedBox(width: 8),
          OutlinedButton(onPressed: c.reset, child: const Text('Reset')),
        ]),
      ]),
    );
  }
}

class _DialPainter extends CustomPainter {
  _DialPainter(this.frac, this.color);
  final double frac;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero), r = size.shortestSide / 2 - 8;
    final track = Paint()..style = PaintingStyle.stroke..strokeWidth = 8..color = NextUpColors.raised;
    final arc = Paint()..style = PaintingStyle.stroke..strokeWidth = 8..strokeCap = StrokeCap.round..color = color;
    canvas.drawCircle(c, r, track);
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), -math.pi / 2, 2 * math.pi * frac, false, arc);
  }

  @override
  bool shouldRepaint(_DialPainter old) => old.frac != frac || old.color != color;
}
