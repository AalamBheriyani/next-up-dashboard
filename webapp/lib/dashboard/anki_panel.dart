// Anki: cards due per deck and a year of review days. Owner only; the laptop relay supplies the numbers.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:next_up_core/anki.dart';
import 'package:next_up_core/theme.dart';

import 'heat_grid.dart';
import 'panel.dart';

class AnkiPanel extends StatefulWidget {
  const AnkiPanel({super.key, required this.source, this.now});
  final AnkiSource source;
  final DateTime Function()? now;

  @override
  State<AnkiPanel> createState() => _AnkiPanelState();
}

class _AnkiPanelState extends State<AnkiPanel> {
  late final Future<AnkiStats?> _stats = widget.source.load();

  @override
  Widget build(BuildContext context) => FutureBuilder<AnkiStats?>(
        future: _stats,
        builder: (context, snap) {
          final s = snap.data;
          if (snap.connectionState != ConnectionState.done) return const Panel(title: 'Anki', child: Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator(strokeWidth: 2))));
          if (s == null) return const Panel(title: 'Anki', child: Text('No Anki data yet. It appears when Anki is open on the laptop.', style: TextStyle(color: NextUpColors.muted)));
          final today = (widget.now ?? DateTime.now)();
          final decks = s.decks.where((d) => d.due > 0).toList()..sort((a, b) => b.due.compareTo(a.due));
          return Panel(
            title: 'Anki',
            trailing: s.at == null ? null : Text('updated ${DateFormat('MMM d, h:mm a').format(s.at!)}', style: const TextStyle(color: NextUpColors.muted, fontSize: NextUpType.label)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('${s.totalDue}', style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800)),
                const SizedBox(width: 8),
                const Padding(padding: EdgeInsets.only(bottom: 6), child: Text('cards due', style: TextStyle(color: NextUpColors.muted))),
              ]),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final d in decks)
                  Tooltip(
                    message: '${d.newCards} new · ${d.learn} learning · ${d.review} review',
                    child: Chip(label: Text('${d.name}  ${d.due}', style: const TextStyle(fontSize: NextUpType.caption)), backgroundColor: NextUpColors.raised, side: BorderSide.none, visualDensity: VisualDensity.compact),
                  ),
              ]),
              const SizedBox(height: 12),
              HeatGrid(counts: s.days, today: today, unit: 'review'),
              const SizedBox(height: 8),
              heatCaption(HeatSummary(s.days, today), 'review'),
            ]),
          );
        },
      );
}
