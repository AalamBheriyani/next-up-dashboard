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
          // A narrow panel shortens its title before its buttons.
          Expanded(child: Text(title.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: accent ?? NextUpColors.muted, fontSize: NextUpType.label, fontWeight: FontWeight.w700, letterSpacing: 1.4))),
          ?trailing,
        ]),
        const SizedBox(height: 12),
        child,
      ]),
    );
  }
}

/// "updated 1:42 PM" beside a page's refresh button, as the old site showed, so stale data is easy to spot.
class UpdatedStamp extends StatelessWidget {
  const UpdatedStamp({super.key, required this.at});
  final DateTime? at;

  @override
  Widget build(BuildContext context) {
    if (at == null) return const SizedBox.shrink();
    final h = at!.hour % 12 == 0 ? 12 : at!.hour % 12;
    final text = 'updated $h:${'${at!.minute}'.padLeft(2, '0')} ${at!.hour < 12 ? 'AM' : 'PM'}';
    return Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Text(text, style: TextStyle(color: NextUpColors.muted, fontSize: NextUpType.label)));
  }
}
