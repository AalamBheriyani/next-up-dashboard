// Today hour by hour: the calendar as blocks down a column, with a line at "now", opened scrolled to the
// current hour. The old site's day column.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:next_up_core/calendar.dart';
import 'package:next_up_core/theme.dart';
import 'package:url_launcher/url_launcher.dart';

import 'panel.dart';

class DayColumn extends StatefulWidget {
  const DayColumn({super.key, required this.events, required this.now, this.height = 340});
  final List<CalendarEvent>? events;
  final DateTime now;
  final double height;

  static const hourPx = 52.0;

  @override
  State<DayColumn> createState() => _DayColumnState();
}

class _DayColumnState extends State<DayColumn> {
  late final ScrollController _scroll = ScrollController(initialScrollOffset: (_y(widget.now, _range().$1) - DayColumn.hourPx).clamp(0.0, double.infinity));

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  List<CalendarEvent> get _timed => DaySchedule(widget.events ?? const [], widget.now).timed;

  /// 6 AM to midnight, widened for anything earlier or later.
  (int, int) _range() {
    var h0 = 6, h1 = 24;
    final d0 = DateTime(widget.now.year, widget.now.month, widget.now.day);
    for (final e in _timed) {
      if (!e.start.isBefore(d0)) h0 = e.start.hour < h0 ? e.start.hour : h0;
    }
    return (h0, h1);
  }

  double _y(DateTime t, int h0) {
    final d0 = DateTime(widget.now.year, widget.now.month, widget.now.day);
    return (t.difference(d0).inMinutes / 60 - h0) * DayColumn.hourPx;
  }

  @override
  Widget build(BuildContext context) {
    final now = widget.now;
    final (h0, h1) = _range();
    final hm = DateFormat('h:mm a');
    final total = (h1 - h0) * DayColumn.hourPx;
    return Panel(
      title: 'Today hour by hour',
      child: widget.events == null
          ? Text('Your calendar shows here once it loads.', style: TextStyle(color: NextUpColors.muted))
          : SizedBox(
              height: widget.height,
              child: SingleChildScrollView(
                controller: _scroll,
                child: LayoutBuilder(builder: (context, box) {
                  final lanes = dayLanes(_timed);
                  final laneW = box.maxWidth - 56;
                  return SizedBox(
                  height: total,
                  child: Stack(children: [
                    for (var h = h0; h < h1; h++)
                      Positioned(
                        top: (h - h0) * DayColumn.hourPx,
                        left: 0,
                        right: 0,
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          SizedBox(width: 48, child: Text(DateFormat('h a').format(DateTime(2000, 1, 1, h)), style: TextStyle(color: NextUpColors.muted, fontSize: NextUpType.label))),
                          Expanded(child: Container(height: 1, margin: const EdgeInsets.only(top: 7), color: NextUpColors.line)),
                        ]),
                      ),
                    for (final e in _timed)
                      Positioned(
                        top: _y(e.start, h0).clamp(0, total),
                        // Events that overlap share the width side by side.
                        left: 52 + laneW * lanes[e]!.$1 / lanes[e]!.$2,
                        width: laneW / lanes[e]!.$2 - 2,
                        height: (_y(e.end, h0) - _y(e.start, h0) - 2).clamp(18, total),
                        child: Tooltip(
                          message: '${hm.format(e.start)} to ${hm.format(e.end)} ${e.title}',
                          child: e.link.isEmpty
                              ? _Block(event: e, now: now)
                              : MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(onTap: () => launchUrl(Uri.parse(e.link), webOnlyWindowName: '_blank'), child: _Block(event: e, now: now))),
                        ),
                      ),
                    Positioned(
                      top: _y(now, h0).clamp(0, total - 2),
                      left: 44,
                      right: 0,
                      child: Row(children: [
                        Container(width: 8, height: 8, decoration: BoxDecoration(color: NextUpColors.deadline, shape: BoxShape.circle)),
                        Expanded(child: Container(height: 2, color: NextUpColors.deadline)),
                      ]),
                    ),
                  ]),
                );
                }),
              ),
            ),
    );
  }
}

/// Which side-by-side lane each event sits in, and how many lanes its group of overlapping events needs.
Map<CalendarEvent, (int, int)> dayLanes(List<CalendarEvent> events) {
  final sorted = [...events]..sort((a, b) => a.start.compareTo(b.start));
  final out = <CalendarEvent, (int, int)>{};
  var group = <CalendarEvent>[];
  var laneEnds = <DateTime>[];
  var groupEnd = DateTime(0);
  void close() {
    for (final e in group) {
      out[e] = (out[e]!.$1, laneEnds.length);
    }
    group = [];
    laneEnds = [];
  }

  for (final e in sorted) {
    if (group.isNotEmpty && !e.start.isBefore(groupEnd)) close();
    var lane = laneEnds.indexWhere((end) => !end.isAfter(e.start));
    if (lane < 0) {
      lane = laneEnds.length;
      laneEnds.add(e.end);
    } else {
      laneEnds[lane] = e.end;
    }
    out[e] = (lane, 1);
    group.add(e);
    if (group.length == 1 || e.end.isAfter(groupEnd)) groupEnd = e.end;
  }
  if (group.isNotEmpty) close();
  return out;
}

class _Block extends StatelessWidget {
  const _Block({required this.event, required this.now});
  final CalendarEvent event;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final past = !event.end.isAfter(now), current = !past && !event.start.isAfter(now);
    return LayoutBuilder(builder: (context, box) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: current ? NextUpColors.accent.withValues(alpha: 0.3) : NextUpColors.raised,
          borderRadius: BorderRadius.circular(8),
          border: Border(left: BorderSide(color: past ? NextUpColors.line : NextUpColors.accent, width: 3)),
        ),
        child: Opacity(
          opacity: past ? 0.5 : 1,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(event.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: NextUpType.caption, fontWeight: FontWeight.w700)),
            if (box.maxHeight >= 34)
              Text('${DateFormat('h:mm').format(event.start)}–${DateFormat('h:mm a').format(event.end)}', maxLines: 1, style: TextStyle(color: NextUpColors.muted, fontSize: NextUpType.label)),
          ]),
        ),
      );
    });
  }
}
