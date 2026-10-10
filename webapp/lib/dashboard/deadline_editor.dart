// Edit a deadline beyond marking it done: rename it, move the day, change its priority, or delete it.
// These are the changes TickTick's API allows; the same sheet also adds a new deadline.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:next_up_core/deadline.dart';
import 'package:next_up_core/deadline_source.dart';
import 'package:next_up_core/theme.dart';

import '../motion.dart';

const _priorities = [(0, 'None'), (1, 'Low'), (3, 'Medium'), (5, 'High')];

/// Shows the editor for [d], or the "add" form when [d] is null. Returns true when something changed.
Future<bool> showDeadlineEditor(BuildContext context, DeadlineEditor editor, {Deadline? d, DateTime Function()? now}) async {
  final changed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: NextUpColors.panel,
    showDragHandle: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: _EditorSheet(editor: editor, d: d, now: now ?? DateTime.now),
    ),
  );
  return changed ?? false;
}

class _EditorSheet extends StatefulWidget {
  const _EditorSheet({required this.editor, required this.d, required this.now});
  final DeadlineEditor editor;
  final Deadline? d;
  final DateTime Function() now;

  @override
  State<_EditorSheet> createState() => _EditorSheetState();
}

class _EditorSheetState extends State<_EditorSheet> {
  late final _title = TextEditingController(text: widget.d?.title ?? '');
  late DateTime? _day = widget.d == null ? null : DateTime(widget.d!.due.year, widget.d!.due.month, widget.d!.due.day);
  late int _priority = widget.d?.priority ?? 0;
  bool _busy = false, _confirmDelete = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  DateTime get _today => DateTime(widget.now().year, widget.now().month, widget.now().day);

  Future<void> _run(Future<void> Function() job) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await job();
      if (mounted) Navigator.pop(context, true);
    } on SourceException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _save() {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Give it a name first.');
      return;
    }
    final d = widget.d;
    if (d == null) {
      _run(() => widget.editor.create(title: title, day: _day, priority: _priority));
      return;
    }
    final sameDay = _day == null || (_day!.year == d.due.year && _day!.month == d.due.month && _day!.day == d.due.day);
    _run(() => widget.editor.update(d,
        title: title == d.title ? null : title, day: sameDay ? null : _day, priority: _priority == d.priority ? null : _priority));
  }

  Future<void> _pick() async {
    final picked = await showDatePicker(context: context, initialDate: _day ?? _today, firstDate: DateTime(2020), lastDate: DateTime(2100));
    if (picked != null) setState(() => _day = picked);
  }

  @override
  Widget build(BuildContext context) {
    final adding = widget.d == null;
    Widget chip(String label, DateTime day) => ChoiceChip(label: Text(label), selected: _day == day, onSelected: (_) => setState(() => _day = day));
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(adding ? 'Add a deadline' : 'Edit deadline', style: const TextStyle(fontSize: NextUpType.title, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            TextField(controller: _title, autofocus: adding, decoration: const InputDecoration(labelText: 'Name'), onSubmitted: (_) => _save()),
            const SizedBox(height: 16),
            Text(_day == null ? 'No due date' : 'Due ${DateFormat('EEE, MMM d').format(_day!)}', style: TextStyle(color: NextUpColors.muted, fontSize: NextUpType.body)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              chip('Today', _today),
              chip('Tomorrow', _today.add(const Duration(days: 1))),
              chip('Next week', _today.add(const Duration(days: 7))),
              ActionChip(avatar: const Icon(Icons.calendar_month_outlined, size: 16), label: const Text('Pick a date'), onPressed: _pick),
            ]),
            const SizedBox(height: 16),
            Text('Priority', style: TextStyle(color: NextUpColors.muted, fontSize: NextUpType.body)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              for (final p in _priorities) ChoiceChip(label: Text(p.$2), selected: _priority == p.$1, onSelected: (_) => setState(() => _priority = p.$1)),
            ]),
            AnimatedSize(
              duration: motionFast,
              child: _error == null ? const SizedBox(width: double.infinity) : Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(color: NextUpColors.deadline))),
            ),
            const SizedBox(height: 20),
            Row(children: [
              if (!adding)
                TextButton.icon(
                  onPressed: _busy ? null : () => _confirmDelete ? _run(() => widget.editor.delete(widget.d!)) : setState(() => _confirmDelete = true),
                  icon: Icon(Icons.delete_outline_rounded, color: NextUpColors.deadline, size: 18),
                  label: Text(_confirmDelete ? 'Tap again to delete' : 'Delete', style: TextStyle(color: NextUpColors.deadline)),
                ),
              const Spacer(),
              TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
              const SizedBox(width: 8),
              FilledButton(onPressed: _busy ? null : _save, child: Text(_busy ? 'Saving…' : (adding ? 'Add' : 'Save'))),
            ]),
          ]),
        ),
      ),
    );
  }
}
