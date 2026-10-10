// Habit heatmap: one square per day, shaded by how many habit quests were logged in the Quest Log.
import 'package:flutter/material.dart';
import 'package:next_up_core/deadline_source.dart';
import 'package:next_up_core/quest.dart';
import 'package:next_up_core/theme.dart';

import 'heat_grid.dart';
import 'panel.dart';

class HabitsPanel extends StatefulWidget {
  const HabitsPanel({super.key, required this.repo, this.now});
  final XpRepository repo;
  final DateTime Function()? now;

  @override
  State<HabitsPanel> createState() => _HabitsPanelState();
}

class _HabitsPanelState extends State<HabitsPanel> {
  List<Quest>? _habits;
  List<XpRow> _log = [];
  String? _error;
  String _pick = '';

  @override
  void initState() {
    super.initState();
    widget.repo.load().then((d) {
      if (mounted) {
        setState(() {
          _habits = d.quests.where((q) => RegExp('habit', caseSensitive: false).hasMatch(q.cat)).toList();
          _log = d.log;
        });
      }
    }).catchError((Object e) {
      if (mounted) setState(() => _error = e is SourceException ? e.message : 'Habits failed to load.');
    });
  }

  @override
  Widget build(BuildContext context) {
    final habits = _habits;
    final today = (widget.now ?? DateTime.now)();
    final ids = _pick.isEmpty ? {...?habits?.map((h) => h.id)} : {_pick};
    final counts = <String, int>{};
    for (final r in _log) {
      if (r.kind == 'undo' || !ids.contains(r.q)) continue;
      final d = DateTime.fromMillisecondsSinceEpoch(r.t);
      final k = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      counts[k] = (counts[k] ?? 0) + 1;
    }
    return Panel(
      title: 'Habits',
      trailing: habits == null || habits.isEmpty
          ? null
          : DropdownButton<String>(
              value: _pick,
              underline: const SizedBox.shrink(),
              isDense: true,
              style: const TextStyle(fontSize: NextUpType.caption, color: NextUpColors.muted),
              onChanged: (v) => setState(() => _pick = v ?? ''),
              items: [const DropdownMenuItem(value: '', child: Text('All habits')), for (final h in habits) DropdownMenuItem(value: h.id, child: Text(h.name))],
            ),
      child: _error != null
          ? Text(_error!, style: const TextStyle(color: NextUpColors.muted))
          : habits == null
              ? const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  HeatGrid(counts: counts, today: today, color: NextUpColors.ok, unit: 'check-in'),
                  const SizedBox(height: 8),
                  heatCaption(HeatSummary(counts, today), 'habit check-in'),
                ]),
    );
  }
}
