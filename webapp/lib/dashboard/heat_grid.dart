// A GitHub-style year of squares, one per day, shaded by how much happened that day.
import 'package:flutter/material.dart';
import 'package:next_up_core/theme.dart';


String _key(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class HeatSummary {
  HeatSummary(this.counts, DateTime today) {
    final day = DateTime(today.year, today.month, today.day);
    total = counts.values.fold(0, (a, b) => a + b);
    days = counts.values.where((n) => n > 0).length;
    for (var d = day; (counts[_key(d)] ?? 0) > 0; d = DateTime(d.year, d.month, d.day - 1)) {
      streak++;
    }
  }
  final Map<String, int> counts;
  late final int total, days;
  int streak = 0;
}

class HeatGrid extends StatelessWidget {
  const HeatGrid({super.key, required this.counts, required this.today, this.weeks = 53, this.color, this.unit = 'item'});
  final Map<String, int> counts; // 'yyyy-mm-dd' -> n
  final DateTime today;
  final int weeks;
  final Color? color;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final end = DateTime(today.year, today.month, today.day);
    final start = DateTime(end.year, end.month, end.day - end.weekday % 7 - (weeks - 1) * 7); // weeks start on Sunday
    final max = counts.values.fold(1, (a, b) => b > a ? b : a);
    final cols = <Widget>[];
    for (var w = 0; w < weeks; w++) {
      final cells = <Widget>[];
      for (var i = 0; i < 7; i++) {
        final d = DateTime(start.year, start.month, start.day + w * 7 + i);
        if (d.isAfter(end)) {
          cells.add(const SizedBox(width: 12, height: 12));
          continue;
        }
        final n = counts[_key(d)] ?? 0;
        final level = n == 0 ? 0 : (n / max * 4).ceil().clamp(1, 4);
        cells.add(Tooltip(
          message: '${d.month}/${d.day}: $n $unit${n == 1 ? '' : 's'}',
          child: Container(width: 12, height: 12, decoration: BoxDecoration(color: level == 0 ? NextUpColors.raised : (color ?? NextUpColors.accent).withValues(alpha: .25 + .19 * level), borderRadius: BorderRadius.circular(3))),
        ));
      }
      cols.add(Column(mainAxisSize: MainAxisSize.min, spacing: 3, children: cells));
    }
    return SizedBox(
      height: 7 * 12 + 6 * 3,
      child: ListView(
        scrollDirection: Axis.horizontal,
        reverse: true, // starts at today; scroll back for earlier weeks
        children: [
          Row(mainAxisSize: MainAxisSize.min, spacing: 3, children: cols),
        ],
      ),
    );
  }
}

/// The summary line under a heat grid.
Widget heatCaption(HeatSummary s, String unit) => Text('${s.total} $unit${s.total == 1 ? '' : 's'} on ${s.days} days · streak ${s.streak} day${s.streak == 1 ? '' : 's'}', style: TextStyle(color: NextUpColors.muted, fontSize: NextUpType.caption));
