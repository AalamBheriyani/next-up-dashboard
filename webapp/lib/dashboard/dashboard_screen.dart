// The dashboard: clock and day progress, next deadline, now and next from the calendar, a focus timer,
// the week ahead, and every deadline grouped by urgency. Each panel loads on its own, so a calendar
// problem never hides the deadlines.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:next_up_core/board_layout.dart';
import 'package:next_up_core/calendar.dart';
import 'package:next_up_core/deadline.dart';
import 'package:next_up_core/deadline_source.dart';
import 'package:next_up_core/theme.dart';
import 'package:next_up_core/today_screen.dart';

import '../board/widget_board.dart';
import 'calendar_panel.dart';
import 'deadline_editor.dart';
import 'clock_header.dart';
import 'focus_timer.dart';
import 'panel.dart';
import 'week_strip.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.deadlines,
    required this.calendar,
    required this.signedIn,
    required this.onSignIn,
    this.now,
    this.extras = const [],
    this.layout = const BoardLayout(),
    this.onLayout,
  });
  final DeadlineSource deadlines;
  final CalendarSource calendar;
  final bool Function() signedIn;
  final Future<void> Function() onSignIn;
  final DateTime Function()? now; // for tests
  /// Further panels (habits, Anki) shown below the deadlines, each loading on its own.
  final List<BoardItem> extras;
  /// The saved arrangement of panels, and where to report a change (saved to the account by the shell).
  final BoardLayout layout;
  final ValueChanged<BoardLayout>? onLayout;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List<Deadline>? _deadlines;
  List<CalendarEvent>? _events;
  String? _deadlineError, _calendarError;
  bool _needsSignIn = false;
  bool _loading = false;
  bool _editing = false;
  late BoardLayout _layout = widget.layout;
  Timer? _refresh;
  Timer? _clock;

  @override
  void didUpdateWidget(DashboardScreen old) {
    super.didUpdateWidget(old);
    // A layout arriving from the account (after sign-in) replaces ours unless we're mid-edit.
    if (!_editing && old.layout != widget.layout) _layout = widget.layout;
  }

  void _setLayout(BoardLayout l) {
    setState(() => _layout = l);
    widget.onLayout?.call(l);
  }

  DateTime _now() => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _load();
    // Pick up changes made elsewhere, and move "now" along for the calendar panel.
    _refresh = Timer.periodic(const Duration(minutes: 5), (_) => _load());
    _clock = Timer.periodic(const Duration(seconds: 30), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _refresh?.cancel();
    _clock?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (!widget.signedIn()) {
      setState(() {
        _needsSignIn = true;
        _deadlineError = 'Sign in to see your deadlines and calendar.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _needsSignIn = false;
    });
    final now = _now();
    final start = DateTime(now.year, now.month, now.day);
    await Future.wait([
      _guard(widget.deadlines.load(), (d) => _deadlines = d, (m) => _deadlineError = m, 'Deadlines failed to load.'),
      _guard(widget.calendar.load(start, start.add(const Duration(days: 7))), (c) => _events = c, (m) => _calendarError = m, 'Calendar failed to load.'),
    ]);
    if (mounted) setState(() => _loading = false);
  }

  /// Runs one panel's load; a failure shows in that panel only.
  Future<void> _guard<T>(Future<T> job, void Function(T) ok, void Function(String?) fail, String fallback) async {
    try {
      final value = await job;
      if (mounted) {
        setState(() {
          ok(value);
          fail(null);
        });
      }
    } on SourceException catch (e) {
      if (mounted) {
        setState(() {
          fail(e.message);
          _needsSignIn = _needsSignIn || e.signedOut;
        });
      }
    } catch (_) {
      if (mounted) setState(() => fail(fallback));
    }
  }

  Future<void> _signIn() async {
    try {
      await widget.onSignIn();
    } catch (_) {
      if (mounted) setState(() => _deadlineError = 'Sign-in was cancelled or failed. Try again.');
      return;
    }
    await _load();
  }

  /// Opens the editor for [d], or the add form when null, and reloads if anything changed.
  Future<void> _edit(Deadline? d) async {
    final editor = widget.deadlines;
    if (editor is! DeadlineEditor) return;
    if (await showDeadlineEditor(context, editor as DeadlineEditor, d: d, now: widget.now)) await _load();
  }

  Future<void> _finish(Deadline d) async {
    final before = _deadlines;
    setState(() => _deadlines = before?.where((x) => x.id != d.id).toList());
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.deadlines.complete(d);
      messenger.showSnackBar(SnackBar(content: Text('Done: ${d.title}')));
    } on SourceException catch (e) {
      if (mounted) setState(() => _deadlines = before);
      messenger.showSnackBar(SnackBar(content: Text("Couldn't finish it. ${e.message}")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = _now();
    final items = _items(now);
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: LayoutBuilder(builder: (context, box) {
          final w = box.maxWidth;
          return ListView(
            padding: EdgeInsets.symmetric(horizontal: w >= 720 ? 28 : 16, vertical: 24),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: ClockHeader(now: widget.now)),
                if (_loading) const Padding(padding: EdgeInsets.all(8), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
                if (widget.deadlines is DeadlineEditor) IconButton(tooltip: 'Add a deadline', onPressed: () => _edit(null), icon: const Icon(Icons.add_rounded)),
                IconButton(tooltip: _editing ? 'Done customising' : 'Customise panels', onPressed: () => setState(() => _editing = !_editing), icon: Icon(_editing ? Icons.check_rounded : Icons.dashboard_customize_outlined)),
                IconButton(tooltip: 'Refresh', onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
              ]),
              const SizedBox(height: 20),
              if (_deadlineError != null && _deadlines == null) _Banner(message: _deadlineError!, onSignIn: _needsSignIn ? _signIn : null, onRetry: _load),
              if (_editing) ...[
                BoardBar(items: items, layout: _layout.resolved([for (final i in items) i.id]), onChanged: _setLayout, onReset: () => _setLayout(const BoardLayout()), onDone: () => setState(() => _editing = false)),
                const SizedBox(height: 16),
              ],
              WidgetBoard(items: items, layout: _layout, editing: _editing, onChanged: _setLayout),
            ],
          );
        }),
      ),
    );
  }

  Widget _board(DateTime now) {
    final items = _deadlines;
    if (items == null) {
      return const Panel(title: 'Next deadline', child: Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: CircularProgressIndicator(strokeWidth: 2))));
    }
    final next = DeadlineGroups(items, now).next;
    if (next == null) return Panel(title: 'Next deadline', child: Text('Nothing due. Enjoy the free time.', style: TextStyle(color: NextUpColors.muted)));
    return NextBoard(deadline: next, now: widget.now);
  }

  /// Every panel the dashboard can show; the board places them.
  List<BoardItem> _items(DateTime now) {
    final all = _deadlines ?? const <Deadline>[];
    final g = DeadlineGroups(all, now);
    final next = g.next;
    BoardItem list(String id, String title, Color color, List<Deadline> items, {String? hint, bool showDate = false, int? limit}) => BoardItem(
          id: id,
          name: title,
          span: 6,
          child: Panel(
            title: title,
            accent: color,
            trailing: hint == null ? null : Text(hint, style: TextStyle(color: NextUpColors.muted, fontSize: NextUpType.label)),
            child: items.isEmpty
                ? Text('Nothing here.', style: TextStyle(color: NextUpColors.muted))
                : DeadlineSection(title: title, color: color, items: items, now: now, onFinish: _finish, showDate: showDate, limit: limit, bare: true, onEdit: widget.deadlines is DeadlineEditor ? _edit : null),
          ),
        );
    return [
      BoardItem(id: 'next', name: 'Next deadline', span: 4, child: _board(now)),
      BoardItem(id: 'calendar', name: 'Now and next', span: 4, child: CalendarPanel(events: _events, now: now, error: _calendarError, onSignIn: _calendarError != null && _needsSignIn ? _signIn : null)),
      const BoardItem(id: 'timer', name: 'Focus timer', span: 4, child: FocusTimer()),
      BoardItem(id: 'week', name: 'Next 7 days', span: 12, child: WeekStrip(deadlines: [...all], events: [...?_events], now: now)),
      if (_deadlines != null) ...[
        if (g.overdue.isNotEmpty || _editing) list('overdue', 'Overdue', NextUpColors.deadline, g.overdue, hint: 'Oldest first', showDate: true),
        if (g.today(now).any((d) => d != next) || _editing) list('today', 'Today', NextUpColors.accent, g.today(now).where((d) => d != next).toList()),
        if (g.thisWeek(now).isNotEmpty || _editing) list('thisweek', 'This week', NextUpColors.accent, g.thisWeek(now), showDate: true),
        if (g.later(now).isNotEmpty || _editing) list('later', 'Later', NextUpColors.muted, g.later(now), showDate: true, limit: 10),
      ],
      ...widget.extras,
    ];
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.message, required this.onSignIn, required this.onRetry});
  final String message;
  final VoidCallback? onSignIn;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: NextUpColors.panel, borderRadius: BorderRadius.circular(14), border: Border.all(color: NextUpColors.line)),
      child: Row(children: [
        Expanded(child: Text(message)),
        const SizedBox(width: 12),
        if (onSignIn != null) FilledButton(onPressed: onSignIn, child: const Text('Sign in with Google')) else OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
      ]),
    );
  }
}
