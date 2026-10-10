// Ask Claude: a small chat that sees your deadlines and calendar, and can tick tasks off or start the timer.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:next_up_core/ask_claude.dart';
import 'package:next_up_core/calendar.dart';
import 'package:next_up_core/deadline.dart';
import 'package:next_up_core/deadline_source.dart';
import 'package:next_up_core/theme.dart';
import 'package:url_launcher/url_launcher.dart';

import '../motion.dart';
import 'focus_controller.dart';
import 'panel.dart';

/// What Claude is shown about today: the rest of the calendar, the next deadlines (ids in brackets so it can
/// complete one), and the timer. The same facts the current site sends.
String askSnapshot({required DateTime now, required List<Deadline> deadlines, required List<CalendarEvent> events, required FocusController focus}) {
  String t(DateTime d) => DateFormat('h:mm a').format(d);
  String day(DateTime d) => DateFormat('EEE, MMM d').format(d);
  String left(Duration d) {
    final m = d.inMinutes.abs();
    final s = m >= 1440 ? '${m ~/ 1440}d ${m % 1440 ~/ 60}h' : (m >= 60 ? '${m ~/ 60}h ${m % 60}m' : '${m}m');
    return d.isNegative ? '$s late' : s;
  }

  final today = DateTime(now.year, now.month, now.day);
  final evs = events.where((e) => !e.allDay && e.end.isAfter(now) && e.start.isBefore(today.add(const Duration(days: 1)))).take(10).map((e) => '- ${t(e.start)}-${t(e.end)} ${e.title}').join('\n');
  final sorted = [...deadlines]..sort((a, b) => a.due.compareTo(b.due));
  final ts = sorted.take(20).map((d) => '- [${d.id}] ${d.title} | list: ${d.list} | personal deadline ${day(d.due)}${d.allDay ? '' : ' ${t(d.due)}'} (${left(d.due.difference(now))}${d.isLate(now) ? '' : ' from now'}) | priority ${d.priority}').join('\n');
  final timer = focus.running ? '${focusLabels[focus.mode]}, ${focus.left.inMinutes}m left' : 'not running';
  return 'Current time: $now\n\nCalendar, rest of today:\n${evs.isEmpty ? '(none loaded)' : evs}\n\nOpen TickTick tasks (overdue and next 7 days), soonest first:\n${ts.isEmpty ? '(none loaded)' : ts}\n\nFocus timer: $timer';
}

const _quick = ['What should I do right now?', 'Break my most urgent task into a 2-minute first step', "I'm procrastinating. Help me start.", 'Plan the rest of today'];

class _Msg {
  _Msg(this.kind, this.text);
  final String kind; // me, claude, note
  String text;
}

class AskPanel extends StatefulWidget {
  const AskPanel({super.key, required this.service, required this.snapshot, required this.tools});
  final AskService service;
  final String Function() snapshot;
  final AskTools tools;

  @override
  State<AskPanel> createState() => AskPanelState();
}

class AskPanelState extends State<AskPanel> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  final _msgs = <_Msg>[];
  final _history = <ChatTurn>[];
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String get _intro => switch (widget.service.mode) {
        AskMode.api => 'Ask anything about today. Claude can also mark tasks done or start your timer.',
        AskMode.relay => "Ask anything about today. Your laptop answers; if it's off, this opens Claude in a new tab instead.",
        AskMode.app => 'Ask anything about today. It opens Claude with your tasks and calendar filled in.',
      };

  void _scrollDown() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: motionFast, curve: motionCurve);
      });

  /// Sends [raw] as if typed (the dashboard uses this for the "2-minute first step" button).
  Future<void> send(String raw) => _send(raw);

  Future<void> _send(String raw) async {
    final q = raw.trim();
    if (q.isEmpty || _busy) return;
    _text.clear();
    final bubble = _Msg('claude', 'Thinking…');
    setState(() {
      _busy = true;
      _msgs.addAll([_Msg('me', q), bubble]);
    });
    _scrollDown();
    try {
      final r = await widget.service.ask(q, List.of(_history.length > 11 ? _history.sublist(_history.length - 11) : _history), widget.snapshot(), widget.tools);
      if (!mounted) return;
      setState(() {
        _msgs.remove(bubble);
        for (final n in r.notes) {
          _msgs.add(_Msg('note', n));
        }
        if (r.text.isNotEmpty) _msgs.add(_Msg('claude', r.text));
        _history.add(ChatTurn('user', q));
        if (r.text.isNotEmpty) _history.add(ChatTurn('assistant', r.text));
      });
      if (r.openUrl != null) {
        await Clipboard.setData(ClipboardData(text: Uri.decodeQueryComponent(Uri.parse(r.openUrl!).query.substring(2))));
        await launchUrl(Uri.parse(r.openUrl!), webOnlyWindowName: '_blank');
        if (mounted) setState(() => _msgs.add(_Msg('note', "Opened in Claude. If the message box there is empty, paste: it's on your clipboard.")));
      }
    } on SourceException catch (e) {
      if (mounted) setState(() => _msgs..remove(bubble)..add(_Msg('note', e.message)));
    } catch (_) {
      if (mounted) setState(() => _msgs..remove(bubble)..add(_Msg('note', 'Claude could not answer. Try again.')));
    } finally {
      if (mounted) setState(() => _busy = false);
      _scrollDown();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Panel(
      title: 'Ask Claude',
      trailing: Text('sees your tasks + calendar', style: TextStyle(color: NextUpColors.muted, fontSize: NextUpType.label)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final q in _quick) ActionChip(label: Text(q, style: const TextStyle(fontSize: NextUpType.caption)), onPressed: _busy ? null : () => _send(q)),
        ]),
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 360),
          child: ListView(
            controller: _scroll,
            shrinkWrap: true,
            children: [
              _Bubble(kind: 'note', text: _intro),
              for (final m in _msgs) _Bubble(kind: m.kind, text: m.text),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: TextField(
              controller: _text,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: _send,
              decoration: const InputDecoration(hintText: 'Type a question…', isDense: true),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(onPressed: _busy ? null : () => _send(_text.text), child: Text(widget.service.mode == AskMode.app ? 'Ask' : 'Send')),
        ]),
      ]),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.kind, required this.text});
  final String kind, text;

  @override
  Widget build(BuildContext context) {
    final me = kind == 'me', note = kind == 'note';
    return Align(
      alignment: me ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: const BoxConstraints(maxWidth: 520),
        decoration: BoxDecoration(color: me ? NextUpColors.accent.withValues(alpha: .3) : (note ? Colors.transparent : NextUpColors.raised), borderRadius: BorderRadius.circular(12)),
        child: SelectableText(text, style: TextStyle(fontSize: note ? NextUpType.caption : NextUpType.body, color: note ? NextUpColors.muted : Colors.white)),
      ),
    );
  }
}
