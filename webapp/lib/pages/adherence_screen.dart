// Adherence: how this week went against the plan, plus the blocks that still need a rating.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:next_up_core/deadline_source.dart';
import 'package:next_up_core/hours.dart';
import 'package:next_up_core/theme.dart';
import 'package:next_up_core/worker_api.dart';

import '../dashboard/panel.dart';
import '../motion.dart';
import '../services.dart';

class AdherenceScreen extends StatefulWidget {
  const AdherenceScreen({super.key, required this.services, required this.config, this.now});
  final Services services;
  final AppConfig config;
  final DateTime Function()? now;

  @override
  State<AdherenceScreen> createState() => _AdherenceScreenState();
}

class _AdherenceScreenState extends State<AdherenceScreen> {
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

  Future<void> _load() async {
    if (widget.config.sheetId.isEmpty) {
      setState(() => _error = 'Add your Time Tracker sheet in Settings to see your adherence.');
      return;
    }
    try {
      final r = await Future.wait([_repo.summary(), _repo.log()]);
      if (!mounted) return;
      setState(() {
        _summary = r[0] as HoursSummary;
        _blocks = blocksToRate(r[1] as List<List<String>>, _now());
        _error = null;
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

  @override
  Widget build(BuildContext context) {
    final s = _summary;
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      children: [
        Reveal(child: Row(children: [
          const Text('Adherence', style: TextStyle(fontSize: NextUpType.heading, fontWeight: FontWeight.w800)),
          const Spacer(),
          IconButton(tooltip: 'Refresh', onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
        ])),
        if (s != null) Reveal(index: 1, child: Text('${s.title}. Adherence counts only blocks you have rated.', style: const TextStyle(color: NextUpColors.muted, fontSize: NextUpType.body))),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Panel(title: 'Heads up', child: Text(_error!, style: const TextStyle(color: NextUpColors.muted)))),
        if (s == null && _error == null) const Padding(padding: EdgeInsets.only(top: 80), child: Center(child: CircularProgressIndicator())),
        if (s != null) ...[
          const SizedBox(height: 16),
          Reveal(index: 2, child: _Kpis(s: s)),
          const SizedBox(height: 16),
          LayoutBuilder(builder: (context, box) {
            final cols = box.maxWidth >= 900 ? 3 : (box.maxWidth >= 600 ? 2 : 1);
            final w = (box.maxWidth - 16 * (cols - 1)) / cols;
            Widget group(int i, String title, List<HoursBar> bars, {String Function(HoursBar)? label}) => bars.isEmpty
                ? const SizedBox.shrink()
                : SizedBox(width: w, child: Reveal(index: 3 + i, child: Panel(title: title, child: Column(children: [for (final b in bars) _BarRow(bar: b, today: label != null && b.label.replaceAll(RegExp(r'\s+'), ' ') == _todayLabel(_now()), unrated: label?.call(b))]))));
            return Wrap(spacing: 16, runSpacing: 16, children: [
              group(0, 'Courses · done vs planned', s.courses),
              group(1, 'By day · on plan vs planned', s.days, label: (b) => b.rated ? '${b.done.toStringAsFixed(1)}/${b.planned.toStringAsFixed(1)}h' : '${b.planned.toStringAsFixed(1)}h unrated'),
              group(2, 'By type · done vs planned', s.types),
            ]);
          }),
        ],
        if (_blocks != null) ...[
          const SizedBox(height: 16),
          Reveal(index: 6, child: Panel(
            title: 'Rate your blocks',
            child: _blocks!.isEmpty
                ? const Text('All caught up. Every block from the last two days has a status.', style: TextStyle(color: NextUpColors.muted))
                : Column(children: [for (final b in _blocks!.take(8)) _RateRow(key: ValueKey(b.row), block: b, now: _now(), busy: _rating.contains(b.row), note: _note[b.row], onRate: (st, h) => _rate(b, st, h))]),
          )),
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
    Widget kpi(String label, double? v, String Function(double) f, Color color, {String? fallback}) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: NextUpColors.panel, borderRadius: BorderRadius.circular(16), border: Border.all(color: NextUpColors.line)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label.toUpperCase(), style: const TextStyle(fontSize: NextUpType.label, letterSpacing: 1.2, color: NextUpColors.muted, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              v == null ? Text(fallback ?? '–', style: const TextStyle(fontSize: NextUpType.heading, fontWeight: FontWeight.w800)) : CountUp(value: v, format: f, style: TextStyle(fontSize: NextUpType.heading, fontWeight: FontWeight.w800, color: color, fontFeatures: monoFeatures)),
            ]),
          ),
        );
    return Wrap(spacing: 12, runSpacing: 12, children: [
      SizedBox(width: 220, child: Row(children: [kpi('Time adherence', s.timeAdherence, (v) => '${v.round()}%', _tone(s.timeAdherence))])),
      SizedBox(width: 220, child: Row(children: [kpi('Blocks done', s.blocksDone, (v) => '${v.round()}%', _tone(s.blocksDone))])),
      SizedBox(width: 220, child: Row(children: [kpi('Hours missed', s.hoursMissed, (v) => '${v.toStringAsFixed(1)}h', (s.hoursMissed ?? 0) > 3 ? NextUpColors.deadline : NextUpColors.ink)])),
      SizedBox(width: 220, child: Row(children: [kpi('Uni hours done', s.uniPlanned == 0 && s.uniDone == 0 ? null : s.uniDone, (v) => '${v.toStringAsFixed(v == v.roundToDouble() ? 0 : 1)}/${s.uniPlanned.toStringAsFixed(s.uniPlanned == s.uniPlanned.roundToDouble() ? 0 : 1)}', NextUpColors.ink)])),
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
        SizedBox(width: 92, child: Text(unrated ?? '${bar.done.toStringAsFixed(1)}/${bar.planned.toStringAsFixed(1)}h', textAlign: TextAlign.right, style: const TextStyle(fontSize: NextUpType.caption, color: NextUpColors.muted, fontFeatures: monoFeatures))),
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
        if (widget.note != null) Text(widget.note!, style: const TextStyle(fontSize: NextUpType.caption, color: NextUpColors.deadline)),
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
