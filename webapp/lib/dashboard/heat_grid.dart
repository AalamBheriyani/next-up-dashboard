// A GitHub-style year of squares, one per day, shaded by how much happened that day.
import 'package:flutter/material.dart';
import 'package:next_up_core/theme.dart';


String _key(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class HeatSummary {
  HeatSummary(this.counts, DateTime today) {
    var day = DateTime(today.year, today.month, today.day);
    total = counts.values.fold(0, (a, b) => a + b);
    days = counts.values.where((n) => n > 0).length;
    // Today still counts until it ends: an empty today doesn't break yesterday's streak.
    if ((counts[_key(day)] ?? 0) == 0) day = DateTime(day.year, day.month, day.day - 1);
    for (var d = day; (counts[_key(d)] ?? 0) > 0; d = DateTime(d.year, d.month, d.day - 1)) {
      streak++;
    }
  }
  final Map<String, int> counts;
  late final int total, days;
  int streak = 0;
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// Up to [weeks] columns of days that fill the width: squares grow on wide panels, and narrow ones show
/// fewer weeks. Month names run along the top.
class HeatGrid extends StatelessWidget {
  const HeatGrid({super.key, required this.counts, required this.today, this.weeks = 53, this.color, this.unit = 'item'});
  final Map<String, int> counts; // 'yyyy-mm-dd' -> n
  final DateTime today;
  final int weeks;
  final Color? color;
  final String unit;

  static const _gap = 3.0, _min = 10.0, _max = 24.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final width = box.maxWidth.isFinite ? box.maxWidth : weeks * (_min + _gap);
      final fit = ((width + _gap) / (_min + _gap)).floor().clamp(1, weeks);
      final cell = ((width + _gap) / fit - _gap).clamp(_min, _max).floorToDouble();
      final end = DateTime(today.year, today.month, today.day);
      final start = DateTime(end.year, end.month, end.day - end.weekday % 7 - (fit - 1) * 7); // weeks start on Sunday
      final max = counts.values.fold(1, (a, b) => b > a ? b : a);
      final cols = <Widget>[];
      final labels = <Widget>[];
      for (var w = 0; w < fit; w++) {
        final first = DateTime(start.year, start.month, start.day + w * 7);
        // A month's name sits over the week its first day falls in.
        final newMonth = first.day <= 7;
        labels.add(SizedBox(
          width: cell + (w == fit - 1 ? 0 : _gap),
          child: newMonth && w < fit - 1 ? OverflowBox(alignment: Alignment.centerLeft, maxWidth: 40, child: Text(_months[first.month - 1], style: TextStyle(fontSize: 10, color: NextUpColors.muted))) : null,
        ));
        final cells = <Widget>[];
        for (var i = 0; i < 7; i++) {
          final d = DateTime(start.year, start.month, start.day + w * 7 + i);
          if (d.isAfter(end)) {
            cells.add(SizedBox(width: cell, height: cell));
            continue;
          }
          final n = counts[_key(d)] ?? 0;
          final level = n == 0 ? 0 : (n / max * 4).ceil().clamp(1, 4);
          cells.add(Tooltip(
            message: '${_months[d.month - 1]} ${d.day}: $n $unit${n == 1 ? '' : 's'}',
            child: Container(width: cell, height: cell, decoration: BoxDecoration(color: level == 0 ? NextUpColors.raised : (color ?? NextUpColors.accent).withValues(alpha: .25 + .19 * level), borderRadius: BorderRadius.circular(cell / 4))),
          ));
        }
        cols.add(Column(mainAxisSize: MainAxisSize.min, spacing: _gap, children: cells));
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        SizedBox(height: 14, child: Row(children: labels)),
        const SizedBox(height: 4),
        Row(mainAxisSize: MainAxisSize.min, spacing: _gap, children: cols),
      ]);
    });
  }
}

/// The summary line under a heat grid.
Widget heatCaption(HeatSummary s, String unit) => Text('${s.total} $unit${s.total == 1 ? '' : 's'} on ${s.days} days · streak ${s.streak} day${s.streak == 1 ? '' : 's'}', style: TextStyle(color: NextUpColors.muted, fontSize: NextUpType.caption));
