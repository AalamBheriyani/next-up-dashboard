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
        Text('${c.done} done', style: TextStyle(color: NextUpColors.muted, fontSize: NextUpType.caption)),
        IconButton(tooltip: 'Timer settings', visualDensity: VisualDensity.compact, iconSize: 18, onPressed: () => showDialog<void>(context: context, builder: (_) => TimerSettings(controller: c)), icon: const Icon(Icons.tune_rounded)),
        IconButton(tooltip: 'Fullscreen', visualDensity: VisualDensity.compact, iconSize: 18, onPressed: _full, icon: const Icon(Icons.fullscreen_rounded)),
      ]),
      child: Focus(onKeyEvent: (_, e) => timerKeys(c, e), child: Center(child: TimerBody(controller: c, dial: 170))),
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
      Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 4, children: [
        FilledButton(onPressed: c.running ? c.pause : c.start, child: Text(c.running ? 'Pause' : 'Start')),
        OutlinedButton(onPressed: c.reset, child: const Text('Reset')),
        TextButton(onPressed: c.skip, child: const Text('Skip')),
      ]),
    ]);
  }
}

/// The timer's lengths, the long-break rhythm and auto-start. Each change applies and is kept at once.
class TimerSettings extends StatelessWidget {
  const TimerSettings({super.key, required this.controller});
  final FocusController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return AlertDialog(
      title: const Text('Timer settings'),
      content: SizedBox(
        width: 340,
        child: ListenableBuilder(
          listenable: c,
          builder: (context, _) => Column(mainAxisSize: MainAxisSize.min, children: [
            _Step('Pomodoro', '${c.focusMin} min', () => c.setSettings(focus: c.focusMin - 5 < 1 ? 1 : c.focusMin - 5), () => c.setSettings(focus: c.focusMin + 5)),
            _Step('Short break', '${c.shortMin} min', () => c.setSettings(short: c.shortMin - 1), () => c.setSettings(short: c.shortMin + 1)),
            _Step('Long break', '${c.longMin} min', () => c.setSettings(long: c.longMin - 5 < 1 ? 1 : c.longMin - 5), () => c.setSettings(long: c.longMin + 5)),
            _Step('Long break every', '${c.every} pomodoros', () => c.setSettings(every: c.every - 1), () => c.setSettings(every: c.every + 1)),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Start the next session by itself'),
              value: c.autoContinue,
              onChanged: (v) => c.setSettings(auto: v),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(onPressed: () => c.setSettings(focus: 25, short: 5, long: 15, every: 4, auto: true), child: const Text('Back to 25 / 5 / 15')),
            ),
          ]),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done'))],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step(this.label, this.value, this.less, this.more);
  final String label, value;
  final VoidCallback less, more;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Expanded(child: Text(label)),
          IconButton(tooltip: 'Less $label', onPressed: less, icon: const Icon(Icons.remove_rounded, size: 18)),
          SizedBox(width: 100, child: Text(value, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, fontFeatures: monoFeatures))),
          IconButton(tooltip: 'More $label', onPressed: more, icon: const Icon(Icons.add_rounded, size: 18)),
        ]),
      );
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
