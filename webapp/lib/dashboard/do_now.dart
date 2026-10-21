// "Do this now": the one deadline to work on, how urgent it is, and a single tap to start. Overdue work
// comes first (oldest first), then whatever is due next.
import 'package:flutter/material.dart';
import 'package:next_up_core/deadline.dart';
import 'package:next_up_core/theme.dart';
import 'package:next_up_core/urgency.dart';

/// The deadline to push right now: the longest-overdue one, else the next due.
Deadline? doNowTarget(List<Deadline> all, DateTime now) {
  final g = DeadlineGroups(all, now);
  return g.overdue.isNotEmpty ? g.overdue.first : g.next;
}

class DoNowStrip extends StatelessWidget {
  const DoNowStrip({super.key, required this.deadline, required this.now, required this.onStart, this.onFirstStep});
  final Deadline deadline;
  final DateTime now;
  final VoidCallback onStart;
  final VoidCallback? onFirstStep; // asks Claude for a 2-minute first step, when Ask Claude is available

  @override
  Widget build(BuildContext context) {
    final u = urgencyOf(deadline, now);
    final color = urgencyColor(u);
    final loud = u == Urgency.overdue || u == Urgency.critical || u == Urgency.soon;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: loud ? .1 : .05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: loud ? .9 : .4), width: loud ? 1.5 : 1),
      ),
      child: Wrap(spacing: 16, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 220, maxWidth: 560),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(u == Urgency.overdue ? 'DO THIS FIRST' : 'DO THIS NOW', style: TextStyle(color: color, fontSize: NextUpType.label, fontWeight: FontWeight.w800, letterSpacing: 1.4)),
            const SizedBox(height: 4),
            Text(deadline.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: NextUpType.subtitle, fontWeight: FontWeight.w800)),
            Text(urgencyLine(deadline, now), style: TextStyle(color: color, fontSize: NextUpType.body, fontWeight: FontWeight.w700)),
          ]),
        ),
        FilledButton.icon(onPressed: onStart, icon: const Icon(Icons.play_arrow_rounded), label: const Text('Start 25 min')),
        if (onFirstStep != null) OutlinedButton.icon(onPressed: onFirstStep, icon: const Icon(Icons.bolt_rounded, size: 18), label: const Text('2-minute first step')),
      ]),
    );
  }
}
