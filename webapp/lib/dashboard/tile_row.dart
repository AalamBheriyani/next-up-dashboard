// A row of small stat tiles that always fills the width: four across on a wide panel, two on a phone, with
// every tile in a row the same height.
import 'package:flutter/material.dart';

class TileRow extends StatelessWidget {
  const TileRow({super.key, required this.children, this.gap = 12, this.minTile = 170});
  final List<Widget> children;
  final double gap;
  /// The narrowest a tile may get before the row wraps to fewer per line.
  final double minTile;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final fit = ((box.maxWidth + gap) / (minTile + gap)).floor().clamp(1, children.length);
      // Four tiles go 4 or 2 per row, never an odd 3 + 1.
      final per = fit >= children.length ? children.length : (fit >= 2 ? 2 : 1);
      final rows = <Widget>[];
      for (var i = 0; i < children.length; i += per) {
        final row = children.sublist(i, (i + per).clamp(0, children.length));
        rows.add(IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var j = 0; j < per; j++) ...[
              if (j > 0) SizedBox(width: gap),
              Expanded(child: j < row.length ? row[j] : const SizedBox.shrink()),
            ],
          ]),
        ));
      }
      return Column(mainAxisSize: MainAxisSize.min, spacing: gap, children: rows);
    });
  }
}
