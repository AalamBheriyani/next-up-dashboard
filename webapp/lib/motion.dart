// Small, consistent motion used across the pages: things ease in one after another, bars grow to
// their value, numbers count up. Reduced-motion settings turn all of it into instant changes.
import 'dart:math' as math;

import 'package:flutter/material.dart';

const motionFast = Duration(milliseconds: 180);
const motionBase = Duration(milliseconds: 380);
const motionCurve = Curves.easeOutCubic;

bool reduceMotion(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// Fades and slides its child up a little, [index] steps after the page appears.
class Reveal extends StatelessWidget {
  const Reveal({super.key, required this.child, this.index = 0});
  final Widget child;
  final int index;

  @override
  Widget build(BuildContext context) {
    if (reduceMotion(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: motionBase + Duration(milliseconds: 60 * math.min(index, 8)),
      curve: Interval(math.min(index, 8) * 0.08, 1, curve: motionCurve),
      builder: (context, t, c) => Opacity(opacity: t, child: Transform.translate(offset: Offset(0, 14 * (1 - t)), child: c)),
      child: child,
    );
  }
}

/// A horizontal bar that eases to [value] (0 to 1) whenever it changes.
class GrowBar extends StatelessWidget {
  const GrowBar({super.key, required this.value, required this.color, this.height = 8, this.track = const Color(0xFF14161B)});
  final double value;
  final Color color;
  final double height;
  final Color track;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: value.clamp(0.0, 1.0)),
        duration: reduceMotion(context) ? Duration.zero : const Duration(milliseconds: 600),
        curve: motionCurve,
        builder: (context, v, _) => LinearProgressIndicator(value: v, minHeight: height, backgroundColor: track, color: color),
      ),
    );
  }
}

/// A number that counts to its value.
class CountUp extends StatelessWidget {
  const CountUp({super.key, required this.value, required this.format, this.style});
  final double value;
  final String Function(double) format;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value),
      duration: reduceMotion(context) ? Duration.zero : const Duration(milliseconds: 700),
      curve: motionCurve,
      builder: (context, v, _) => Text(format(v), style: style),
    );
  }
}

/// Page change: the new page fades in while sliding up slightly.
Widget pageTransition(Widget child, Animation<double> animation) => FadeTransition(
      opacity: animation,
      child: SlideTransition(position: Tween(begin: const Offset(0, 0.015), end: Offset.zero).animate(CurvedAnimation(parent: animation, curve: motionCurve)), child: child),
    );

/// A short burst of confetti over the page, used when a Track target is reached.
void showConfetti(BuildContext context) {
  if (reduceMotion(context)) return;
  final overlay = Overlay.maybeOf(context);
  if (overlay == null) return;
  late OverlayEntry entry;
  entry = OverlayEntry(builder: (_) => _Confetti(onDone: () => entry.remove()));
  overlay.insert(entry);
}

class _Confetti extends StatefulWidget {
  const _Confetti({required this.onDone});
  final VoidCallback onDone;
  @override
  State<_Confetti> createState() => _ConfettiState();
}

class _ConfettiState extends State<_Confetti> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))
    ..forward().whenComplete(widget.onDone);
  final _rng = math.Random();
  late final List<(double, double, double, Color)> _bits = [
    for (var i = 0; i < 70; i++) (_rng.nextDouble(), _rng.nextDouble() * 0.4, 0.5 + _rng.nextDouble(), const [Color(0xFFE4572E), Color(0xFF2E86AB), Color(0xFFF6AE2D), Color(0xFF43AA8B), Color(0xFF9C4DCC), Color(0xFF4D8DFF)][i % 6]),
  ];

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(child: CustomPaint(painter: _ConfettiPainter(_c, _bits), size: Size.infinite));
  }
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.anim, this.bits) : super(repaint: anim);
  final Animation<double> anim;
  final List<(double, double, double, Color)> bits;

  @override
  void paint(Canvas canvas, Size size) {
    for (final (x, delay, speed, color) in bits) {
      final t = ((anim.value - delay) / (1 - delay)).clamp(0.0, 1.0);
      if (t == 0) continue;
      final y = -20 + (size.height + 40) * Curves.easeIn.transform(t) * speed.clamp(0.5, 1.0);
      final dx = math.sin(t * 8 + x * 10) * 18;
      canvas.save();
      canvas.translate(x * size.width + dx, y);
      canvas.rotate(t * 10 * speed);
      canvas.drawRect(const Rect.fromLTWH(-4, -2, 8, 4), Paint()..color = color.withValues(alpha: 1 - t * 0.6));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => false;
}
