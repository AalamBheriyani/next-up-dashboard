// Adherence: how this week went against the plan, plus the blocks that still need a rating.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:next_up_core/ask_claude.dart';
import 'package:next_up_core/board_layout.dart';
import 'package:next_up_core/deadline_source.dart';
import 'package:next_up_core/hours.dart';
import 'package:next_up_core/theme.dart';
import 'package:next_up_core/worker_api.dart';
import 'package:url_launcher/url_launcher.dart';

import '../board/page_board.dart';
import '../board/widget_board.dart';
import '../dashboard/panel.dart';
import '../dashboard/tile_row.dart';
import '../motion.dart';
import '../services.dart';
import '../refresh.dart';
import 'settings_screen.dart' show sheetLinkFor;

class AdherenceScreen extends StatefulWidget {
  const AdherenceScreen({super.key, required this.services, required this.config, this.now, this.layout = const BoardLayout(), this.onLayout, this.ask, this.onSettings});
  final Services services;
  /// For "Rate with Claude"; null hides it.
  final AskService? ask;
  final AppConfig config;
  final DateTime Function()? now;
  final BoardLayout layout;
  final ValueChanged<BoardLayout>? onLayout;
  final VoidCallback? onSettings; // opens Settings, where the sheet is added

  @override
  State<AdherenceScreen> createState() => _AdherenceScreenState();
}

class _AdherenceScreenState extends State<AdherenceScreen> with RefreshOnReturn {
  @override
  Future<void> refreshData() => _load();

  final _editing = ValueNotifier(false); // shared by the header's customise button and the board
  HoursSummary? _summary;
  List<RateBlock>? _blocks;
  String? _error;
  final Set<int> _rating = {};
  final Map<int, String> _note = {};

  DateTime _now() => (widget.now ?? DateTime.now)();
  HoursRepository get _repo => widget.services.hoursFor(widget.config.sheetId);

  @override
  void initState() {
    super.initState();
    _load();
  }

  DateTime? _updatedAt;

  Future<void> _load() async {
    if (widget.config.sheetId.isEmpty) {
      setState(() => _error = widget.services.signedIn() ? 'Add your Time Tracker sheet in Settings to see your adherence.' : 'Sign in to see your adherence.');
      return;
    }
    try {
      final r = await Future.wait([_repo.summary(), _repo.log()]);
      if (!mounted) return;
      setState(() {
        _summary = r[0] as HoursSummary;
        _blocks = blocksToRate(r[1] as List<List<String>>, _now());
        _error = null;
        _updatedAt = _now();
      });
    } on SourceException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _rate(RateBlock b, String status, double? actual) async {
    if (status == 'PARTIAL' && (actual == null || actual <= 0)) {
      setState(() => _note[b.row] = 'Enter the hours you actually did, then tap Partial.');
      return;
    }
    setState(() => _rating.add(b.row));
    try {
      await _repo.rate(b, status, actual);
      if (!mounted) return;
      setState(() => _blocks = _blocks?.where((x) => x.row != b.row).toList());
      _load(); // totals changed
    } on SourceException catch (e) {
      if (mounted) setState(() => _note[b.row] = e.message);
    } finally {
      if (mounted) setState(() => _rating.remove(b.row));
    }
  }

  Widget _group(String title, List<HoursBar> bars, {String Function(HoursBar)? label}) => Panel(
        title: title,
        child: Column(children: [for (final b in bars) _BarRow(bar: b, today: label != null && b.label.replaceAll(RegExp(r'\s+'), ' ') == _todayLabel(_now()), unrated: label?.call(b))]),
      );

  @override
  void dispose() {
    _editing.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = _summary;
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      children: [
        Reveal(child: Row(children: [
          const Text('Adherence', style: TextStyle(fontSize: NextUpType.heading, fontWeight: FontWeight.w800)),
          const Spacer(),
          if (widget.config.sheetId.isNotEmpty) TextButton.icon(onPressed: () => launchUrl(Uri.parse(sheetLinkFor(widget.config.sheetId))), icon: const Icon(Icons.open_in_new_rounded, size: 16), label: const Text('Open sheet')),
          UpdatedStamp(at: _updatedAt),
          if (s != null) CustomiseButton(editing: _editing),
          IconButton(tooltip: 'Refresh', onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
        ])),
        if (s != null) Reveal(index: 1, child: Text('${s.title}. Adherence counts only blocks you have rated.', style: TextStyle(color: NextUpColors.muted, fontSize: NextUpType.body))),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Panel(title: 'Heads up', child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(_error!, style: TextStyle(color: NextUpColors.muted)), if (widget.config.sheetId.isEmpty)
                    // Signed out, the sheet only looks missing: signing in brings the account's settings back.
                    widget.services.signedIn()
                        ? (widget.onSettings == null ? const SizedBox.shrink() : Padding(padding: const EdgeInsets.only(top: 8), child: FilledButton(onPressed: widget.onSettings, child: const Text('Add it in Settings'))))
                        : Padding(padding: const EdgeInsets.only(top: 8), child: FilledButton(onPressed: widget.services.signIn, child: const Text('Sign in')))]))),
        if (s == null && _error == null) const Padding(padding: EdgeInsets.only(top: 80), child: Center(child: CircularProgressIndicator())),
        if (s != null) ...[
          const SizedBox(height: 8),
          PageBoard(
            editing: _editing,
            layout: widget.layout,
            onLayout: widget.onLayout,
            items: [
              BoardItem(id: 'adh-kpis', name: 'Summary', span: 12, child: Reveal(index: 2, child: _Kpis(s: s))),
              if (s.courses.isNotEmpty) BoardItem(id: 'adh-courses', name: 'Courses', span: 4, child: Reveal(index: 3, child: _group('Courses · done vs planned', s.courses))),
              if (s.days.isNotEmpty) BoardItem(id: 'adh-days', name: 'By day', span: 4, child: Reveal(index: 4, child: _group('By day · on plan vs planned', s.days, label: (b) => b.rated ? '${b.done.toStringAsFixed(1)}/${b.planned.toStringAsFixed(1)}h' : '${b.planned.toStringAsFixed(1)}h unrated'))),
              if (s.types.isNotEmpty) BoardItem(id: 'adh-types', name: 'By type', span: 4, child: Reveal(index: 5, child: _group('By type · done vs planned', s.types))),
              if (_blocks != null)
                BoardItem(
                  id: 'adh-rate',
                  name: 'Rate your blocks',
                  span: 12,
                  child: Reveal(index: 6, child: Panel(
                    title: 'Rate your blocks',
                    child: _blocks!.isEmpty
                        ? Text('All caught up. Every block from the last two days has a status.', style: TextStyle(color: NextUpColors.muted))
                        : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            if (widget.ask != null) _RateWithClaude(ask: widget.ask!, blocks: _blocks!, now: _now, rate: _repo.rate, onSaved: _load),
                            // Side by side when there is room, instead of one narrow column.
                            Wrap(spacing: 12, children: [
                              for (final b in _blocks!.take(8)) _RateRow(key: ValueKey(b.row), block: b, now: _now(), busy: _rating.contains(b.row), note: _note[b.row], onRate: (st, h) => _rate(b, st, h)),
                            ]),
                          ]),
                  )),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

String _todayLabel(DateTime now) => DateFormat('EEE MMM d').format(now);

class _Kpis extends StatelessWidget {
  const _Kpis({required this.s});
  final HoursSummary s;

  Color _tone(double? p) => p == null ? NextUpColors.ink : p >= 70 ? NextUpColors.ok : p >= 40 ? NextUpColors.soon : NextUpColors.deadline;

  @override
  Widget build(BuildContext context) {
    Widget kpi(String label, double? v, String Function(double) f, Color color, {String? fallback}) => Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: NextUpColors.panel, borderRadius: BorderRadius.circular(16), border: Border.all(color: NextUpColors.line)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label.toUpperCase(), style: TextStyle(fontSize: NextUpType.label, letterSpacing: 1.2, color: NextUpColors.muted, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            v == null ? Text(fallback ?? '–', style: const TextStyle(fontSize: NextUpType.heading, fontWeight: FontWeight.w800)) : CountUp(value: v, format: f, style: TextStyle(fontSize: NextUpType.heading, fontWeight: FontWeight.w800, color: color, fontFeatures: monoFeatures)),
          ]),
        );
    return TileRow(children: [
      kpi('Time adherence', s.timeAdherence, (v) => '${v.round()}%', _tone(s.timeAdherence)),
      kpi('Blocks done', s.blocksDone, (v) => '${v.round()}%', _tone(s.blocksDone)),
      kpi('Hours missed', s.hoursMissed, (v) => '${v.toStringAsFixed(1)}h', (s.hoursMissed ?? 0) > 3 ? NextUpColors.deadline : NextUpColors.ink),
      kpi('Uni hours done', s.uniPlanned == 0 && s.uniDone == 0 ? null : s.uniDone, (v) => '${v.toStringAsFixed(v == v.roundToDouble() ? 0 : 1)}/${s.uniPlanned.toStringAsFixed(s.uniPlanned == s.uniPlanned.roundToDouble() ? 0 : 1)}', NextUpColors.ink),
    ]);
  }
}

class _BarRow extends StatelessWidget {
  const _BarRow({required this.bar, this.today = false, this.unrated});
  final HoursBar bar;
  final bool today;
  final String? unrated;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        SizedBox(width: 100, child: Text(bar.label, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: NextUpType.body, fontWeight: today ? FontWeight.w800 : FontWeight.w500, color: today ? NextUpColors.accent : null))),
        Expanded(child: GrowBar(value: bar.fraction, color: today ? NextUpColors.accent : NextUpColors.muted.withValues(alpha: 0.7))),
        const SizedBox(width: 10),
        SizedBox(width: 92, child: Text(unrated ?? '${bar.done.toStringAsFixed(1)}/${bar.planned.toStringAsFixed(1)}h', textAlign: TextAlign.right, style: TextStyle(fontSize: NextUpType.caption, color: NextUpColors.muted, fontFeatures: monoFeatures))),
      ]),
    );
  }
}

class _RateRow extends StatefulWidget {
  const _RateRow({super.key, required this.block, required this.now, required this.busy, required this.note, required this.onRate});
  final RateBlock block;
  final DateTime now;
  final bool busy;
  final String? note;
  final void Function(String status, double? actual) onRate;
  @override
  State<_RateRow> createState() => _RateRowState();
}

class _RateRowState extends State<_RateRow> {
  final _hours = TextEditingController();

  @override
  void dispose() {
    _hours.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.block;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: NextUpColors.raised, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(b.name, style: const TextStyle(fontSize: NextUpType.body, fontWeight: FontWeight.w700)),
        Text('${DateFormat('EEE, MMM d').format(b.from)} ${b.start} to ${b.end} · ${b.planned}h planned${b.isLive(widget.now) ? ' · happening now' : ''}', style: TextStyle(fontSize: NextUpType.caption, color: widget.note == null ? NextUpColors.muted : NextUpColors.deadline)),
        if (widget.note != null) Text(widget.note!, style: TextStyle(fontSize: NextUpType.caption, color: NextUpColors.deadline)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          for (final st in const ['DONE', 'PARTIAL', 'MISSED', 'SKIP'])
            OutlinedButton(onPressed: widget.busy ? null : () => widget.onRate(st, double.tryParse(_hours.text)), child: Text(st[0] + st.substring(1).toLowerCase())),
          SizedBox(width: 90, child: TextField(controller: _hours, keyboardType: TextInputType.number, decoration: const InputDecoration(isDense: true, hintText: 'hrs', helperText: 'for partial'))),
        ]),
      ]),
    );
  }
}

/// "Rate with Claude": say how the day went in your own words, Claude proposes a status for each block it
/// can match, you untick any it got wrong, and Apply writes them like the buttons do.
class _RateWithClaude extends StatefulWidget {
  const _RateWithClaude({required this.ask, required this.blocks, required this.now, required this.rate, required this.onSaved});
  final AskService ask;
  final List<RateBlock> blocks;
  final DateTime Function() now;
  final Future<void> Function(RateBlock, String, double?) rate;
  final VoidCallback onSaved;

  @override
  State<_RateWithClaude> createState() => _RateWithClaudeState();
}

class _RateWithClaudeState extends State<_RateWithClaude> {
  final _text = TextEditingController();
  bool _busy = false;
  String _note = '';
  List<RatePick> _picks = const [];
  final Set<int> _off = {}; // rows unticked

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _askClaude() async {
    final said = _text.text.trim();
    if (said.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _note = 'Asking Claude…';
      _picks = const [];
      _off.clear();
    });
    try {
      final out = await widget.ask.once(ratePrompt(widget.blocks, said, widget.now()));
      final r = parseRatings(out, widget.blocks);
      if (!mounted) return;
      setState(() {
        _picks = r.picks;
        _note = r.picks.isEmpty ? '${r.reply.isEmpty ? '' : '${r.reply} '}No blocks matched.' : r.reply;
      });
    } on SourceException catch (e) {
      if (mounted) setState(() => _note = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _apply() async {
    setState(() => _busy = true);
    try {
      for (final p in _picks.where((p) => !_off.contains(p.block.row))) {
        await widget.rate(p.block, p.status, p.hours);
      }
      if (!mounted) return;
      _text.clear();
      setState(() {
        _picks = const [];
        _note = 'Saved. Adherence updates in a moment.';
      });
      widget.onSaved();
    } on SourceException catch (e) {
      if (mounted) setState(() => _note = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    String label(String st) => st[0] + st.substring(1).toLowerCase();
    // A Material (not a coloured box) so the checkbox rows can show their ink.
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
      color: NextUpColors.raised,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Rate with Claude', style: TextStyle(color: NextUpColors.accent, fontWeight: FontWeight.w700, fontSize: NextUpType.caption)),
        const SizedBox(height: 6),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: TextField(
              controller: _text,
              minLines: 1,
              maxLines: 4,
              onSubmitted: (_) => _askClaude(),
              decoration: const InputDecoration(isDense: true, hintText: 'How did it go? e.g. "did chemistry, half of maths, skipped the gym"'),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(onPressed: _busy ? null : _askClaude, child: const Text('Rate')),
        ]),
        if (_note.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_note, style: TextStyle(color: NextUpColors.muted, fontSize: NextUpType.caption))),
        if (_picks.isNotEmpty) ...[
          const SizedBox(height: 4),
          for (final p in _picks)
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: !_off.contains(p.block.row),
              onChanged: _busy ? null : (on) => setState(() => on == true ? _off.remove(p.block.row) : _off.add(p.block.row)),
              title: Text.rich(TextSpan(children: [
                TextSpan(text: '${label(p.status)}${p.hours == null ? '' : ' ${p.hours}h'}  ', style: const TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(text: '${p.block.name} · ${p.block.date} ${p.block.start}', style: TextStyle(color: NextUpColors.muted)),
              ])),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonal(onPressed: _busy || _off.length == _picks.length ? null : _apply, child: const Text('Apply to Time Tracker')),
          ),
        ],
      ]),
      ),
      ),
    );
  }
}
