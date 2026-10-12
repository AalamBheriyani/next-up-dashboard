// The dashboard: clock and day progress, next deadline, now and next from the calendar, a focus timer,
// the week ahead, and every deadline grouped by urgency. Each panel loads on its own, so a calendar
// problem never hides the deadlines.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:next_up_core/ask_claude.dart';
import 'package:next_up_core/board_layout.dart';
import 'package:next_up_core/calendar.dart';
import 'package:next_up_core/deadline.dart';
import 'package:next_up_core/deadline_source.dart';
import 'package:next_up_core/hours.dart' show HoursSummary;
import 'package:next_up_core/theme.dart';
import 'package:next_up_core/worker_api.dart' show defaultWakeMinutes, defaultWindDownMinutes;
import 'package:next_up_core/today_screen.dart';

import '../board/widget_board.dart';
import 'calendar_panel.dart';
import 'ask_panel.dart';
import 'day_column.dart';
import 'deadline_box.dart';
import 'deadline_editor.dart';
import 'do_now.dart';
import 'focus_controller.dart';
import 'clock_header.dart';
import 'focus_timer.dart';
import 'panel.dart';
import 'week_strip.dart';
import '../motion.dart';
import '../refresh.dart';

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
    this.wakeMinutes = defaultWakeMinutes,
    this.windDownMinutes = defaultWindDownMinutes,
    this.place = '',
    this.sleepMinutes,
    this.onLayout,
    this.focus,
    this.ask,
    this.hours,
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
  final int wakeMinutes, windDownMinutes; // the waking day for the header's bars
  final String place;
  final int? sleepMinutes;
  final ValueChanged<BoardLayout>? onLayout;
  /// The focus timer (owned by the shell so it keeps running between pages) and Ask Claude, when available.
  final FocusController? focus;
  final AskService? ask;
  /// This week's adherence from the Time Tracker sheet, for Ask Claude (when a sheet is set).
  final Future<HoursSummary> Function()? hours;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with RefreshOnReturn {
  @override
  Future<void> refreshData() => _load();

  List<Deadline>? _deadlines;
  List<CalendarEvent>? _events;
  HoursSummary? _hours;
  String? _deadlineError, _calendarError;
  bool _needsSignIn = false;
  bool _notConnected = false;
  bool _loading = false;
  bool _editing = false;
  late BoardLayout _layout = widget.layout;
  late final FocusController _ownFocus = FocusController();
  FocusController get _focus => widget.focus ?? _ownFocus;
  Timer? _refresh;
  Timer? _clock;

  @override
  void didUpdateWidget(DashboardScreen old) {
    super.didUpdateWidget(old);
    // A layout arriving from the account (after sign-in) replaces ours unless we're mid-edit.
    if (!_editing && old.layout != widget.layout) _layout = widget.layout;
  }

  List<String> _ids = const [];

  /// [page] is this page's arrangement; it is merged into the account layout so other pages keep theirs.
  void _setLayout(BoardLayout page) {
    final full = _layout.withPage(page, _ids);
    setState(() => _layout = full);
    widget.onLayout?.call(full);
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

  // The old Deadlines widget's "Search deadlines…" and list chips, opened from the header.
  bool _searching = false;
  String _query = '';
  final Set<String> _lists = {};

  Widget _searchBar() {
    final lists = {for (final d in _deadlines ?? const <Deadline>[]) if (d.list.isNotEmpty) d.list}.toList()..sort();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SizedBox(
          width: 260,
          child: TextField(
            autofocus: true,
            onChanged: (v) => setState(() => _query = v),
            decoration: const InputDecoration(isDense: true, prefixIcon: Icon(Icons.search_rounded, size: 18), hintText: 'Search deadlines', border: OutlineInputBorder()),
          ),
        ),
        if (lists.length > 1)
          for (final l in lists)
            FilterChip(
              avatar: () {
                final c = (_deadlines ?? const <Deadline>[]).firstWhere((d) => d.list == l).color;
                return c == 0 ? null : Container(width: 10, height: 10, decoration: BoxDecoration(color: Color(c), shape: BoxShape.circle));
              }(),
              label: Text(l),
              selected: _lists.contains(l),
              onSelected: (on) => setState(() => on ? _lists.add(l) : _lists.remove(l)),
            ),
      ]),
    );
  }

  DateTime? _updatedAt; // when the last load finished, for the "updated" stamp

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
      if (widget.hours != null) _loadHours(),
    ]);
    if (mounted) {
      setState(() {
        _loading = false;
        if (_deadlineError == null || _calendarError == null) _updatedAt = _now();
      });
    }
  }

  // Only Ask Claude reads this, so a failure just leaves it out.
  Future<void> _loadHours() async {
    try {
      _hours = await widget.hours!();
    } catch (_) {}
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
          _notConnected = e.notConnected;
        });
      }
    } catch (_) {
      if (mounted) setState(() => fail(fallback));
    }
  }

  /// Sends the person to TickTick to connect; the Worker brings them back to the site afterwards.
  Future<void> _connect() async {
    final c = widget.deadlines;
    if (c is! TickTickConnector) return;
    try {
      await launchUrl(Uri.parse(await (c as TickTickConnector).connectUrl(back: 'beta')), webOnlyWindowName: '_self');
    } on SourceException catch (e) {
      if (mounted) setState(() => _deadlineError = e.message);
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
    if (await showDeadlineEditor(context, editor as DeadlineEditor, d: d, now: widget.now, calendar: widget.calendar is CalendarWriter ? widget.calendar as CalendarWriter : null)) await _load();
  }

  Future<void> _finish(Deadline d) async {
    final before = _deadlines;
    setState(() => _deadlines = before?.where((x) => x.id != d.id).toList());
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (!await finishWithUndo(messenger, widget.deadlines, d) && mounted) setState(() => _deadlines = [...?_deadlines, d]);
    } on SourceException catch (e) {
      if (mounted) setState(() => _deadlines = before);
      messenger.showSnackBar(SnackBar(content: Text("Couldn't finish it. ${e.message}")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = _now();
    final items = _items(now);
    _ids = [for (final i in items) i.id];
    final phone = MediaQuery.sizeOf(context).width < 720;
    return Scaffold(
      // On a phone Ask Claude is far down the page; this button goes straight to it, as on the old site.
      // It shrinks to an icon once the page scrolls and steps aside while the chat itself is on screen.
      floatingActionButton: phone && widget.ask != null && !_layout.isHidden('ask') && !_editing
          ? AnimatedScale(
              scale: _askInView ? 0 : 1,
              duration: motionFast,
              child: _scrolled
                  ? FloatingActionButton(tooltip: 'Ask Claude', onPressed: _toAsk, child: const Icon(Icons.auto_awesome_rounded))
                  : FloatingActionButton.extended(onPressed: _toAsk, icon: const Icon(Icons.auto_awesome_rounded), label: const Text('Ask Claude')),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _load,
        child: NotificationListener<ScrollUpdateNotification>(
        onNotification: (n) {
          if (n.depth == 0) _onScroll(n.metrics.pixels);
          return false;
        },
        child: LayoutBuilder(builder: (context, box) {
          final w = box.maxWidth;
          return ListView(
            padding: EdgeInsets.symmetric(horizontal: w >= 720 ? 28 : 16, vertical: 24),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              Builder(builder: (context) {
                final clock = ClockHeader(now: widget.now, events: _events, wakeMinutes: widget.wakeMinutes, windDownMinutes: widget.windDownMinutes, place: widget.place, sleepMinutes: widget.sleepMinutes);
                final tools = Row(mainAxisSize: MainAxisSize.min, children: [
                  if (!_loading) UpdatedStamp(at: _updatedAt),
                  if (_loading) const Padding(padding: EdgeInsets.all(8), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
                  IconButton(
                    tooltip: _searching ? 'Close search' : 'Search deadlines',
                    onPressed: () => setState(() {
                      _searching = !_searching;
                      _query = '';
                      _lists.clear();
                    }),
                    icon: Icon(_searching ? Icons.search_off_rounded : Icons.search_rounded),
                  ),
                  if (widget.deadlines is DeadlineEditor) IconButton(tooltip: 'Add a deadline', onPressed: () => _edit(null), icon: const Icon(Icons.add_rounded)),
                  IconButton(tooltip: _editing ? 'Done customising' : 'Customise panels', onPressed: () => setState(() => _editing = !_editing), icon: Icon(_editing ? Icons.check_rounded : Icons.dashboard_customize_outlined)),
                  IconButton(tooltip: 'Refresh', onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
                ]);
                // On a phone the buttons take their own line so the clock and date are never squeezed.
                if (w < 600) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Align(alignment: Alignment.centerRight, child: tools), clock]);
                return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: clock), tools]);
              }),
              const SizedBox(height: 20),
              AnimatedSize(duration: motionFast, alignment: Alignment.topLeft, child: _searching ? _searchBar() : const SizedBox(width: double.infinity)),
              if (_deadlineError != null && _deadlines == null) _Banner(message: _deadlineError!, onSignIn: _needsSignIn ? _signIn : null, onConnect: _notConnected && widget.deadlines is TickTickConnector ? _connect : null, onRetry: _load),
              if (!_editing && doNowTarget(_deadlines ?? const [], now) != null) ...[
                Builder(builder: (context) {
                  final t = doNowTarget(_deadlines ?? const [], now)!;
                  return DoNowStrip(deadline: t, now: now, onStart: () => _startOn(t), onFirstStep: widget.ask == null || _layout.isHidden('ask') ? null : () => _firstStep(t));
                }),
                const SizedBox(height: 16),
              ],
              if (_editing) ...[
                BoardBar(items: items, layout: _layout.resolved([for (final i in items) i.id]), onChanged: _setLayout, onReset: () => _setLayout(const BoardLayout()), onDone: () => setState(() => _editing = false)),
                const SizedBox(height: 16),
              ],
              WidgetBoard(items: items, layout: _layout, editing: _editing, onChanged: _setLayout, onEdit: () => setState(() => _editing = true)),
            ],
          );
        }),
        ),
      ),
    );
  }

  Widget _board(DateTime now, {VoidCallback? onStart}) {
    final items = _deadlines;
    if (items == null && _needsSignIn) {
      return Panel(title: 'Next deadline', child: Text('Sign in to see your next deadline.', style: TextStyle(color: NextUpColors.muted)));
    }
    if (items == null) {
      return const Panel(title: 'Next deadline', child: Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: CircularProgressIndicator(strokeWidth: 2))));
    }
    final next = DeadlineGroups(items, now).next;
    if (next == null) {
      return Panel(
        title: 'Next deadline',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Clear', style: TextStyle(fontSize: NextUpType.display, fontWeight: FontWeight.w800)),
          Text('Nothing due. Enjoy the free time.', style: TextStyle(color: NextUpColors.muted)),
        ]),
      );
    }
    return NextBoard(deadline: next, now: widget.now, onStart: onStart, overdue: DeadlineGroups(items, now).overdue.length);
  }

  late final AskTools _tools = _DashboardTools(this);
  final _askKey = GlobalKey<AskPanelState>();

  void _startOn(Deadline d) => _focus.startFocus(25, d.title);

  bool _scrolled = false, _askInView = false;

  // Measured after the frame, once the scrolled panels have moved.
  void _onScroll(double px) => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _measureAsk(px);
      });

  void _measureAsk(double px) {
    final box = _askKey.currentContext?.findRenderObject() as RenderBox?;
    var inView = false;
    if (box != null && box.attached) {
      final top = box.localToGlobal(Offset.zero).dy;
      inView = top < MediaQuery.sizeOf(context).height - 120 && top + box.size.height > 80;
    }
    final scrolled = px > 40;
    if (scrolled != _scrolled || inView != _askInView) {
      setState(() {
        _scrolled = scrolled;
        _askInView = inView;
      });
    }
  }

  Future<void> _toAsk() async {
    final c = _askKey.currentContext;
    if (c == null) return;
    await Scrollable.ensureVisible(c, duration: motionBase, curve: motionCurve, alignment: 0.1);
    _askKey.currentState?.focusInput();
  }

  void _firstStep(Deadline d) => _askKey.currentState?.send('Break "${d.title}" into a 2-minute first step');

  /// Every panel the dashboard can show; the board places them.
  List<BoardItem> _items(DateTime now) {
    final all = _deadlines ?? const <Deadline>[];
    final g = DeadlineGroups(all, now);
    final next = g.next;
    // The search bar narrows the four deadline lists only; the next deadline and the calendar stay whole.
    final q = _query.trim().toLowerCase();
    final f = !_searching || (q.isEmpty && _lists.isEmpty)
        ? g
        : DeadlineGroups([for (final d in all) if ((_lists.isEmpty || _lists.contains(d.list)) && (q.isEmpty || '${d.title} ${d.list} ${d.notes}'.toLowerCase().contains(q))) d], now);
    BoardItem list(String id, String title, Color color, List<Deadline> items, {String? hint, bool showDate = false}) => BoardItem(
          id: id,
          name: title,
          span: 6,
          child: Panel(
            title: title,
            accent: color,
            trailing: hint == null ? null : Text(hint, style: TextStyle(color: NextUpColors.muted, fontSize: NextUpType.label)),
            child: DeadlineBox(title: title, color: color, items: items, now: now, onFinish: _finish, showDate: showDate, onEdit: widget.deadlines is DeadlineEditor ? _edit : null,
                // On a phone the panels stack, so a short list needn't keep the shared height.
                height: MediaQuery.sizeOf(context).width < 600 ? (items.length * 64.0 + 8).clamp(64.0, deadlineBoxHeight) : deadlineBoxHeight),
          ),
        );
    return [
      BoardItem(id: 'next', name: 'Next deadline', span: 4, child: _board(now, onStart: () => next == null ? null : _startOn(next))),
      // "Use it on" suggests the oldest late task first, as Do this first does.
      BoardItem(id: 'calendar', name: 'Now and next', span: 4, child: CalendarPanel(events: _events, now: now, useOn: (g.overdue.isNotEmpty ? g.overdue.first : next)?.title, error: _calendarError ?? (_needsSignIn && _events == null ? 'Sign in to see today\'s calendar.' : null), onSignIn: _calendarError != null && _needsSignIn ? _signIn : null)),
      BoardItem(id: 'timer', name: 'Focus timer', span: 4, child: FocusTimer(controller: _focus)),
      if (widget.ask != null)
        BoardItem(
          id: 'ask',
          name: 'Ask Claude',
          span: 4,
          child: AskPanel(key: _askKey, service: widget.ask!, tools: _tools, snapshot: () => askSnapshot(now: _now(), deadlines: _deadlines ?? const [], events: _events ?? const [], focus: _focus, hours: _hours?.forAsk)),
        ),
      BoardItem(id: 'day', name: 'Today hour by hour', span: 8, child: DayColumn(events: _events, now: now)),
      BoardItem(id: 'week', name: 'Next 7 days', span: 12, child: WeekStrip(deadlines: [...all], events: [...?_events], now: now)),
      if (_deadlines != null) ...[
        if (f.overdue.isNotEmpty || _editing) list('overdue', 'Overdue', NextUpColors.deadline, f.overdue, hint: 'Oldest first', showDate: true),
        if (f.today(now).any((d) => d != next) || _editing) list('today', 'Today', NextUpColors.accent, f.today(now).where((d) => d != next).toList()),
        if (f.thisWeek(now).isNotEmpty || _editing) list('thisweek', 'This week', NextUpColors.accent, f.thisWeek(now), showDate: true),
        if (f.later(now).isNotEmpty || _editing) list('later', 'Later', NextUpColors.muted, f.later(now), showDate: true),
      ],
      ...widget.extras,
    ];
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.message, required this.onSignIn, required this.onRetry, this.onConnect});
  final String message;
  final VoidCallback? onSignIn, onConnect;
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
        if (onSignIn != null) FilledButton(onPressed: onSignIn, child: const Text('Sign in with Google')) else if (onConnect != null) FilledButton(onPressed: onConnect, child: const Text('Connect TickTick')) else OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
      ]),
    );
  }
}

/// What Ask Claude may do: finish a task from the loaded list, or start the focus timer.
class _DashboardTools implements AskTools {
  _DashboardTools(this.s);
  final _DashboardScreenState s;

  @override
  Future<String> completeTask(String id) async {
    final d = (s._deadlines ?? const <Deadline>[]).where((x) => x.id == id).firstOrNull;
    if (d == null) throw SourceException('No open task with that id.');
    await s._finish(d);
    return d.title;
  }

  @override
  int startTimer(int minutes, String label) => s._focus.startFocus(minutes, label);
}
