// A titled card, the building block of the dashboard grid (the site calls these panels).
import 'package:flutter/material.dart';
import 'package:next_up_core/theme.dart';

class Panel extends StatelessWidget {
  const Panel({super.key, required this.title, required this.child, this.trailing, this.accent});
  final String title;
  final Widget child;
  final Widget? trailing;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: NextUpColors.panel, borderRadius: BorderRadius.circular(18), border: Border.all(color: NextUpColors.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Text(title.toUpperCase(), style: TextStyle(color: accent ?? NextUpColors.muted, fontSize: NextUpType.label, fontWeight: FontWeight.w700, letterSpacing: 1.4)),
          const Spacer(),
          ?trailing,
        ]),
        const SizedBox(height: 12),
        child,
      ]),
    );
  }
}
