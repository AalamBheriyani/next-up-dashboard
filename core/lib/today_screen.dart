// Today: the next deadline as a big countdown, then what is overdue, due today and coming up.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'deadline.dart';
import 'deadline_source.dart';
import 'theme.dart';
import 'flap_countdown.dart';
import 'urgency.dart';

class TodayScreen extends StatefulWidget {
  const TodayScreen({
    super.key,
    required this.source,
    required this.signedIn,
    required this.onSignIn,
    this.now,
    this.onEdit,
    this.heading,
  });

  /// A page title over the date (the website's Deadlines page); the app shows only the date.
  final String? heading;
  final void Function(Deadline)? onEdit; // when set, each row gets an edit button
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
      if (!await finishWithUndo(messenger, widget.source, d) && mounted) setState(() => _items = [...?_items, d]);
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
        toolbarHeight: widget.heading == null ? null : 72,
        title: widget.heading == null
            ? Text(DateFormat('EEEE, MMM d').format(now), style: TextStyle(fontSize: NextUpType.body, color: NextUpColors.muted))
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.heading!, style: const TextStyle(fontSize: NextUpType.heading, fontWeight: FontWeight.w800)),
                Text(DateFormat('EEEE, MMM d').format(now), style: TextStyle(fontSize: NextUpType.body, color: NextUpColors.muted)),
              ]),
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
      DeadlineSection(title: 'Overdue', hint: 'Oldest first', color: NextUpColors.deadline, items: g.overdue, now: now, onFinish: _finish, showDate: true, onEdit: widget.onEdit),
      DeadlineSection(title: 'Today', color: NextUpColors.accent, items: g.today(now).where((d) => d != next).toList(), now: now, onFinish: _finish, onEdit: widget.onEdit),
      DeadlineSection(title: 'This week', color: NextUpColors.accent, items: g.thisWeek(now), now: now, onFinish: _finish, showDate: true, onEdit: widget.onEdit),
      DeadlineSection(title: 'Later', color: NextUpColors.muted, items: g.later(now), now: now, onFinish: _finish, showDate: true, limit: 8, onEdit: widget.onEdit),
    ];
  }
}

class NextBoard extends StatelessWidget {
  const NextBoard({super.key, required this.deadline, this.now, this.onStart});
  final Deadline deadline;
  final DateTime Function()? now;
  /// When set, a Start button begins work on this deadline (the site starts a focus session on it).
  final VoidCallback? onStart;

  @override
  Widget build(BuildContext context) {
    final at = (now ?? DateTime.now)();
    final u = urgencyOf(deadline, at);
    final hot = u == Urgency.critical || u == Urgency.soon;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: hot ? urgencyColor(u).withValues(alpha: .08) : NextUpColors.panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: hot ? urgencyColor(u) : NextUpColors.line, width: hot ? 1.5 : 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('NEXT DEADLINE', style: TextStyle(color: NextUpColors.muted, fontSize: NextUpType.label, fontWeight: FontWeight.w700, letterSpacing: 1.4)),
        const SizedBox(height: 10),
        Text(deadline.title, style: const TextStyle(fontSize: NextUpType.heading, fontWeight: FontWeight.w800, height: 1.1)),
        if (deadline.list.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(deadline.list, style: TextStyle(color: NextUpColors.muted))),
        const SizedBox(height: 16),
        FlapCountdown(target: deadline.due, now: now),
        const SizedBox(height: 12),
        Text(hot ? urgencyLine(deadline, at) : _dueText(deadline), style: TextStyle(color: hot ? urgencyColor(u) : NextUpColors.muted, fontSize: NextUpType.body, fontWeight: hot ? FontWeight.w700 : FontWeight.w400)),
        if (onStart != null) Padding(padding: const EdgeInsets.only(top: 14), child: FilledButton.icon(onPressed: onStart, icon: const Icon(Icons.play_arrow_rounded), label: const Text('Start 25 min on this'))),
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
    this.onEdit,
    this.showList = true,
  });
  final bool bare; // the caller's panel already shows the title
  final bool showList; // off when every row is from the same list (the box is that list)
  final void Function(Deadline)? onEdit; // when set, each row gets an edit button
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
          Text('${items.length}', style: TextStyle(color: NextUpColors.muted, fontSize: NextUpType.caption)),
          if (hint != null) ...[const Spacer(), Text(hint!, style: TextStyle(color: NextUpColors.muted, fontSize: NextUpType.caption))],
        ]),
        if (!bare) const SizedBox(height: 6),
        for (final d in shown) _Row(d: d, now: now, onFinish: onFinish, onEdit: onEdit, showDate: showDate, showList: showList),
        if (shown.length < items.length)
          Padding(padding: const EdgeInsets.only(top: 6), child: Text('+ ${items.length - shown.length} more', style: TextStyle(color: NextUpColors.muted, fontSize: NextUpType.caption))),
      ]),
    );
  }
}

class _Row extends StatefulWidget {
  const _Row({required this.d, required this.now, required this.onFinish, required this.showDate, this.onEdit, this.showList = true});
  final bool showList;
  final Deadline d;
  final DateTime now;
  final void Function(Deadline) onFinish;
  final void Function(Deadline)? onEdit;
  final bool showDate;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  bool _open = false; // the task's notes, shown on a tap like the old site

  @override
  Widget build(BuildContext context) {
    final d = widget.d, now = widget.now, onFinish = widget.onFinish, onEdit = widget.onEdit;
    final late = d.isLate(now);
    final real = d.realDeadline;
    final meta = [if (widget.showList && d.list.isNotEmpty) d.list, if (real != null) 'Real: $real', if (d.priority >= 5) 'High priority'].join(' · ');
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
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: d.notes.isEmpty ? null : () => setState(() => _open = !_open),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(child: Text(d.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: NextUpType.body, fontWeight: FontWeight.w600))),
                  if (d.notes.isNotEmpty) Padding(padding: const EdgeInsets.only(left: 6), child: Icon(_open ? Icons.expand_less_rounded : Icons.notes_rounded, size: 14, color: NextUpColors.muted)),
                ]),
                if (meta.isNotEmpty) Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: NextUpColors.muted, fontSize: NextUpType.caption)),
                AnimatedSize(
                  duration: const Duration(milliseconds: 180),
                  alignment: Alignment.topLeft,
                  child: _open ? Padding(padding: const EdgeInsets.only(top: 6, bottom: 4), child: SelectableText(d.notes, style: TextStyle(color: NextUpColors.muted, fontSize: NextUpType.caption))) : const SizedBox(width: double.infinity),
                ),
              ]),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _relative(d, now, widget.showDate),
            style: TextStyle(fontFamily: 'monospace', fontFeatures: monoFeatures, fontSize: NextUpType.caption, fontWeight: FontWeight.w700, color: late ? NextUpColors.deadline : (urgencyOf(d, now) == Urgency.week || urgencyOf(d, now) == Urgency.later ? NextUpColors.muted : urgencyColor(urgencyOf(d, now)))),
          ),
          if (onEdit != null) IconButton(tooltip: 'Edit ${d.title}', icon: const Icon(Icons.edit_outlined, size: 18), color: NextUpColors.muted, visualDensity: VisualDensity.compact, onPressed: () => onEdit(d)),
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
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(top: 80),
        child: Center(child: Text('Nothing due. Enjoy the free time.', style: TextStyle(color: NextUpColors.muted))),
      );
}

/// Shows "Done" with an Undo for a few seconds and only then finishes [d] in TickTick, so a slip of the
/// finger costs nothing. Returns false when Undo was tapped. Throws [SourceException] if finishing fails.
Future<bool> finishWithUndo(ScaffoldMessengerState messenger, DeadlineSource source, Deadline d) async {
  messenger.hideCurrentSnackBar();
  final bar = messenger.showSnackBar(SnackBar(
    content: Text('Done: ${d.title}'),
    duration: const Duration(seconds: 4),
    persist: false, // with an action it would otherwise stay up and the task never finish
    action: SnackBarAction(label: 'Undo', onPressed: () {}),
  ));
  if (await bar.closed == SnackBarClosedReason.action) return false;
  await source.complete(d);
  return true;
}
