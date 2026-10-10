// Quest Log: log what you got done, earn XP, keep the streak. Same rules and sheet as the old Quest Log page.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:next_up_core/deadline_source.dart';
import 'package:next_up_core/quest.dart';
import 'package:next_up_core/theme.dart';
import 'package:next_up_core/worker_api.dart';

import '../dashboard/panel.dart';
import '../motion.dart';
import '../services.dart';

const _gold = Color(0xFFFFC53D);
const _flame = Color(0xFFFF6B4A);
const _combo = Color(0xFF4CC9F0);

class QuestScreen extends StatefulWidget {
  const QuestScreen({super.key, required this.services, required this.config, this.now, this.random});
  final Services services;
  final AppConfig config;
  final DateTime Function()? now;
  final math.Random? random;

  @override
  State<QuestScreen> createState() => _QuestScreenState();
}

class _QuestScreenState extends State<QuestScreen> {
  List<Quest> _quests = defaultQuests;
  List<XpRow> _rows = [];
  XpSettings _settings = const XpSettings();
  bool _loaded = false;
  String? _error, _note;

  DateTime _now() => (widget.now ?? DateTime.now)();
  late final math.Random _rng = widget.random ?? math.Random();
  XpRepository get _repo => widget.services.xpFor(widget.config.questSheetId);
  QuestModel get _model => QuestModel(_rows, _settings, _now().millisecondsSinceEpoch);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.config.questSheetId.isEmpty) {
      setState(() => _error = 'Add your XP Tracker sheet in Settings to use the Quest Log.');
      return;
    }
    try {
      final d = await _repo.load();
      if (!mounted) return;
      setState(() {
        _quests = d.quests;
        _rows = d.log;
        _settings = d.settings;
        _loaded = true;
        _error = null;
      });
    } on SourceException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _log(XpRow r, {String? note}) async {
    final before = _model.level;
    setState(() {
      _rows = [..._rows, r];
      _note = note;
    });
    if (_model.level > before) {
      showConfetti(context);
      _note = 'Level up! You are now ${titleFor(_model.level)}.';
    }
    try {
      await _repo.append([r], _settings.dayStartHour);
    } on SourceException catch (e) {
      if (mounted) setState(() => _note = 'Could not save: ${e.message}');
    }
  }

  void _do(Quest q) {
    final m = _model;
    if ((m.counts[q.id] ?? 0) >= q.cap) {
      setState(() => _note = 'That quest is maxed for today. It resets at ${_settings.dayStartHour}:00.');
      return;
    }
    final crit = _rng.nextDouble() < _settings.critChance;
    final r = questRow(q, m, _now().millisecondsSinceEpoch, crit: crit);
    _log(r, note: '${crit ? 'CRIT! ' : ''}+${r.xp} XP');
  }

  void _undo() {
    final r = lastUndoable(_rows);
    if (r != null) _log(undoRow(r, _now().millisecondsSinceEpoch), note: 'Undid: ${r.name}');
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null && !_loaded) return _Message(_error!, onRetry: widget.config.questSheetId.isEmpty ? null : _load);
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    final m = _model;
    final span = m.next - m.floor;
    final cats = [for (final c in categoryOrder) if (_quests.any((q) => q.cat == c)) c, ..._quests.map((q) => q.cat).where((c) => !categoryOrder.contains(c)).toSet()];
    final badges = earnedBadges(_rows, m.byDay, m.info, _settings.weeklyGoal);
    final recent = _rows.reversed.take(8).toList();
    return ListView(padding: const EdgeInsets.all(24), children: [
      Reveal(
        child: Panel(
          title: 'Level ${m.level}',
          accent: _gold,
          trailing: Text(titleFor(m.level).toUpperCase(), style: const TextStyle(color: _gold, fontSize: NextUpType.label, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              CountUp(value: m.total.toDouble(), format: (v) => v.round().toString(), style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800, fontFeatures: monoFeatures)),
              Padding(padding: EdgeInsets.only(left: 6, bottom: 6), child: Text('XP', style: TextStyle(color: NextUpColors.muted))),
              const Spacer(),
              Text('${m.next - m.total} to level ${m.level + 1}', style: TextStyle(color: NextUpColors.muted, fontSize: NextUpType.caption)),
            ]),
            const SizedBox(height: 10),
            GrowBar(value: span == 0 ? 0 : (m.total - m.floor) / span, color: _gold),
          ]),
        ),
      ),
      const SizedBox(height: 16),
      Reveal(
        index: 1,
        child: Wrap(spacing: 16, runSpacing: 16, children: [
          _Stat(title: 'Today', value: '${m.todayXp}', of: '/ ${_settings.dailyGoal.round()}', frac: m.todayXp / _settings.dailyGoal, color: NextUpColors.ok),
          _Stat(title: 'This week', value: '${m.weekXp}', of: '/ ${_settings.weeklyGoal.round()}', frac: m.weekXp / _settings.weeklyGoal, color: NextUpColors.accent),
          _Stat(title: 'Streak', value: '${m.info.streak}', of: 'days${m.info.shields > 0 ? ' · ${m.info.shields} shield' : ''}', frac: m.info.todayMet ? 1 : 0, color: _flame, note: m.info.atRisk ? 'Hit today\'s goal to keep it' : 'Best ${m.info.best}'),
          _Stat(title: 'Combo', value: 'x${m.multiplier.toStringAsFixed(1)}', of: m.comboLevel > 0 ? '${(m.comboLeftMs / 60000).ceil()}m left' : 'log a quest', frac: m.comboLevel / 5, color: _combo),
        ]),
      ),
      if (_note != null) Padding(padding: const EdgeInsets.only(top: 12), child: AnimatedSwitcher(duration: motionFast, child: Text(_note!, key: ValueKey(_note), style: const TextStyle(color: _gold, fontWeight: FontWeight.w700)))),
      const SizedBox(height: 16),
      for (var i = 0; i < cats.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Reveal(
            index: 2 + i,
            child: Panel(
              title: cats[i],
              child: Wrap(spacing: 10, runSpacing: 10, children: [
                for (final q in _quests.where((q) => q.cat == cats[i]))
                  _QuestButton(q: q, done: m.counts[q.id] ?? 0, mult: m.multiplier, onTap: () => _do(q)),
              ]),
            ),
          ),
        ),
      Panel(
        title: 'Badges',
        child: Wrap(spacing: 10, runSpacing: 10, children: [
          for (final b in badgeList)
            Tooltip(
              message: b.$3,
              child: Chip(
                avatar: Icon(badges.contains(b.$1) ? Icons.military_tech_rounded : Icons.lock_outline_rounded, size: 16, color: badges.contains(b.$1) ? _gold : NextUpColors.muted),
                label: Text(b.$2, style: TextStyle(fontSize: NextUpType.caption, color: badges.contains(b.$1) ? Colors.white : NextUpColors.muted)),
                backgroundColor: NextUpColors.raised,
                side: BorderSide.none,
              ),
            ),
        ]),
      ),
      const SizedBox(height: 16),
      Panel(
        title: 'Recent',
        trailing: recent.any((r) => r.kind != 'undo') ? TextButton(onPressed: _undo, child: const Text('Undo last')) : null,
        child: recent.isEmpty
            ? Text('Nothing logged yet.', style: TextStyle(color: NextUpColors.muted))
            : Column(children: [
                for (final r in recent)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      SizedBox(width: 92, child: Text(DateFormat('E h:mm a').format(DateTime.fromMillisecondsSinceEpoch(r.t)), style: TextStyle(color: NextUpColors.muted, fontSize: NextUpType.caption))),
                      Expanded(child: Text(r.kind == 'undo' ? 'Undid: ${r.name}' : r.name, style: const TextStyle(fontSize: NextUpType.body))),
                      Text('${r.xp < 0 ? '−' : '+'}${r.xp.abs()}', style: TextStyle(color: r.xp < 0 ? NextUpColors.deadline : _gold, fontWeight: FontWeight.w700, fontFeatures: monoFeatures)),
                    ]),
                  ),
              ]),
      ),
    ]);
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.title, required this.value, required this.of, required this.frac, required this.color, this.note});
  final String title, value, of;
  final String? note;
  final double frac;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 220,
        child: Panel(
          title: title,
          accent: color,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
              const SizedBox(width: 6),
              Flexible(child: Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(of, overflow: TextOverflow.ellipsis, style: TextStyle(color: NextUpColors.muted, fontSize: NextUpType.caption)))),
            ]),
            const SizedBox(height: 8),
            GrowBar(value: frac.clamp(0, 1).toDouble(), color: color, height: 6),
            if (note != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(note!, style: TextStyle(color: NextUpColors.muted, fontSize: NextUpType.caption))),
          ]),
        ),
      );
}

class _QuestButton extends StatelessWidget {
  const _QuestButton({required this.q, required this.done, required this.mult, required this.onTap});
  final Quest q;
  final int done;
  final double mult;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final maxed = done >= q.cap;
    return Semantics(
      button: true,
      label: '${q.name}, ${(q.xp * mult).round()} XP, $done of ${q.cap} today',
      child: Material(
        color: maxed ? NextUpColors.panel : NextUpColors.raised,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            width: 250,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: maxed ? NextUpColors.line : _gold.withValues(alpha: .35))),
            child: Row(children: [
              Expanded(child: Text(q.name, style: TextStyle(fontSize: NextUpType.body, fontWeight: FontWeight.w600, color: maxed ? NextUpColors.muted : Colors.white))),
              const SizedBox(width: 8),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('+${(q.xp * mult).round()}', style: const TextStyle(color: _gold, fontWeight: FontWeight.w800)),
                Text('$done/${q.cap}', style: TextStyle(color: NextUpColors.muted, fontSize: NextUpType.label)),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text, {this.onRetry});
  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(text, textAlign: TextAlign.center, style: TextStyle(color: NextUpColors.muted)),
            if (onRetry != null) TextButton(onPressed: onRetry, child: const Text('Try again')),
          ]),
        ),
      );
}
