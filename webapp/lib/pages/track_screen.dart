// Track: tap what you are doing, see the day as a timeline next to your calendar plan, and watch
// totals against daily and weekly targets. Everything lives in the Tracked tab of your Time Tracker sheet.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:next_up_core/calendar.dart';
import 'package:next_up_core/deadline_source.dart';
import 'package:next_up_core/theme.dart';
import 'package:next_up_core/track.dart';
import 'package:next_up_core/worker_api.dart';

import '../dashboard/panel.dart';
import '../format.dart';
import '../motion.dart';
import '../services.dart';

const trackPalette = [Color(0xFFE4572E), Color(0xFF2E86AB), Color(0xFFF6AE2D), Color(0xFF43AA8B), Color(0xFF9C4DCC), Color(0xFF00A6A6), Color(0xFFFF7F50), Color(0xFF6C6CD8), Color(0xFFD81B60), Color(0xFF8D6E63), Color(0xFF7CB342), Color(0xFFF3722C)];

Color colorFor(String cat, List<String> cats) {
  var i = cats.indexOf(cat);
  if (i < 0) {
    i = 0;
    for (final c in cat.codeUnits) {
      i = (i * 31 + c) & 0x7fffffff;
    }
  }
  return trackPalette[i % trackPalette.length];
}

class TrackScreen extends StatefulWidget {
  const TrackScreen({super.key, required this.services, required this.config, this.now});
  final Services services;
  final AppConfig config;
  final DateTime Function()? now; // for tests

  @override
  State<TrackScreen> createState() => _TrackScreenState();
}

class _TrackScreenState extends State<TrackScreen> {
  TrackData? _data;
  String? _error;
  bool _busy = false;
  int _dayOffset = 0;
  bool _week = false;
  final Map<int, List<CalendarEvent>> _plan = {};
  final Set<String> _hit = {};
  Timer? _tick;

  DateTime _now() => (widget.now ?? DateTime.now)();
  TrackRepository get _repo => widget.services.trackFor(widget.config.sheetId);

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _data?.running != null) setState(() {});
    });
    _load();
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (widget.config.sheetId.isEmpty) {
      setState(() => _error = 'Add your Time Tracker sheet in Settings to start tracking.');
      return;
    }
    try {
      final d = await _repo.load();
      if (!mounted) return;
      setState(() {
        _data = d;
        _error = null;
      });
      _loadPlan(_dayOffset);
    } on SourceException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _loadPlan(int off) async {
    if (_plan.containsKey(off)) return;
    final now = _now();
    final from = DateTime(now.year, now.month, now.day + off);
    try {
      final ev = await widget.services.calendar.load(from, from.add(const Duration(days: 1)));
      if (mounted) setState(() => _plan[off] = ev.where((e) => !e.allDay).toList());
    } catch (_) {
      if (mounted) setState(() => _plan[off] = const []);
    }
  }

  Future<void> _run(Future<void> Function() job) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await job();
      if (mounted) setState(() => _error = null);
    } on SourceException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toggle(String cat) {
    final d = _data;
    if (d == null) return;
    final running = d.running;
    _run(() => running != null && running.cat == cat ? _repo.stop(d, _now()) : _repo.start(d, cat, '', _now()));
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final now = _now();
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      children: [
        Reveal(child: Row(children: [
          Text('Track', style: TextStyle(fontSize: NextUpType.heading, fontWeight: FontWeight.w800)),
          const Spacer(),
          if (_busy) const Padding(padding: EdgeInsets.only(right: 12), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
          if (d != null) OutlinedButton.icon(onPressed: () => _editBlock(null), icon: const Icon(Icons.add_rounded), label: const Text('Add block')),
        ])),
        if (_error != null)
          Padding(padding: const EdgeInsets.only(top: 12), child: Panel(title: 'Heads up', child: Text(_error!, style: TextStyle(color: NextUpColors.muted)))),
        if (d == null && _error == null) const Padding(padding: EdgeInsets.only(top: 80), child: Center(child: CircularProgressIndicator())),
        if (d != null) ...[
          const SizedBox(height: 16),
          Reveal(index: 1, child: _NowBar(data: d, now: now, onStop: () => _run(() => _repo.stop(d, _now())))),
          const SizedBox(height: 12),
          Reveal(index: 2, child: _Categories(data: d, onTap: _toggle)),
          const SizedBox(height: 16),
          Reveal(index: 3, child: _timeline(d, now)),
          const SizedBox(height: 16),
          Reveal(index: 4, child: _stats(d, now)),
        ],
      ],
    );
  }

  Widget _timeline(TrackData d, DateTime now) {
    final day = DateTime(now.year, now.month, now.day + _dayOffset);
    final plan = _plan[_dayOffset] ?? const <CalendarEvent>[];
    return Panel(
      title: 'Day',
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(tooltip: 'Previous day', visualDensity: VisualDensity.compact, onPressed: () { setState(() => _dayOffset--); _loadPlan(_dayOffset); }, icon: const Icon(Icons.chevron_left_rounded)),
        SizedBox(width: 110, child: Text(dayLabel(day, now), textAlign: TextAlign.center, style: TextStyle(fontSize: NextUpType.body, fontWeight: FontWeight.w600))),
        IconButton(tooltip: 'Next day', visualDensity: VisualDensity.compact, onPressed: _dayOffset < 0 ? () { setState(() => _dayOffset++); _loadPlan(_dayOffset); } : null, icon: const Icon(Icons.chevron_right_rounded)),
      ]),
      child: _Timeline(day: day, now: now, blocks: d.onDay(day, now), plan: plan, cats: d.categories, onEdit: _editBlock, isToday: _dayOffset == 0),
    );
  }

  Widget _stats(TrackData d, DateTime now) {
    final from = _week ? weekStart(now) : DateTime(now.year, now.month, now.day);
    final to = _week ? from.add(const Duration(days: 7)) : from.add(const Duration(days: 1));
    final tot = d.totals(from, to, now);
    double target(String c) => ((_week ? d.targetFor(c)?.week : d.targetFor(c)?.day) ?? 0) * 3600e3;
    final cats = {...tot.keys, ...d.targets.where((t) => (_week ? t.week : t.day) > 0).map((t) => t.cat)}.toList()
      ..sort((a, b) => (tot[b]?.inMilliseconds ?? 0).compareTo(tot[a]?.inMilliseconds ?? 0));
    final maxMs = [3600e3, ...cats.map((c) => (tot[c]?.inMilliseconds ?? 0).toDouble()), ...cats.map(target)].reduce((a, b) => a > b ? a : b);
    return Panel(
      title: 'Totals',
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        SegmentedButton<bool>(
          showSelectedIcon: false,
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          segments: const [ButtonSegment(value: false, label: Text('Today')), ButtonSegment(value: true, label: Text('This week'))],
          selected: {_week},
          onSelectionChanged: (s) => setState(() => _week = s.first),
        ),
        const SizedBox(width: 8),
        TextButton(onPressed: () => _editTargets(d), child: const Text('Targets')),
      ]),
      child: cats.isEmpty
          ? Text(_week ? 'Nothing tracked this week yet.' : 'Nothing tracked today yet.', style: TextStyle(color: NextUpColors.muted))
          : Column(children: [
              for (final c in cats) _statRow(d, c, tot[c] ?? Duration.zero, target(c), maxMs, from),
            ]),
    );
  }

  Widget _statRow(TrackData d, String cat, Duration v, double targetMs, double maxMs, DateTime from) {
    final hit = targetMs > 0 && v.inMilliseconds >= targetMs;
    final key = '${_week ? 'w' : 'd'}${from.toIso8601String()}|$cat';
    if (hit && _hit.add(key)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showConfetti(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Target hit: $cat ${_week ? 'this week' : 'today'}')));
      });
    }
    final color = colorFor(cat, d.categories);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        SizedBox(width: 110, child: Text(cat, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: NextUpType.body, fontWeight: FontWeight.w600, color: hit ? NextUpColors.ok : null))),
        Expanded(child: GrowBar(value: v.inMilliseconds / (targetMs > 0 ? targetMs : maxMs), color: hit ? NextUpColors.ok : color)),
        const SizedBox(width: 12),
        SizedBox(width: 120, child: Text(targetMs > 0 ? '${hm(v)} / ${hm(Duration(milliseconds: targetMs.round()))}${hit ? ' ✓' : ''}' : hm(v), textAlign: TextAlign.right, style: TextStyle(fontSize: NextUpType.caption, color: NextUpColors.muted, fontFeatures: monoFeatures))),
      ]),
    );
  }

  Future<void> _editBlock(TrackBlock? b) async {
    final d = _data;
    if (d == null) return;
    final result = await showDialog<_BlockEdit>(context: context, builder: (_) => _BlockDialog(block: b, cats: d.categories, now: _now(), day: DateTime(_now().year, _now().month, _now().day + _dayOffset)));
    if (result == null) return;
    await _run(() async {
      if (result.delete && b != null) {
        await _repo.delete(d, b);
      } else if (b == null) {
        await _repo.add(d, TrackBlock(row: 0, start: result.start, end: result.end, cat: result.cat, note: result.note, id: newId()));
      } else {
        b.start = result.start;
        b.end = result.end;
        b.cat = result.cat;
        b.note = result.note;
        await _repo.update(d, b);
      }
    });
  }

  Future<void> _editTargets(TrackData d) async {
    final result = await showDialog<List<TrackTarget>>(context: context, builder: (_) => _TargetsDialog(data: d));
    if (result != null) await _run(() => _repo.saveTargets(d, result));
  }
}

class _NowBar extends StatelessWidget {
  const _NowBar({required this.data, required this.now, required this.onStop});
  final TrackData data;
  final DateTime now;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final run = data.running;
    final color = run == null ? NextUpColors.muted : colorFor(run.cat, data.categories);
    return AnimatedContainer(
      duration: motionBase,
      curve: motionCurve,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(color: run == null ? NextUpColors.panel : color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(16), border: Border.all(color: run == null ? NextUpColors.line : color.withValues(alpha: 0.5))),
      child: Row(children: [
        _Pulse(color: color, active: run != null),
        const SizedBox(width: 12),
        Expanded(
          child: AnimatedSwitcher(
            duration: motionFast,
            child: Text(run == null ? "Not tracking. Tap what you're doing to start." : run.cat + (run.note.isEmpty ? '' : ' · ${run.note}'), key: ValueKey(run?.id ?? 'idle'), style: TextStyle(fontSize: NextUpType.subtitle, fontWeight: FontWeight.w700, color: run == null ? NextUpColors.muted : null)),
          ),
        ),
        if (run != null) ...[
          Text(clockDuration(now.difference(run.start)), style: const TextStyle(fontSize: NextUpType.title, fontWeight: FontWeight.w800, fontFeatures: monoFeatures)),
          const SizedBox(width: 12),
          FilledButton(onPressed: onStop, child: const Text('Stop')),
        ],
      ]),
    );
  }
}

class _Pulse extends StatefulWidget {
  const _Pulse({required this.color, required this.active});
  final Color color;
  final bool active;
  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final animate = widget.active && !reduceMotion(context);
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) => Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle, boxShadow: animate ? [BoxShadow(color: widget.color.withValues(alpha: 0.6 * (1 - _c.value)), blurRadius: 10 * _c.value + 2, spreadRadius: 4 * _c.value)] : null),
      ),
    );
  }
}

class _Categories extends StatelessWidget {
  const _Categories({required this.data, required this.onTap});
  final TrackData data;
  final void Function(String) onTap;

  @override
  Widget build(BuildContext context) {
    final run = data.running;
    final cats = data.categories;
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final c in cats)
        _CatButton(label: c, color: colorFor(c, cats), on: run?.cat == c, onTap: () => onTap(c)),
    ]);
  }
}

class _CatButton extends StatelessWidget {
  const _CatButton({required this.label, required this.color, required this.on, required this.onTap});
  final String label;
  final Color color;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: on,
      label: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: AnimatedContainer(
          duration: motionFast,
          curve: motionCurve,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(color: on ? color : NextUpColors.panel, borderRadius: BorderRadius.circular(999), border: Border.all(color: on ? color : NextUpColors.line)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            AnimatedContainer(duration: motionFast, width: on ? 0 : 8, height: 8, margin: EdgeInsets.only(right: on ? 0 : 8), decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            Text(label, style: const TextStyle(fontSize: NextUpType.body, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.day, required this.now, required this.blocks, required this.plan, required this.cats, required this.onEdit, required this.isToday});
  final DateTime day, now;
  final List<TrackBlock> blocks;
  final List<CalendarEvent> plan;
  final List<String> cats;
  final void Function(TrackBlock) onEdit;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    var h0 = 6;
    for (final t in [...plan.map((p) => p.start), ...blocks.map((b) => b.start)]) {
      if (t.year == day.year && t.month == day.month && t.day == day.day && t.hour < h0) h0 = t.hour;
    }
    final t0 = day.add(Duration(hours: h0));
    final span = day.add(const Duration(days: 1)).difference(t0).inMinutes.toDouble();
    double pos(DateTime t) => (t.difference(t0).inMinutes / span).clamp(0.0, 1.0);
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      final step = w > 760 ? 1 : (w > 480 ? 2 : 3);
      Widget lane(String label, List<Widget> kids) => SizedBox(
            height: 46,
            child: Stack(clipBehavior: Clip.none, children: [
              Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(color: NextUpColors.raised, borderRadius: BorderRadius.circular(8)))),
              Positioned(left: 4, top: -14, child: Text(label.toUpperCase(), style: TextStyle(fontSize: 9, letterSpacing: 1, color: NextUpColors.muted))),
              ...kids,
            ]),
          );
      Widget at(DateTime a, DateTime z, Widget child) {
        final l = pos(a), r = pos(z);
        return Positioned(left: l * w, width: ((r - l) * w).clamp(3.0, w), top: 3, bottom: 3, child: child);
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          height: 18,
          child: Stack(children: [
            for (var h = ((h0 + step - 1) ~/ step) * step; h < 24; h += step)
              Positioned(left: pos(day.add(Duration(hours: h))) * w, child: Text(h == 12 ? '12p' : h > 12 ? '${h - 12}p' : '${h}a', style: TextStyle(fontSize: NextUpType.label, color: NextUpColors.muted))),
          ]),
        ),
        const SizedBox(height: 16),
        Stack(clipBehavior: Clip.none, children: [
          Column(children: [
            lane('plan', [
              for (final p in plan)
                at(p.start, p.end, Tooltip(message: '${DateFormat('h:mm a').format(p.start)} to ${DateFormat('h:mm a').format(p.end)} ${p.title}', child: Container(padding: const EdgeInsets.symmetric(horizontal: 6), alignment: Alignment.centerLeft, decoration: BoxDecoration(color: NextUpColors.accent.withValues(alpha: 0.28), borderRadius: BorderRadius.circular(6)), child: Text(p.title, maxLines: 1, overflow: TextOverflow.clip, style: const TextStyle(fontSize: NextUpType.label))))),
            ]),
            const SizedBox(height: 22),
            lane('tracked', [
              for (final b in blocks)
                at(b.start, b.endOr(now), Tooltip(message: '${b.cat}${b.note.isEmpty ? '' : ' · ${b.note}'}', child: InkWell(onTap: () => onEdit(b), borderRadius: BorderRadius.circular(6), child: Container(padding: const EdgeInsets.symmetric(horizontal: 6), alignment: Alignment.centerLeft, decoration: BoxDecoration(color: colorFor(b.cat, cats), borderRadius: BorderRadius.circular(6)), child: Text(b.cat, maxLines: 1, overflow: TextOverflow.clip, style: const TextStyle(fontSize: NextUpType.label, fontWeight: FontWeight.w700, color: Colors.white)))))),
            ]),
          ]),
          if (isToday) Positioned(left: pos(now) * w, top: -4, bottom: -4, child: Container(width: 2, color: NextUpColors.deadline)),
        ]),
      ]);
    });
  }
}

class _BlockEdit {
  const _BlockEdit({required this.cat, required this.note, required this.start, this.end, this.delete = false});
  final String cat, note;
  final DateTime start;
  final DateTime? end;
  final bool delete;
}

class _BlockDialog extends StatefulWidget {
  const _BlockDialog({required this.block, required this.cats, required this.now, required this.day});
  final TrackBlock? block;
  final List<String> cats;
  final DateTime now, day;
  @override
  State<_BlockDialog> createState() => _BlockDialogState();
}

class _BlockDialogState extends State<_BlockDialog> {
  late final TextEditingController _cat = TextEditingController(text: widget.block?.cat ?? widget.cats.first);
  late final TextEditingController _note = TextEditingController(text: widget.block?.note ?? '');
  late DateTime _start = widget.block?.start ?? DateTime(widget.day.year, widget.day.month, widget.day.day, widget.now.hour - 1 < 0 ? 0 : widget.now.hour - 1);
  late DateTime? _end = widget.block == null ? _start.add(const Duration(hours: 1)) : widget.block!.end;
  String? _err;

  Future<DateTime?> _pick(DateTime initial) async {
    final d = await showDatePicker(context: context, initialDate: initial, firstDate: DateTime(2020), lastDate: DateTime(2100));
    if (d == null || !mounted) return null;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initial));
    if (t == null) return null;
    return DateTime(d.year, d.month, d.day, t.hour, t.minute);
  }

  @override
  Widget build(BuildContext context) {
    final f = DateFormat('EEE, MMM d, h:mm a');
    return AlertDialog(
      title: Text(widget.block == null ? 'Add a block' : 'Edit block'),
      content: SizedBox(
        width: 380,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Autocomplete<String>(
            initialValue: TextEditingValue(text: _cat.text),
            optionsBuilder: (v) => widget.cats.where((c) => c.toLowerCase().contains(v.text.toLowerCase())),
            onSelected: (v) => _cat.text = v,
            fieldViewBuilder: (context, controller, focus, submit) {
              controller.addListener(() => _cat.text = controller.text);
              return TextField(controller: controller, focusNode: focus, decoration: const InputDecoration(labelText: 'Category'));
            },
          ),
          const SizedBox(height: 8),
          TextField(controller: _note, decoration: const InputDecoration(labelText: 'Note')),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () async { final d = await _pick(_start); if (d != null) setState(() => _start = d); }, child: Text('Start: ${f.format(_start)}'))),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () async { final d = await _pick(_end ?? _start.add(const Duration(hours: 1))); if (d != null) setState(() => _end = d); }, child: Text(_end == null ? 'End: still running' : 'End: ${f.format(_end!)}'))),
            if (_end != null) IconButton(tooltip: 'Still running', onPressed: () => setState(() => _end = null), icon: const Icon(Icons.close_rounded)),
          ]),
          if (_err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_err!, style: TextStyle(color: NextUpColors.deadline))),
        ]),
      ),
      actions: [
        if (widget.block != null) TextButton(onPressed: () => Navigator.pop(context, _BlockEdit(cat: _cat.text, note: '', start: _start, delete: true)), child: Text('Delete', style: TextStyle(color: NextUpColors.deadline))),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final end = _end;
            if (_cat.text.trim().isEmpty) return setState(() => _err = 'Pick a category.');
            if (end != null && !end.isAfter(_start)) return setState(() => _err = 'End has to be after start.');
            Navigator.pop(context, _BlockEdit(cat: _cat.text.trim(), note: _note.text.trim(), start: _start, end: end));
          },
          child: Text(widget.block == null ? 'Add' : 'Save'),
        ),
      ],
    );
  }
}

class _TargetsDialog extends StatefulWidget {
  const _TargetsDialog({required this.data});
  final TrackData data;
  @override
  State<_TargetsDialog> createState() => _TargetsDialogState();
}

class _TargetsDialogState extends State<_TargetsDialog> {
  late final Map<String, (TextEditingController, TextEditingController)> _c = {
    for (final cat in widget.data.categories)
      cat: (
        TextEditingController(text: (widget.data.targetFor(cat)?.day ?? 0) > 0 ? '${widget.data.targetFor(cat)!.day}' : ''),
        TextEditingController(text: (widget.data.targetFor(cat)?.week ?? 0) > 0 ? '${widget.data.targetFor(cat)!.week}' : ''),
      ),
  };

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Targets'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Align(alignment: Alignment.centerLeft, child: Text('Hours per category. Leave blank for no target.', style: TextStyle(color: NextUpColors.muted))),
            for (final e in _c.entries)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(children: [
                  SizedBox(width: 110, child: Text(e.key)),
                  Expanded(child: TextField(controller: e.value.$1, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'per day', isDense: true))),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: e.value.$2, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'per week', isDense: true))),
                ]),
              ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(context, [
            for (final e in _c.entries)
              if ((double.tryParse(e.value.$1.text) ?? 0) > 0 || (double.tryParse(e.value.$2.text) ?? 0) > 0)
                TrackTarget(e.key, day: double.tryParse(e.value.$1.text) ?? 0, week: double.tryParse(e.value.$2.text) ?? 0),
          ]),
          child: const Text('Save targets'),
        ),
      ],
    );
  }
}
