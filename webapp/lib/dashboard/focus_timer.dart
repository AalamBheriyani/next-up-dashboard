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
class TimerBody extends StatefulWidget {
  const TimerBody({super.key, required this.controller, required this.dial});
  final FocusController controller;
  final double dial;

  @override
  State<TimerBody> createState() => _TimerBodyState();
}

class _TimerBodyState extends State<TimerBody> {
  int? _pick; // minutes while dragging the dial

  /// Minutes at a point on the dial: counterclockwise from the top, a full turn is an hour (the old dial).
  int _minutesAt(Offset p) {
    final c = Offset(widget.dial / 2, widget.dial / 2), d = p - c;
    var a = math.atan2(-d.dx, -d.dy);
    if (a < 0) a += 2 * math.pi;
    var m = (a / (2 * math.pi) * 60).round();
    if (m == 0) m = (_pick ?? 0) > 30 ? 60 : 1;
    return m.clamp(1, 60);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller, dial = widget.dial;
    final left = _pick == null ? c.left : Duration(minutes: _pick!);
    final mm = left.inSeconds ~/ 60, ss = left.inSeconds % 60;
    final k = dial / 170;
    final tone = timerTone(c);
    const modes = [(FocusMode.focus, 'Focus'), (FocusMode.shortBreak, 'Break'), (FocusMode.longBreak, 'Long')];
    final time = Text('${mm.toString().padLeft(2, '0')}:${ss.toString().padLeft(2, '0')}', style: TextStyle(fontSize: (c.classicFace ? NextUpType.title : NextUpType.display) * k, fontWeight: FontWeight.w800, fontFeatures: monoFeatures));
    return Column(mainAxisSize: MainAxisSize.min, children: [
      SegmentedButton<FocusMode>(
        showSelectedIcon: false,
        segments: [for (final m in modes) ButtonSegment(value: m.$1, label: Text('${m.$2} ${switch (m.$1) { FocusMode.focus => c.focusMin, FocusMode.shortBreak => c.shortMin, FocusMode.longBreak => c.longMin }}'))],
        selected: {c.mode},
        onSelectionChanged: (s) => c.setMode(s.first),
      ),
      SizedBox(height: 16 * k),
      Tooltip(
        message: 'Drag round the dial to set the minutes; let go to start',
        waitDuration: const Duration(seconds: 1),
        child: MouseRegion(
          cursor: SystemMouseCursors.grab,
          child: GestureDetector(
            onPanStart: (e) => setState(() => _pick = _minutesAt(e.localPosition)),
            onPanUpdate: (e) => setState(() => _pick = _minutesAt(e.localPosition)),
            onPanEnd: (_) {
              final m = _pick;
              setState(() => _pick = null);
              if (m != null) c.pickAndStart(m);
            },
            onPanCancel: () => setState(() => _pick = null),
            child: SizedBox(
              width: dial,
              height: dial,
              child: CustomPaint(
                painter: c.classicFace
                    ? _FacePainter(left.inSeconds / 3600, tone, k)
                    : _DialPainter(_pick == null ? c.fraction : 1, tone, 8 * k),
                child: Center(
                  child: c.classicFace
                      // On the classic face the time sits in a small dark disc over the wedge.
                      ? Container(
                          padding: EdgeInsets.symmetric(horizontal: 8 * k, vertical: 2 * k),
                          decoration: BoxDecoration(color: NextUpColors.panel.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(8 * k)),
                          child: time,
                        )
                      : Column(mainAxisSize: MainAxisSize.min, children: [
                          time,
                          if (c.label.isNotEmpty) Padding(padding: EdgeInsets.symmetric(horizontal: 12 * k), child: Text(c.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: NextUpColors.muted, fontSize: NextUpType.caption * k))),
                        ]),
                ),
              ),
            ),
          ),
        ),
      ),
      if (c.classicFace && c.label.isNotEmpty) Padding(padding: EdgeInsets.only(top: 6 * k), child: Text(c.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: NextUpColors.muted, fontSize: NextUpType.caption * k))),
      SizedBox(height: 14 * k),
      Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 4, children: [
        FilledButton(onPressed: c.running ? c.pause : c.start, child: Text(c.running ? 'Pause' : 'Start')),
        OutlinedButton(onPressed: c.reset, child: const Text('Reset')),
        TextButton(onPressed: c.skip, child: const Text('Skip')),
      ]),
    ]);
  }
}

/// The colour of the dial: the person's own choice, else red on the Time Timer face (accent on the ring) and
/// green for breaks.
Color timerTone(FocusController c) => c.mode == FocusMode.focus
    ? (c.focusColor != 0 ? Color(c.focusColor) : (c.classicFace ? NextUpColors.deadline : NextUpColors.accent))
    : (c.breakColor != 0 ? Color(c.breakColor) : NextUpColors.ok);

const _swatches = [0xFFE5484D, 0xFFF76B15, 0xFFFFC53D, 0xFF46A758, 0xFF12A594, 0xFF3E8EF7, 0xFF8E4EC6, 0xFFD6409F];

/// A row of colour dots; the first, empty one means the default.
class _Swatches extends StatelessWidget {
  const _Swatches(this.label, this.value, this.onPick);
  final String label;
  final int value;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    Widget dot(int argb) {
      final on = argb == value;
      return Tooltip(
        message: argb == 0 ? 'Default' : '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}',
        child: InkResponse(
          onTap: () => onPick(argb),
          radius: 18,
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: argb == 0 ? Colors.transparent : Color(argb),
              border: Border.all(color: on ? Colors.white : NextUpColors.line, width: on ? 2.5 : 1),
            ),
            child: argb == 0 ? Icon(Icons.block_rounded, size: 14, color: NextUpColors.muted) : null,
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 8, children: [dot(0), for (final s in _swatches) dot(s)]),
      ]),
    );
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
          builder: (context, _) => SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            _Step('Pomodoro', '${c.focusMin} min', () => c.setSettings(focus: c.focusMin - 5 < 1 ? 1 : c.focusMin - 5), () => c.setSettings(focus: c.focusMin + 5)),
            _Step('Short break', '${c.shortMin} min', () => c.setSettings(short: c.shortMin - 1), () => c.setSettings(short: c.shortMin + 1)),
            _Step('Long break', '${c.longMin} min', () => c.setSettings(long: c.longMin - 5 < 1 ? 1 : c.longMin - 5), () => c.setSettings(long: c.longMin + 5)),
            _Step('Long break every', '${c.every} pomodoros', () => c.setSettings(every: c.every - 1), () => c.setSettings(every: c.every + 1)),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Time Timer face'),
              subtitle: const Text('A filled disc for the minutes left; off shows a thin ring'),
              value: c.classicFace,
              onChanged: (v) => c.setSettings(classic: v),
            ),
            _Swatches('Focus colour', c.focusColor, (v) => c.setSettings(focusColor: v)),
            _Swatches('Break colour', c.breakColor, (v) => c.setSettings(breakColor: v)),
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
          ])),
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

/// The old site's Time Timer face: minute ticks, numbers every five, and a disc for the time left out of an
/// hour, counterclockwise from the top.
class _FacePainter extends CustomPainter {
  _FacePainter(this.hours, this.color, this.k);
  final double hours, k; // time left as a fraction of an hour; k scales with the dial
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero), r = size.shortestSide / 2;
    canvas.drawCircle(c, r - 1, Paint()..color = NextUpColors.raised);
    final tick = Paint()..color = NextUpColors.muted..strokeCap = StrokeCap.round;
    for (var m = 0; m < 60; m++) {
      final a = m / 60 * 2 * math.pi, major = m % 5 == 0;
      final dir = Offset(-math.sin(a), -math.cos(a));
      tick.strokeWidth = (major ? 2 : 1) * k;
      canvas.drawLine(c + dir * (r * .95), c + dir * (r * (major ? .84 : .89)), tick);
      if (major && k >= .9) {
        final tp = TextPainter(text: TextSpan(text: '$m', style: TextStyle(color: NextUpColors.muted, fontSize: 9 * k)), textDirection: TextDirection.ltr)..layout();
        tp.paint(canvas, c + dir * (r * .72) - Offset(tp.width / 2, tp.height / 2));
      }
    }
    final f = hours.clamp(0.0, 1.0);
    if (f > 0) {
      final wedge = Rect.fromCircle(center: c, radius: r * .62);
      canvas.drawArc(wedge, -math.pi / 2, -2 * math.pi * f, true, Paint()..color = color.withValues(alpha: .9));
    }
    canvas.drawCircle(c, 5 * k, Paint()..color = NextUpColors.muted);
  }

  @override
  bool shouldRepaint(_FacePainter old) => old.hours != hours || old.color != color || old.k != k;
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
