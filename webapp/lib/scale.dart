// Full-screen scaling: past a laptop-sized window the whole site (text, panels, spacing, pop-ups) is drawn
// larger instead of leaving more empty space. It lays the page out at a smaller virtual size and draws that
// scaled up, so every widget keeps its proportions.
import 'package:flutter/widgets.dart';

const scaleFrom = 1440.0;
const scaleMax = 2.0;

/// How much to enlarge a window [width] pixels wide: 1 up to [scaleFrom], then in step with the width.
double screenScale(double width) => width <= scaleFrom ? 1 : (width / scaleFrom).clamp(1.0, scaleMax);

class ScaleToScreen extends StatelessWidget {
  const ScaleToScreen({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final s = screenScale(mq.size.width);
    if (s == 1) return child;
    final virtual = Size(mq.size.width / s, mq.size.height / s);
    return ClipRect(
      child: OverflowBox(
        alignment: Alignment.topLeft,
        minWidth: virtual.width,
        maxWidth: virtual.width,
        minHeight: virtual.height,
        maxHeight: virtual.height,
        child: Transform.scale(
          scale: s,
          alignment: Alignment.topLeft,
          child: MediaQuery(data: mq.copyWith(size: virtual), child: SizedBox.fromSize(size: virtual, child: child)),
        ),
      ),
    );
  }
}
