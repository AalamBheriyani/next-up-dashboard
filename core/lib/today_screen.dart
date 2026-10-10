// Today: the next deadline as a big countdown, then what is overdue, due today and coming up.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'deadline.dart';
import 'deadline_source.dart';
import 'theme.dart';
import 'flap_countdown.dart';

class TodayScreen extends StatefulWidget {
  const TodayScreen({
    super.key,
    required this.source,
    required this.signedIn,
    required this.onSignIn,
    this.now,
  });

  final DeadlineSource source;
  final bool Function() signedIn;
  final Future<void> Function() onSignIn;
  final DateTime Function()? now; // for tests

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  List<Deadline>? _items;
  SourceException? _error;
  bool _loading = false;

  DateTime _now() => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (!widget.signedIn()) {
      setState(() => _error = SourceException('Sign in to see your deadlines.', signedOut: true));
      return;
    }
    setState(() => _loading = true);
    try {
      final items = await widget.source.load();
      if (!mounted) return;
      setState(() {
        _items = items;
        _error = null;
      });
    } on SourceException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signIn() async {
    try {
      await widget.onSignIn();
    } catch (_) {
      if (mounted) setState(() => _error = SourceException('Sign-in was cancelled or failed. Try again.', signedOut: true));
      return;
    }
    await _refresh();
  }

  Future<void> _finish(Deadline d) async {
    HapticFeedback.lightImpact();
    final before = _items;
    setState(() => _items = before?.where((x) => x.id != d.id).toList());
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.source.complete(d);
      messenger.showSnackBar(SnackBar(content: Text('Done: ${d.title}')));
    } on SourceException catch (e) {
      if (mounted) setState(() => _items = before);
      messenger.showSnackBar(SnackBar(content: Text("Couldn't finish it. ${e.message}")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = _now();
    final items = _items;
    return Scaffold(
      appBar: AppBar(
        title: Text(DateFormat('EEEE, MMM d').format(now), style: const TextStyle(fontSize: NextUpType.body, color: NextUpColors.muted)),
        actions: [
          if (_loading)
            const Padding(padding: EdgeInsets.only(right: 16), child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            if (_error != null) _Notice(error: _error!, onSignIn: _signIn, onRetry: _refresh),
            if (items == null && _error == null) const _Loading(),
            if (items != null) ..._sections(items, now),
          ],
        ),
      ),
    );
  }

  List<Widget> _sections(List<Deadline> items, DateTime now) {
    if (items.isEmpty) {
      return [const _Empty()];
    }
    final g = DeadlineGroups(items, now);
    final next = g.next;
    return [
      if (next != null) Padding(padding: const EdgeInsets.only(top: 8), child: NextBoard(deadline: next, now: widget.now)),
      const SizedBox(height: 8),
      DeadlineSection(title: 'Overdue', hint: 'Oldest first', color: NextUpColors.deadline, items: g.overdue, now: now, onFinish: _finish, showDate: true),
      DeadlineSection(title: 'Today', color: NextUpColors.accent, items: g.today(now).where((d) => d != next).toList(), now: now, onFinish: _finish),
      DeadlineSection(title: 'This week', color: NextUpColors.accent, items: g.thisWeek(now), now: now, onFinish: _finish, showDate: true),
      DeadlineSection(title: 'Later', color: NextUpColors.muted, items: g.later(now), now: now, onFinish: _finish, showDate: true, limit: 8),
    ];
  }
}

class NextBoard extends StatelessWidget {
  const NextBoard({super.key, required this.deadline, this.now});
  final Deadline deadline;
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: NextUpColors.panel, borderRadius: BorderRadius.circular(18), border: Border.all(color: NextUpColors.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('NEXT DEADLINE', style: TextStyle(color: NextUpColors.muted, fontSize: NextUpType.label, fontWeight: FontWeight.w700, letterSpacing: 1.4)),
        const SizedBox(height: 10),
        Text(deadline.title, style: const TextStyle(fontSize: NextUpType.heading, fontWeight: FontWeight.w800, height: 1.1)),
        if (deadline.list.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(deadline.list, style: const TextStyle(color: NextUpColors.muted))),
        const SizedBox(height: 16),
        FlapCountdown(target: deadline.due, now: now),
        const SizedBox(height: 12),
        Text(_dueText(deadline), style: const TextStyle(color: NextUpColors.muted, fontSize: NextUpType.body)),
      ]),
    );
  }
}

String _dueText(Deadline d) => d.allDay ? 'Due ${DateFormat('EEE, MMM d').format(d.due)}' : 'Due ${DateFormat('EEE, MMM d, h:mm a').format(d.due)}';

class DeadlineSection extends StatelessWidget {
  const DeadlineSection({
    super.key,
    required this.title,
    required this.color,
    required this.items,
    required this.now,
    required this.onFinish,
    this.hint,
    this.showDate = false,
    this.limit,
    this.bare = false,
  });
  final bool bare; // the caller's panel already shows the title
  final String title;
  final String? hint;
  final Color color;
  final List<Deadline> items;
  final DateTime now;
  final void Function(Deadline) onFinish;
  final bool showDate;
  final int? limit;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final shown = limit == null ? items : items.take(limit!).toList();
    return Padding(
      padding: EdgeInsets.only(top: bare ? 0 : 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (!bare) Row(children: [
          Text(title.toUpperCase(), style: TextStyle(color: color, fontSize: NextUpType.caption, fontWeight: FontWeight.w800, letterSpacing: 1.4)),
          const SizedBox(width: 8),
          Text('${items.length}', style: const TextStyle(color: NextUpColors.muted, fontSize: NextUpType.caption)),
          if (hint != null) ...[const Spacer(), Text(hint!, style: const TextStyle(color: NextUpColors.muted, fontSize: NextUpType.caption))],
        ]),
        if (!bare) const SizedBox(height: 6),
        for (final d in shown) _Row(d: d, now: now, onFinish: onFinish, showDate: showDate),
        if (shown.length < items.length)
          Padding(padding: const EdgeInsets.only(top: 6), child: Text('+ ${items.length - shown.length} more', style: const TextStyle(color: NextUpColors.muted, fontSize: NextUpType.caption))),
      ]),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.d, required this.now, required this.onFinish, required this.showDate});
  final Deadline d;
  final DateTime now;
  final void Function(Deadline) onFinish;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final late = d.isLate(now);
    return Dismissible(
      key: ValueKey(d.id),
      direction: DismissDirection.startToEnd,
      onDismissed: (_) => onFinish(d),
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 16),
        margin: const EdgeInsets.only(top: 8),
        decoration: BoxDecoration(color: NextUpColors.ok.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(12)),
        child: const Icon(Icons.check_rounded, color: NextUpColors.ok),
      ),
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.fromLTRB(4, 4, 14, 4),
        decoration: BoxDecoration(color: NextUpColors.panel, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          IconButton(
            tooltip: 'Finish ${d.title}',
            icon: const Icon(Icons.radio_button_unchecked_rounded),
            color: d.priority >= 5 ? NextUpColors.soon : NextUpColors.muted,
            onPressed: () => onFinish(d),
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(d.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: NextUpType.body, fontWeight: FontWeight.w600)),
              if (d.list.isNotEmpty) Text(d.list, style: const TextStyle(color: NextUpColors.muted, fontSize: NextUpType.caption)),
            ]),
          ),
          const SizedBox(width: 8),
          Text(
            _relative(d, now, showDate),
            style: TextStyle(fontFamily: 'monospace', fontFeatures: monoFeatures, fontSize: NextUpType.caption, fontWeight: FontWeight.w700, color: late ? NextUpColors.deadline : NextUpColors.muted),
          ),
        ]),
      ),
    );
  }
}

/// "3d late", "today 5:00 PM", "Wed 14".
String _relative(Deadline d, DateTime now, bool showDate) {
  final today = DateTime(now.year, now.month, now.day);
  final dueDay = DateTime(d.due.year, d.due.month, d.due.day);
  final days = dueDay.difference(today).inDays;
  if (d.isLate(now)) return days == 0 ? 'late today' : '${-days}d late';
  if (days == 0) return d.allDay ? 'today' : DateFormat('h:mm a').format(d.due);
  if (days == 1) return 'tomorrow';
  return showDate ? DateFormat('EEE d').format(d.due) : 'in ${days}d';
}

class _Notice extends StatelessWidget {
  const _Notice({required this.error, required this.onSignIn, required this.onRetry});
  final SourceException error;
  final VoidCallback onSignIn;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: NextUpColors.panel, borderRadius: BorderRadius.circular(14), border: Border.all(color: NextUpColors.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(error.message),
        const SizedBox(height: 12),
        if (error.signedOut)
          FilledButton(onPressed: onSignIn, child: const Text('Sign in with Google'))
        else
          OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
      ]),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) => const Padding(padding: EdgeInsets.only(top: 80), child: Center(child: CircularProgressIndicator()));
}

class _Empty extends StatelessWidget {
  const _Empty();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.only(top: 80),
        child: Center(child: Text('Nothing due. Enjoy the free time.', style: TextStyle(color: NextUpColors.muted))),
      );
}
