// A focus timer with a dial: 25 min focus, 5 min break, or a long 50. Runs in the page, so keep the tab
// open; a "finished" notification needs the phone app.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  void _full() => showGeneralDialog<void>(
        context: context,
        barrierLabel: 'Close fullscreen timer',
        barrierColor: Colors.black,
        pageBuilder: (context, _, _) => _FullTimer(controller: c),
      );

  @override
  Widget build(BuildContext context) {
    return Panel(
      title: 'Focus timer',
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('${c.done} finished', style: TextStyle(color: NextUpColors.muted, fontSize: NextUpType.caption)),
        IconButton(tooltip: 'Fullscreen', visualDensity: VisualDensity.compact, iconSize: 18, onPressed: _full, icon: const Icon(Icons.fullscreen_rounded)),
      ]),
      child: Focus(onKeyEvent: (_, e) => timerKeys(c, e), child: TimerBody(controller: c, dial: 170)),
    );
  }
}

/// Space or Enter starts and pauses, the arrows add or take a minute, like the old site's dial.
KeyEventResult timerKeys(FocusController c, KeyEvent e) {
  if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
  final k = e.logicalKey;
  if (k == LogicalKeyboardKey.space || k == LogicalKeyboardKey.enter) {
    if (e is KeyDownEvent) c.running ? c.pause() : c.start();
  } else if (k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.arrowRight) {
    c.nudge(1);
  } else if (k == LogicalKeyboardKey.arrowDown || k == LogicalKeyboardKey.arrowLeft) {
    c.nudge(-1);
  } else {
    return KeyEventResult.ignored;
  }
  return KeyEventResult.handled;
}

/// The modes, the dial and the buttons; the panel and the fullscreen view both use it.
class TimerBody extends StatelessWidget {
  const TimerBody({super.key, required this.controller, required this.dial});
  final FocusController controller;
  final double dial;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final left = c.left;
    final mm = left.inSeconds ~/ 60, ss = left.inSeconds % 60;
    final k = dial / 170;
    const modes = [(FocusMode.focus, 'Focus'), (FocusMode.shortBreak, 'Break'), (FocusMode.longBreak, 'Long')];
    return Column(mainAxisSize: MainAxisSize.min, children: [
      SegmentedButton<FocusMode>(
        showSelectedIcon: false,
        segments: [for (final m in modes) ButtonSegment(value: m.$1, label: Text('${m.$2} ${switch (m.$1) { FocusMode.focus => c.focusMin, FocusMode.shortBreak => c.shortMin, FocusMode.longBreak => c.longMin }}'))],
        selected: {c.mode},
        onSelectionChanged: (s) => c.setMode(s.first),
      ),
      SizedBox(height: 16 * k),
      SizedBox(
        width: dial,
        height: dial,
        child: CustomPaint(
          painter: _DialPainter(c.fraction, c.mode == FocusMode.focus ? NextUpColors.accent : NextUpColors.ok, 8 * k),
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('${mm.toString().padLeft(2, '0')}:${ss.toString().padLeft(2, '0')}', style: TextStyle(fontSize: NextUpType.display * k, fontWeight: FontWeight.w800, fontFeatures: monoFeatures)),
              if (c.label.isNotEmpty) Padding(padding: EdgeInsets.symmetric(horizontal: 12 * k), child: Text(c.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: NextUpColors.muted, fontSize: NextUpType.caption * k))),
            ]),
          ),
        ),
      ),
      SizedBox(height: 14 * k),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        FilledButton(onPressed: c.running ? c.pause : c.start, child: Text(c.running ? 'Pause' : 'Start')),
        const SizedBox(width: 8),
        OutlinedButton(onPressed: c.reset, child: const Text('Reset')),
      ]),
    ]);
  }
}

/// The timer filling the window, for a focus block on a second screen. Esc or the button closes it.
class _FullTimer extends StatelessWidget {
  const _FullTimer({required this.controller});
  final FocusController controller;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final dial = (size.shortestSide * 0.6).clamp(170.0, 640.0);
    return Material(
      color: NextUpColors.bg,
      child: Stack(children: [
        Center(
          child: Focus(
            autofocus: true,
            onKeyEvent: (_, e) => timerKeys(controller, e),
            child: ListenableBuilder(listenable: controller, builder: (context, _) => TimerBody(controller: controller, dial: dial)),
          ),
        ),
        Positioned(top: 16, right: 16, child: IconButton(tooltip: 'Exit fullscreen', onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.fullscreen_exit_rounded))),
      ]),
    );
  }
}

class _DialPainter extends CustomPainter {
  _DialPainter(this.frac, this.color, this.stroke);
  final double frac, stroke;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero), r = size.shortestSide / 2 - stroke;
    final track = Paint()..style = PaintingStyle.stroke..strokeWidth = stroke..color = NextUpColors.raised;
    final arc = Paint()..style = PaintingStyle.stroke..strokeWidth = stroke..strokeCap = StrokeCap.round..color = color;
    canvas.drawCircle(c, r, track);
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), -math.pi / 2, 2 * math.pi * frac, false, arc);
  }

  @override
  bool shouldRepaint(_DialPainter old) => old.frac != frac || old.color != color || old.stroke != stroke;
}
