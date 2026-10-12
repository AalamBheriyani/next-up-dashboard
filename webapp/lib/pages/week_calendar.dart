// The old Departures "Calendar" view: one column per day with that day's to-dos and calendar events, for this
// week or the next. To-dos can be hidden to see only the calendar.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:next_up_core/calendar.dart';
import 'package:next_up_core/deadline.dart';
import 'package:next_up_core/theme.dart';
import 'package:next_up_core/urgency.dart';
import 'package:url_launcher/url_launcher.dart';

import '../dashboard/panel.dart';
import '../motion.dart';

const hideTodosKey = 'nu.web.hidetodos';

class WeekCalendar extends StatefulWidget {
  const WeekCalendar({super.key, required this.calendar, required this.deadlines, required this.now, this.onEdit, this.hideTodos = false, this.onHideTodos});
  final CalendarSource calendar;
  final List<Deadline> deadlines;
  final DateTime now;
  final void Function(Deadline)? onEdit;
  final bool hideTodos;
  final ValueChanged<bool>? onHideTodos;

  @override
  State<WeekCalendar> createState() => _WeekCalendarState();
}

class _WeekCalendarState extends State<WeekCalendar> {
  int _week = 0; // 0 is the next 7 days, 1 the 7 after (TickTick data covers 14 days ahead)
  final _events = <int, List<CalendarEvent>?>{};
  final _failed = <int>{};

  DateTime get _from {
    final n = widget.now;
    return DateTime(n.year, n.month, n.day + _week * 7);
  }

  @override
  void initState() {
    super.initState();
    _load(0);
  }

  Future<void> _load(int week) async {
    if (_events.containsKey(week)) return;
    _events[week] = null;
    final a = DateTime(widget.now.year, widget.now.month, widget.now.day + week * 7);
    try {
      final evs = await widget.calendar.load(a, a.add(const Duration(days: 7)));
      if (mounted) setState(() => _events[week] = evs);
    } catch (_) {
      if (mounted) {
        setState(() {
          _events[week] = const [];
          _failed.add(week);
        });
      }
    }
  }

  void _go(int week) {
    setState(() => _week = week);
    _load(week);
  }

  @override
  Widget build(BuildContext context) {
    final from = _from;
    final evs = _events[_week];
    final hide = widget.hideTodos;
    final days = [
      for (var i = 0; i < 7; i++)
        () {
          final a = DateTime(from.year, from.month, from.day + i), b = DateTime(from.year, from.month, from.day + i + 1);
          return _Day(
            day: a,
            today: _week == 0 && i == 0,
            todos: hide ? null : [for (final d in widget.deadlines) if (!d.due.isBefore(a) && d.due.isBefore(b)) d],
            events: evs == null ? null : ([for (final e in evs) if (e.start.isBefore(b) && e.end.isAfter(a)) e]..sort(_allDayFirst)),
          );
        }(),
    ];
    final late = [for (final d in widget.deadlines) if (d.due.isBefore(DateTime(widget.now.year, widget.now.month, widget.now.day))) d];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        IconButton(tooltip: 'This week', onPressed: _week == 0 ? null : () => _go(0), icon: const Icon(Icons.chevron_left_rounded)),
        Text(_week == 0 ? 'Next 7 days' : 'The 7 days after', style: const TextStyle(fontWeight: FontWeight.w700)),
        IconButton(tooltip: 'Following week', onPressed: _week >= 1 ? null : () => _go(1), icon: const Icon(Icons.chevron_right_rounded)),
        const SizedBox(width: 8),
        FilterChip(label: const Text('Hide to-dos'), selected: hide, onSelected: widget.onHideTodos),
        if (_failed.contains(_week)) Text("Calendar didn't load.", style: TextStyle(color: NextUpColors.muted, fontSize: NextUpType.caption)),
      ]),
      const SizedBox(height: 12),
      if (_week == 0 && !hide && late.isNotEmpty) ...[
        Panel(
          title: 'Overdue',
          accent: NextUpColors.deadline,
          trailing: Text('${late.length}', style: TextStyle(color: NextUpColors.muted, fontSize: NextUpType.label)),
          child: Wrap(spacing: 8, runSpacing: 8, children: [for (final d in late) _Todo(d: d, now: widget.now, onEdit: widget.onEdit, withDate: true)]),
        ),
        const SizedBox(height: 16),
      ],
      LayoutBuilder(builder: (context, box) {
        // Seven columns when they fit; otherwise the days stack, which reads better on a phone.
        if (box.maxWidth >= 1050) {
          return IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var i = 0; i < 7; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(child: _DayColumn(day: days[i], now: widget.now, onEdit: widget.onEdit)),
              ],
            ]),
          );
        }
        return Column(children: [
          for (final d in days)
            Padding(padding: const EdgeInsets.only(bottom: 10), child: _DayColumn(day: d, now: widget.now, onEdit: widget.onEdit, wide: true)),
        ]);
      }),
    ]);
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

int _allDayFirst(CalendarEvent x, CalendarEvent y) => x.allDay != y.allDay ? (x.allDay ? -1 : 1) : x.start.compareTo(y.start);

class _Day {
  const _Day({required this.day, required this.today, required this.todos, required this.events});
  final DateTime day;
  final bool today;
  final List<Deadline>? todos; // null when hidden
  final List<CalendarEvent>? events; // null while loading
}

class _DayColumn extends StatelessWidget {
  const _DayColumn({required this.day, required this.now, this.onEdit, this.wide = false});
  final _Day day;
  final DateTime now;
  final void Function(Deadline)? onEdit;
  final bool wide; // stacked: the day's name sits beside its items

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(color: NextUpColors.muted, fontSize: NextUpType.caption);
    final head = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(day.today ? 'Today' : DateFormat('EEE').format(day.day), style: TextStyle(fontWeight: FontWeight.w800, color: day.today ? NextUpColors.accent : null)),
      Text(DateFormat('MMM d').format(day.day), style: muted),
    ]);
    final evs = day.events;
    final items = <Widget>[
      if (day.todos != null)
        for (final d in day.todos!) Padding(padding: const EdgeInsets.only(bottom: 6), child: _Todo(d: d, now: now, onEdit: onEdit)),
      if (day.todos != null && (evs == null || evs.isNotEmpty)) const SizedBox(height: 4),
      if (evs == null) Text('Loading…', style: muted),
      if (evs != null && evs.isEmpty && (day.todos?.isEmpty ?? true)) Text('Nothing planned', style: muted),
      if (evs != null)
        for (final e in evs) Padding(padding: const EdgeInsets.only(bottom: 6), child: _Event(e: e, now: now)),
    ];
    return AnimatedContainer(
      duration: motionFast,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NextUpColors.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: day.today ? NextUpColors.accent : NextUpColors.line, width: day.today ? 1.5 : 1),
      ),
      child: wide
          ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 64, child: head),
              const SizedBox(width: 8),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: items)),
            ])
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [head, const SizedBox(height: 10), ...items]),
    );
  }
}

class _Todo extends StatelessWidget {
  const _Todo({required this.d, required this.now, this.onEdit, this.withDate = false});
  final Deadline d;
  final bool withDate; // overdue ones are from other days
  final DateTime now;
  final void Function(Deadline)? onEdit;

  @override
  Widget build(BuildContext context) {
    final c = urgencyColor(urgencyOf(d, now));
    return Material(
      color: NextUpColors.raised,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: d.color == 0 ? null : BoxDecoration(border: Border(left: BorderSide(color: Color(d.color), width: 3))),
        child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onEdit == null ? null : () => onEdit!(d),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.only(top: 5), child: Container(width: 7, height: 7, decoration: BoxDecoration(color: c, shape: BoxShape.circle))),
            const SizedBox(width: 6),
            Flexible(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(d.title, style: const TextStyle(fontSize: NextUpType.caption, fontWeight: FontWeight.w600)),
                Text([if (withDate) DateFormat('EEE MMM d').format(d.due), if (!d.allDay) DateFormat('h:mm a').format(d.due), if (d.list.isNotEmpty) d.list].join(' · ').ifEmpty('To-do'), style: TextStyle(color: NextUpColors.muted, fontSize: NextUpType.label)),
              ]),
            ),
          ]),
        ),
      ),
      ),
    );
  }
}

class _Event extends StatelessWidget {
  const _Event({required this.e, required this.now});
  final CalendarEvent e;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final past = !e.end.isAfter(now);
    final hm = DateFormat('h:mm a');
    final card = Opacity(
      opacity: past ? 0.5 : 1,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: NextUpColors.accent.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(8),
          border: Border(left: BorderSide(color: NextUpColors.accent, width: 3)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(e.title, style: const TextStyle(fontSize: NextUpType.caption, fontWeight: FontWeight.w600)),
          Text(e.allDay ? 'all day' : '${hm.format(e.start)}–${hm.format(e.end)}', style: TextStyle(color: NextUpColors.muted, fontSize: NextUpType.label)),
        ]),
      ),
    );
    if (e.link.isEmpty) return card;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: () => launchUrl(Uri.parse(e.link), webOnlyWindowName: '_blank'), child: Tooltip(message: 'Open in Google Calendar', waitDuration: const Duration(milliseconds: 600), child: card)),
    );
  }
}
