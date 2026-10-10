// A focus timer with a dial: 25 min focus, 5 min break, or a long 50. Runs in the page, so keep the tab
// open; a "finished" notification needs the phone app.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:next_up_core/theme.dart';

import 'panel.dart';

class FocusTimer extends StatefulWidget {
  const FocusTimer({super.key});

  @override
  State<FocusTimer> createState() => _FocusTimerState();
}

class _FocusTimerState extends State<FocusTimer> {
  static const modes = <(String, int)>[('Focus', 25), ('Break', 5), ('Long', 50)];
  int _mode = 0;
  Duration _left = const Duration(minutes: 25);
  Timer? _tick;
  DateTime? _endsAt;
  int _done = 0;

  bool get _running => _tick != null;
  Duration get _total => Duration(minutes: modes[_mode].$2);

  void _pick(int i) {
    _stop();
    setState(() {
      _mode = i;
      _left = Duration(minutes: modes[i].$2);
    });
  }

  void _start() {
    _endsAt = DateTime.now().add(_left);
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) {
      final left = _endsAt!.difference(DateTime.now());
      if (left <= Duration.zero) {
        _stop();
        setState(() {
          if (_mode == 0) _done++;
          _left = _total;
        });
      } else {
        setState(() => _left = left);
      }
    });
    setState(() {});
  }

  void _stop() {
    _tick?.cancel();
    _tick = null;
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final frac = 1 - _left.inMilliseconds / _total.inMilliseconds;
    final mm = _left.inSeconds ~/ 60, ss = _left.inSeconds % 60;
    return Panel(
      title: 'Focus timer',
      trailing: Text('$_done finished', style: TextStyle(color: NextUpColors.muted, fontSize: NextUpType.caption)),
      child: Column(children: [
        SegmentedButton<int>(
          showSelectedIcon: false,
          segments: [for (var i = 0; i < modes.length; i++) ButtonSegment(value: i, label: Text('${modes[i].$1} ${modes[i].$2}'))],
          selected: {_mode},
          onSelectionChanged: (s) => _pick(s.first),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: 170,
          height: 170,
          child: CustomPaint(
            painter: _DialPainter(frac, _mode == 1 ? NextUpColors.ok : NextUpColors.accent),
            child: Center(
              child: Text('${mm.toString().padLeft(2, '0')}:${ss.toString().padLeft(2, '0')}',
                  style: const TextStyle(fontSize: NextUpType.display, fontWeight: FontWeight.w800, fontFeatures: monoFeatures)),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          FilledButton(onPressed: _running ? () => setState(_stop) : _start, child: Text(_running ? 'Pause' : 'Start')),
          const SizedBox(width: 8),
          OutlinedButton(onPressed: () => _pick(_mode), child: const Text('Reset')),
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
