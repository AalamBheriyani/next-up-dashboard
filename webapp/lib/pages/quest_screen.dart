// Quest Log: log what you got done, earn XP, keep the streak. Same rules and sheet as the old Quest Log page.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:next_up_core/board_layout.dart';
import 'package:next_up_core/deadline_source.dart';
import 'package:next_up_core/quest.dart';
import 'package:next_up_core/theme.dart';
import 'package:next_up_core/worker_api.dart';
import 'package:url_launcher/url_launcher.dart';

import '../board/page_board.dart';
import '../board/widget_board.dart';
import '../dashboard/panel.dart';
import '../dashboard/tile_row.dart';
import '../motion.dart';
import '../refresh.dart';
import '../services.dart';
import '../xp_queue.dart';
import 'settings_screen.dart' show sheetLinkFor;

const _muteKey = 'nu.web.mute';
const _gold = Color(0xFFFFC53D);
const _flame = Color(0xFFFF6B4A);
const _combo = Color(0xFF4CC9F0);

class QuestScreen extends StatefulWidget {
  const QuestScreen({super.key, required this.services, required this.config, this.now, this.random, this.layout = const BoardLayout(), this.onLayout, this.onSettings});
  final Services services;
  final AppConfig config;
  final DateTime Function()? now;
  final math.Random? random;
  final BoardLayout layout;
  final ValueChanged<BoardLayout>? onLayout;
  final VoidCallback? onSettings; // opens Settings, where the sheet is added

  @override
  State<QuestScreen> createState() => _QuestScreenState();
}

class _QuestScreenState extends State<QuestScreen> with RefreshOnReturn {
  // Coming back after half a minute reloads, as the old Quest page did; a slow tick keeps the combo
  // countdown, the multiplier and the day rollover current in between.
  @override
  Duration get refreshAfter => const Duration(seconds: 30);
  @override
  Future<void> refreshData() => _load();
  Timer? _tick;

  final _editing = ValueNotifier(false); // shared by the header's customise button and the board
  List<Quest> _quests = defaultQuests;
  List<XpRow> _rows = [];
  XpSettings _settings = const XpSettings();
  bool _loaded = false;
  String? _error, _note;
  late bool _muted = widget.services.store.get(_muteKey) == '1';
  int _shake = 0; // bumped on a crit so the page gives a short shake

  DateTime _now() => (widget.now ?? DateTime.now)();
  late final math.Random _rng = widget.random ?? math.Random();
  XpRepository get _repo => widget.services.xpFor(widget.config.questSheetId);
  late final _queue = XpQueue(widget.services.store);
  int _unsaved = 0; // rows still waiting on this device
  QuestModel get _model => QuestModel(_rows, _settings, _now().millisecondsSinceEpoch);

  @override
  void initState() {
    super.initState();
    _load();
    _tick = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted && _loaded) setState(() {});
    });
  }

  Future<void> _load() async {
    if (widget.config.questSheetId.isEmpty) {
      setState(() => _error = 'Add your XP Tracker sheet in Settings to use the Quest Log.');
      return;
    }
    try {
      final d = await _repo.load();
      if (!mounted) return;
      // Rows still waiting on this device count too, so nothing earned offline disappears from the page.
      final have = {for (final r in d.log) '${r.t}|${r.q}'};
      final waiting = [for (final r in _queue.pending) if (!have.contains('${r.t}|${r.q}')) r];
      setState(() {
        _quests = d.quests;
        _rows = [...d.log, ...waiting];
        _unsaved = waiting.length;
        _settings = d.settings;
        _loaded = true;
        _error = null;
      });
      if (waiting.isNotEmpty) _retry();
    } on SourceException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _retry() async {
    try {
      await _queue.flush(_repo, _settings.dayStartHour);
      if (mounted) setState(() => _unsaved = 0);
    } catch (e) {
      if (mounted) {
        setState(() {
          _unsaved = _queue.pending.length;
          _note = 'Not saved yet: ${e is SourceException ? e.message : 'no connection'}';
        });
      }
    }
  }

  void _beep(List<double> freqs) {
    if (!_muted) widget.services.beep(freqs);
  }

  void _toast(String text) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(text), duration: const Duration(milliseconds: 2600)));

  Future<void> _log(XpRow r, {String? note, bool crit = false}) async {
    final was = _model;
    setState(() {
      _rows = [..._rows, r];
      _note = note;
    });
    final now = _model;
    final gain = r.xp > 0 && r.kind != 'undo';
    if (crit && !reduceMotion(context)) _shake++;
    if (now.level > was.level) {
      showConfetti(context);
      _note = 'Level up! You are now ${titleFor(now.level)}.';
      _beep([523, 659, 784, 1047]);
      _levelCard(now.level);
    } else if (gain) {
      _beep(crit ? [880, 1175, 1568] : [660, 880]);
      if (was.todayXp < _settings.dailyGoal && now.todayXp >= _settings.dailyGoal) {
        _toast('Daily goal hit. Streak is safe.');
      } else if (was.weekXp < _settings.weeklyGoal && now.weekXp >= _settings.weeklyGoal) {
        _toast('Weekly goal hit.');
      }
    }
    _queue.add([r]);
    await _retry();
  }

  // The old page's level-up card: the new level, its title and one button to carry on.
  void _levelCard(int level) => showGeneralDialog(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'Level up',
        transitionDuration: motionBase,
        transitionBuilder: (context, a, _, child) => ScaleTransition(scale: CurvedAnimation(parent: a, curve: Curves.easeOutBack), child: FadeTransition(opacity: a, child: child)),
        pageBuilder: (context, _, _) => Center(
          child: Material(
            color: NextUpColors.panel,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              width: 320,
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), border: Border.all(color: _gold, width: 1.5)),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('LEVEL UP', style: TextStyle(color: _gold, fontSize: NextUpType.label, fontWeight: FontWeight.w800, letterSpacing: 2)),
                const SizedBox(height: 8),
                Text('$level', style: const TextStyle(fontSize: 72, fontWeight: FontWeight.w900, height: 1, color: _gold)),
                const SizedBox(height: 8),
                Text(titleFor(level), style: const TextStyle(fontSize: NextUpType.title, fontWeight: FontWeight.w700)),
                const SizedBox(height: 20),
                FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Keep going')),
              ]),
            ),
          ),
        ),
      );

  void _do(Quest q) {
    final m = _model;
    if ((m.counts[q.id] ?? 0) >= q.cap) {
      final text = 'That quest is maxed for today. It resets at ${_settings.dayStartHour}:00.';
      setState(() => _note = text);
      _toast(text);
      return;
    }
    final crit = _rng.nextDouble() < _settings.critChance;
    final r = questRow(q, m, _now().millisecondsSinceEpoch, crit: crit);
    if (!reduceMotion(context)) _float = (q.id, '${crit ? 'CRIT ' : ''}+${r.xp} XP', (_float?.$3 ?? 0) + 1);
    _log(r, note: '${crit ? 'CRIT! ' : ''}+${r.xp} XP', crit: crit);
  }

  (String, String, int)? _float; // the quest whose tile shows a rising "+15 XP", its text, and a serial to replay it

  void _undo() {
    final r = lastUndoable(_rows);
    if (r != null) _log(undoRow(r, _now().millisecondsSinceEpoch), note: 'Undid: ${r.name}');
  }

  @override
  void dispose() {
    _editing.dispose();
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null && !_loaded) return _Message(_error!, onRetry: widget.config.questSheetId.isEmpty ? null : _load, onSettings: widget.config.questSheetId.isEmpty ? widget.onSettings : null);
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    final m = _model;
    final span = m.next - m.floor;
    final cats = [for (final c in categoryOrder) if (_quests.any((q) => q.cat == c)) c, ..._quests.map((q) => q.cat).where((c) => !categoryOrder.contains(c)).toSet()];
    final badges = earnedBadges(_rows, m.byDay, m.info, _settings.weeklyGoal);
    final recent = _rows.reversed.take(8).toList();
    return TweenAnimationBuilder<double>(
      key: ValueKey(_shake),
      tween: Tween(begin: _shake == 0 ? 1 : 0, end: 1),
      duration: const Duration(milliseconds: 350),
      builder: (context, t, child) => Transform.translate(offset: Offset(math.sin(t * math.pi * 6) * (1 - t) * 6, 0), child: child),
      child: ListView(padding: const EdgeInsets.all(24), children: [
      Row(children: [
        const Text('Quest Log', style: TextStyle(fontSize: NextUpType.heading, fontWeight: FontWeight.w800)),
        const SizedBox(width: 16),
        // The last XP gained shows beside the title, so the page doesn't jump down when it appears.
        Expanded(child: AnimatedSwitcher(duration: motionFast, child: _note == null ? const SizedBox.shrink() : Text(_note!, key: ValueKey(_note), overflow: TextOverflow.ellipsis, style: const TextStyle(color: _gold, fontWeight: FontWeight.w700)))),
        if (_unsaved > 0)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: ActionChip(avatar: const Icon(Icons.cloud_off_rounded, size: 16), label: Text('$_unsaved not saved yet · Retry'), onPressed: _retry),
          ),
        IconButton(
          tooltip: _muted ? 'Turn sound on' : 'Turn sound off',
          icon: Icon(_muted ? Icons.volume_off_rounded : Icons.volume_up_rounded, size: 20),
          onPressed: () {
            setState(() => _muted = !_muted);
            widget.services.store.set(_muteKey, _muted ? '1' : '0');
          },
        ),
        TextButton.icon(onPressed: () => launchUrl(Uri.parse(sheetLinkFor(widget.config.questSheetId))), icon: const Icon(Icons.open_in_new_rounded, size: 16), label: const Text('Open XP sheet')),
        CustomiseButton(editing: _editing),
      ]),
      const SizedBox(height: 8),
      PageBoard(editing: _editing, layout: widget.layout, onLayout: widget.onLayout, items: [
      BoardItem(id: 'quest-level', name: 'Level', span: 12, child: Reveal(
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
      )),
      BoardItem(id: 'quest-stats', name: 'Today and streak', span: 12, child: Reveal(
        index: 1,
        child: TileRow(gap: 12, minTile: 140, children: [
          _Stat(title: 'Today', value: '${m.todayXp}', of: '/ ${_settings.dailyGoal.round()}', frac: m.todayXp / _settings.dailyGoal, color: NextUpColors.ok),
          _Stat(title: 'This week', value: '${m.weekXp}', of: '/ ${_settings.weeklyGoal.round()}', frac: m.weekXp / _settings.weeklyGoal, color: NextUpColors.accent),
          _Stat(title: 'Streak', value: '${m.info.streak}', of: 'days${m.info.shields > 0 ? ' · ${m.info.shields} shield' : ''}', frac: m.info.todayMet ? 1 : 0, color: _flame, note: m.info.atRisk ? 'Hit today\'s goal to keep it' : 'Best ${m.info.best}'),
          _Stat(title: 'Combo', value: 'x${m.multiplier.toStringAsFixed(1)}', of: m.comboLevel > 0 ? '${(m.comboLeftMs / 60000).ceil()}m left' : 'log a quest', frac: m.comboLevel / 5, color: _combo),
        ]),
      )),
      for (var i = 0; i < cats.length; i++)
        BoardItem(
          id: _catId(cats[i]),
          name: cats[i],
          span: 6,
          child: Reveal(
            index: 2 + i,
            child: Panel(
              title: cats[i],
              // Buttons share the row evenly (about 240 px each), so a phone gets one full-width column.
              child: LayoutBuilder(builder: (context, box) {
                final cols = math.max(1, (box.maxWidth + 10) ~/ 250);
                final w = (box.maxWidth - 10 * (cols - 1)) / cols;
                return Wrap(spacing: 10, runSpacing: 10, children: [
                for (final q in _quests.where((q) => q.cat == cats[i]))
                  _QuestButton(q: q, width: w, done: m.counts[q.id] ?? 0, mult: m.multiplier, onTap: () => _do(q), float: _float?.$1 == q.id ? _float : null),
                ]);
              }),
            ),
          ),
        ),
      BoardItem(id: 'quest-week', name: 'This week', span: 6, child: Panel(
        title: 'This week',
        trailing: Text('${m.weekXp} of ${_settings.weeklyGoal.round()} XP', style: TextStyle(color: NextUpColors.muted, fontSize: NextUpType.label)),
        child: _WeekBars(byDay: m.byDay, today: m.today, goal: _settings.dailyGoal),
      )),
      BoardItem(id: 'quest-badges', name: 'Badges', span: 6, child: Panel(
        title: 'Badges',
        child: Wrap(spacing: 10, runSpacing: 10, children: [
          for (final b in badgeList)
            Tooltip(
              message: b.$3,
              child: Chip(
                avatar: Icon(badges.contains(b.$1) ? Icons.military_tech_rounded : Icons.lock_outline_rounded, size: 16, color: badges.contains(b.$1) ? _gold : NextUpColors.muted),
                // The description shows under the name, as on the old page; a tooltip is hard to find on a phone.
                label: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(b.$2, style: TextStyle(fontSize: NextUpType.caption, color: badges.contains(b.$1) ? Colors.white : NextUpColors.muted)),
                  Text(b.$3, style: TextStyle(fontSize: NextUpType.label, color: NextUpColors.muted)),
                ]),
                backgroundColor: NextUpColors.raised,
                side: BorderSide.none,
              ),
            ),
        ]),
      )),
      BoardItem(id: 'quest-recent', name: 'Recent', span: 12, child: Panel(
        title: 'Recent',
        trailing: recent.any((r) => r.kind != 'undo') ? TextButton(onPressed: _undo, child: const Text('Undo last')) : null,
        child: recent.isEmpty
            ? Text('No quests logged yet. Tap "Started a planned block" to earn your first +10.', style: TextStyle(color: NextUpColors.muted))
            : Column(children: [
                for (final r in recent)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      SizedBox(width: 92, child: Text(DateFormat('E h:mm a').format(DateTime.fromMillisecondsSinceEpoch(r.t)), style: TextStyle(color: NextUpColors.muted, fontSize: NextUpType.caption))),
                      if (r.kind == 'auto' || (r.mult >= 2 && r.kind != 'undo'))
                        Container(
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(color: (r.kind == 'auto' ? NextUpColors.accent : _gold).withValues(alpha: 0.18), borderRadius: BorderRadius.circular(4)),
                          child: Text(r.kind == 'auto' ? 'TIMER' : 'CRIT', style: TextStyle(color: r.kind == 'auto' ? NextUpColors.accent : _gold, fontSize: NextUpType.label, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
                        ),
                      Expanded(child: Text(r.kind == 'undo' ? 'Undid: ${r.name}' : r.name, style: const TextStyle(fontSize: NextUpType.body))),
                      Text('${r.xp < 0 ? '−' : '+'}${r.xp.abs()}', style: TextStyle(color: r.xp < 0 ? NextUpColors.deadline : _gold, fontWeight: FontWeight.w700, fontFeatures: monoFeatures)),
                    ]),
                  ),
              ]),
      )),
      ]),
      Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Text('Day rolls over at ${_settings.dayStartHour}:00. Edit quests and goals in the sheet.', style: TextStyle(color: NextUpColors.muted, fontSize: NextUpType.caption)),
      ),
    ]));
  }
}

/// Monday to Sunday: each day's XP against the daily goal, today outlined, as on the old Quest page.
class _WeekBars extends StatelessWidget {
  const _WeekBars({required this.byDay, required this.today, required this.goal});
  final Map<String, int> byDay;
  final String today;
  final double goal;

  @override
  Widget build(BuildContext context) {
    final start = weekStartKey(today);
    final keys = [for (var i = 0; i < 7; i++) addDays(start, i)];
    final vals = [for (final k in keys) byDay[k] ?? 0];
    final top = math.max(goal * 1.5, vals.fold<int>(0, math.max).toDouble());
    const names = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return SizedBox(
      height: 130,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (var i = 0; i < 7; i++)
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
              Text(vals[i] == 0 ? '' : '${vals[i]}', style: TextStyle(color: NextUpColors.muted, fontSize: NextUpType.label, fontFeatures: monoFeatures)),
              const SizedBox(height: 4),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: math.max(3, vals[i] / top * 84)),
                duration: motionBase,
                curve: motionCurve,
                builder: (context, h, _) => Container(
                  width: 22,
                  height: h,
                  decoration: BoxDecoration(
                    color: vals[i] >= goal ? _gold : (vals[i] > 0 ? _gold.withValues(alpha: 0.45) : NextUpColors.line),
                    borderRadius: BorderRadius.circular(4),
                    border: keys[i] == today ? Border.all(color: Colors.white, width: 1.5) : null,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(names[i], style: TextStyle(color: keys[i] == today ? Colors.white : NextUpColors.muted, fontSize: NextUpType.caption, fontWeight: keys[i] == today ? FontWeight.w800 : FontWeight.w400)),
            ]),
          ),
      ]),
    );
  }
}

/// A stable id for a category's panel, safe for the saved layout (letters, digits and dashes, at most 30).
String _catId(String cat) {
  final slug = cat.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
  final id = 'quest-c-$slug';
  return id.length > 30 ? id.substring(0, 30) : id;
}

class _Stat extends StatelessWidget {
  const _Stat({required this.title, required this.value, required this.of, required this.frac, required this.color, this.note});
  final String title, value, of;
  final String? note;
  final double frac;
  final Color color;

  @override
  Widget build(BuildContext context) => Panel(
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
      );
}

class _QuestButton extends StatelessWidget {
  const _QuestButton({required this.q, required this.width, required this.done, required this.mult, required this.onTap, this.float});
  final Quest q;
  final (String, String, int)? float;
  final int done;
  final double mult, width;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final maxed = done >= q.cap;
    final tile = Semantics(
      button: true,
      label: '${q.name}, ${(q.xp * mult).round()} XP, $done of ${q.cap} today',
      child: Material(
        color: maxed ? NextUpColors.panel : NextUpColors.raised,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            width: width,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: maxed ? NextUpColors.line : _gold.withValues(alpha: .35))),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(q.name, style: TextStyle(fontSize: NextUpType.body, fontWeight: FontWeight.w600, color: maxed ? NextUpColors.muted : Colors.white)),
                  const SizedBox(height: 2),
                  // The old page's count line: "2 of 3 today", "Once a day", and which quests the timer logs.
                  Text(
                    '${q.cap > 1 ? '$done of ${q.cap} today' : (done > 0 ? 'Done today' : 'Once a day')}${q.id == 'timer' || q.id == 'break' ? ' · logs itself from the timer' : ''}',
                    style: TextStyle(color: NextUpColors.muted, fontSize: NextUpType.label),
                  ),
                ]),
              ),
              const SizedBox(width: 8),
              Text(maxed ? 'Done' : '+${(q.xp * mult).round()}', style: TextStyle(color: maxed ? NextUpColors.muted : _gold, fontWeight: FontWeight.w800)),
            ]),
          ),
        ),
      ),
    );
    final f = float;
    if (f == null) return tile;
    // The old page's floating "+15" rising out of the tapped tile.
    return Stack(clipBehavior: Clip.none, children: [
      tile,
      Positioned(
        right: 12,
        top: 0,
        child: IgnorePointer(
          child: TweenAnimationBuilder<double>(
            key: ValueKey(f.$3),
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOut,
            builder: (context, v, child) => Transform.translate(offset: Offset(0, -28 * v), child: Opacity(opacity: (1 - v).clamp(0, 1), child: child)),
            child: Text(f.$2, style: const TextStyle(color: _gold, fontWeight: FontWeight.w900, fontSize: NextUpType.body)),
          ),
        ),
      ),
    ]);
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text, {this.onRetry, this.onSettings});
  final String text;
  final VoidCallback? onRetry, onSettings;

  // The same title and "Heads up" card as the other pages, so an empty Quest Log doesn't look broken.
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(24), children: [
        const Text('Quest Log', style: TextStyle(fontSize: NextUpType.heading, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        Panel(
          title: 'Heads up',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(text, style: TextStyle(color: NextUpColors.muted)),
            if (onRetry != null) Padding(padding: const EdgeInsets.only(top: 8), child: OutlinedButton(onPressed: onRetry, child: const Text('Try again'))),
            if (onSettings != null) Padding(padding: const EdgeInsets.only(top: 8), child: FilledButton(onPressed: onSettings, child: const Text('Add it in Settings'))),
          ]),
        ),
      ]);
}
