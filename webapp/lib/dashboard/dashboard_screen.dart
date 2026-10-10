// The dashboard: clock and day progress, next deadline, now and next from the calendar, a focus timer,
// the week ahead, and every deadline grouped by urgency. Each panel loads on its own, so a calendar
// problem never hides the deadlines.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:next_up_core/calendar.dart';
import 'package:next_up_core/deadline.dart';
import 'package:next_up_core/deadline_source.dart';
import 'package:next_up_core/theme.dart';
import 'package:next_up_core/today_screen.dart';

import 'calendar_panel.dart';
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
  });
  final DeadlineSource deadlines;
  final CalendarSource calendar;
  final bool Function() signedIn;
  final Future<void> Function() onSignIn;
  final DateTime Function()? now; // for tests

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List<Deadline>? _deadlines;
  List<CalendarEvent>? _events;
  String? _deadlineError, _calendarError;
  bool _needsSignIn = false;
  bool _loading = false;
  Timer? _refresh;
  Timer? _clock;

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
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: LayoutBuilder(builder: (context, box) {
          final w = box.maxWidth;
          final cols = w >= 1100 ? 3 : (w >= 720 ? 2 : 1);
          return ListView(
            padding: EdgeInsets.symmetric(horizontal: w >= 720 ? 28 : 16, vertical: 24),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: ClockHeader(now: widget.now)),
                if (_loading) const Padding(padding: EdgeInsets.all(8), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
                IconButton(tooltip: 'Refresh', onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
              ]),
              const SizedBox(height: 20),
              if (_deadlineError != null && _deadlines == null) _Banner(message: _deadlineError!, onSignIn: _needsSignIn ? _signIn : null, onRetry: _load),
              _Grid(cols: cols, gap: 16, children: [
                _board(now),
                CalendarPanel(events: _events, now: now, error: _calendarError, onSignIn: _calendarError != null && _needsSignIn ? _signIn : null),
                const FocusTimer(),
              ]),
              const SizedBox(height: 16),
              WeekStrip(deadlines: [...?_deadlines], events: [...?_events], now: now),
              const SizedBox(height: 16),
              ..._lists(now, cols),
            ],
          );
        }),
      ),
    );
  }

  Widget _board(DateTime now) {
    final items = _deadlines;
    if (items == null) {
      return const Panel(title: 'Next departure', child: Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: CircularProgressIndicator(strokeWidth: 2))));
    }
    final next = DeadlineGroups(items, now).next;
    if (next == null) return const Panel(title: 'Next departure', child: Text('Nothing due. Enjoy the free time.', style: TextStyle(color: NextUpColors.muted)));
    return NextBoard(deadline: next, now: widget.now);
  }

  List<Widget> _lists(DateTime now, int cols) {
    final items = _deadlines;
    if (items == null || items.isEmpty) return const [];
    final g = DeadlineGroups(items, now);
    final next = g.next;
    Widget section(String title, Color color, List<Deadline> list, {String? hint, bool showDate = false, int? limit}) => list.isEmpty
        ? const SizedBox.shrink()
        : Panel(
            title: title,
            accent: color,
            child: DeadlineSection(title: title, hint: hint, color: color, items: list, now: now, onFinish: _finish, showDate: showDate, limit: limit, bare: true),
          );
    return [
      _Grid(cols: cols == 3 ? 2 : cols, gap: 16, children: [
        section('Overdue', NextUpColors.deadline, g.overdue, hint: 'Oldest first', showDate: true),
        section('Today', NextUpColors.accent, g.today(now).where((d) => d != next).toList()),
        section('This week', NextUpColors.accent, g.thisWeek(now), showDate: true),
        section('Later', NextUpColors.muted, g.later(now), showDate: true, limit: 10),
      ]),
    ];
  }
}

/// Lays children out in equal columns and drops the empty ones.
class _Grid extends StatelessWidget {
  const _Grid({required this.cols, required this.gap, required this.children});
  final int cols;
  final double gap;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final shown = children.where((c) => c is! SizedBox).toList();
    return LayoutBuilder(builder: (context, box) {
      final w = (box.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(spacing: gap, runSpacing: gap, children: [for (final c in shown) SizedBox(width: w, child: c)]);
    });
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
