// Lists: the same deadlines seen through different views. Urgent / Important sorts them into the four boxes of
// the Eisenhower grid; the others group by priority, by due date or by TickTick list. Each group is a box of
// the same size that scrolls.
import 'package:flutter/material.dart';
import 'package:next_up_core/deadline.dart';
import 'package:next_up_core/deadline_source.dart';
import 'package:next_up_core/list_views.dart';
import 'package:next_up_core/theme.dart';
import 'package:next_up_core/today_screen.dart' show finishWithUndo;

import '../dashboard/deadline_box.dart';
import '../dashboard/panel.dart';
import '../motion.dart';
import '../services.dart';
import '../refresh.dart';
import 'week_calendar.dart';

const _viewKey = 'nu.web.listview';

class ListsScreen extends StatefulWidget {
  const ListsScreen({super.key, required this.services, this.onEdit, this.now});
  final Services services;
  final void Function(Deadline)? onEdit;
  final DateTime Function()? now; // for tests

  @override
  State<ListsScreen> createState() => _ListsScreenState();
}

class _ListsScreenState extends State<ListsScreen> with RefreshOnReturn {
  @override
  Future<void> refreshData() => _load();

  List<Deadline>? _all;
  String? _error;
  // The chosen view is remembered on this device, as the old site did. 'calendar' is the week of days with events.
  late String _saved = widget.services.store.get(_viewKey) ?? '';
  late ListViewKind _view = ListViewKind.values.firstWhere((k) => k.name == _saved, orElse: () => ListViewKind.matrix);
  bool get _calendar => _saved == 'calendar';
  late bool _hideTodos = widget.services.store.get(hideTodosKey) == '1';

  void _pick(String name) {
    setState(() {
      _saved = name;
      if (name != 'calendar') _view = ListViewKind.values.byName(name);
    });
    widget.services.store.set(_viewKey, name);
  }
  // Search and list filter, as on the old Departures board.
  String _query = '';
  final Set<String> _lists = {};

  bool _shows(Deadline d) {
    if (_lists.isNotEmpty && !_lists.contains(d.list)) return false;
    final q = _query.trim().toLowerCase();
    return q.isEmpty || d.title.toLowerCase().contains(q) || d.notes.toLowerCase().contains(q) || d.list.toLowerCase().contains(q);
  }

  DateTime _now() => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!widget.services.signedIn()) {
      setState(() => _error = 'Sign in to see your deadlines.');
      return;
    }
    try {
      final all = await widget.services.deadlines.load();
      if (mounted) {
        setState(() {
          _all = all;
          _error = null;
        });
      }
    } on SourceException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _finish(Deadline d) async {
    final before = _all;
    setState(() => _all = before?.where((x) => x.id != d.id).toList());
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (!await finishWithUndo(messenger, widget.services.deadlines, d) && mounted) setState(() => _all = [...?_all, d]);
    } on SourceException catch (e) {
      if (mounted) setState(() => _all = before);
      messenger.showSnackBar(SnackBar(content: Text("Couldn't finish it. ${e.message}")));
    }
  }

  Color _tone(ListViewKind kind, int i) => switch (kind) {
        ListViewKind.matrix => [NextUpColors.deadline, NextUpColors.accent, NextUpColors.soon, NextUpColors.muted][i],
        ListViewKind.priority => [NextUpColors.deadline, NextUpColors.soon, NextUpColors.accent, NextUpColors.muted][i],
        ListViewKind.due => i == 0 ? NextUpColors.deadline : (i == 4 ? NextUpColors.muted : NextUpColors.accent),
        ListViewKind.week => i == 0 ? NextUpColors.deadline : (i == 1 ? NextUpColors.soon : (i == 8 ? NextUpColors.muted : NextUpColors.accent)),
        ListViewKind.list => NextUpColors.accent,
      };

  @override
  Widget build(BuildContext context) {
    final all = _all;
    final now = _now();
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      children: [
        Reveal(child: Row(children: [
          const Text('Lists', style: TextStyle(fontSize: NextUpType.heading, fontWeight: FontWeight.w800)),
          const Spacer(),
          IconButton(tooltip: 'Refresh', onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
        ])),
        const SizedBox(height: 8),
        Reveal(index: 1, child: Wrap(spacing: 8, runSpacing: 8, children: [
          for (final e in listViewNames.entries)
            ChoiceChip(label: Text(e.value), selected: !_calendar && _view == e.key, onSelected: (_) => _pick(e.key.name)),
          ChoiceChip(label: const Text('Calendar'), selected: _calendar, onSelected: (_) => _pick('calendar')),
        ])),
        if (_view == ListViewKind.matrix && !_calendar)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Urgent means late or due within 2 days. Important means medium or high priority in TickTick.', style: TextStyle(color: NextUpColors.muted, fontSize: NextUpType.caption)),
          ),
        if (all != null && all.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SizedBox(
              width: 260,
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                decoration: const InputDecoration(isDense: true, prefixIcon: Icon(Icons.search_rounded, size: 18), hintText: 'Search deadlines', border: OutlineInputBorder()),
              ),
            ),
            if ({for (final d in all) d.list}.length > 1)
              for (final l in ({for (final d in all) if (d.list.isNotEmpty) d.list}.toList()..sort()))
                FilterChip(
                  label: Text(l),
                  selected: _lists.contains(l),
                  onSelected: (on) => setState(() => on ? _lists.add(l) : _lists.remove(l)),
                ),
          ]),
        ],
        const SizedBox(height: 16),
        if (_error != null && all == null) Panel(title: 'Heads up', child: Text(_error!, style: TextStyle(color: NextUpColors.muted))),
        if (all == null && _error == null) const Padding(padding: EdgeInsets.only(top: 80), child: Center(child: CircularProgressIndicator())),
        if (all != null && _calendar)
          WeekCalendar(
            calendar: widget.services.calendar,
            deadlines: all.where(_shows).toList(),
            now: now,
            onEdit: widget.onEdit,
            hideTodos: _hideTodos,
            onHideTodos: (v) {
              setState(() => _hideTodos = v);
              widget.services.store.set(hideTodosKey, v ? '1' : '0');
            },
          ),
        if (all != null && !_calendar)
          LayoutBuilder(builder: (context, box) {
            final groups = groupsFor(_view, all.where(_shows).toList(), now);
            var cols = box.maxWidth >= 1000 ? 3 : (box.maxWidth >= 600 ? 2 : 1);
            if (cols == 3 && groups.length % 3 == 1) cols = 2; // four boxes read better as 2 by 2 than 3 and 1
            final w = (box.maxWidth - 16 * (cols - 1)) / cols;
            return Wrap(spacing: 16, runSpacing: 16, children: [
              for (var i = 0; i < groups.length; i++)
                SizedBox(
                  width: w,
                  child: Panel(
                    title: groups[i].title,
                    accent: _tone(_view, i),
                    trailing: Text('${groups[i].items.length}', style: TextStyle(color: NextUpColors.muted, fontSize: NextUpType.label)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (groups[i].hint.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(groups[i].hint, style: TextStyle(color: NextUpColors.muted, fontSize: NextUpType.caption))),
                      DeadlineBox(title: groups[i].title, color: _tone(_view, i), items: groups[i].items, now: now, onFinish: _finish, onEdit: widget.onEdit, showDate: true, showList: _view != ListViewKind.list,
                          // Side by side the boxes share one height; in a single column a short list doesn't leave a gap.
                          height: cols == 1 ? (groups[i].items.length * 64.0 + 8).clamp(64.0, deadlineBoxHeight) : deadlineBoxHeight),
                    ]),
                  ),
                ),
            ]);
          }),
      ],
    );
  }
}
