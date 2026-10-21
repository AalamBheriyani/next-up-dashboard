// Quest Log: the XP maths (levels, streaks, combos, badges) and the XP Tracker sheet it reads and writes.
// A direct port of the rules in docs/quest.html, so both give the same numbers from the same sheet.
import 'dart:math' as math;

import 'sheets.dart';

class XpSettings {
  const XpSettings({this.dailyGoal = 60, this.weeklyGoal = 500, this.critChance = 0.12, this.comboMinutes = 45, this.dayStartHour = 4});
  final double dailyGoal, weeklyGoal, critChance, comboMinutes;
  final int dayStartHour;

  factory XpSettings.parse(List<List<String>> rows) {
    final m = <String, double>{};
    for (final r in rows) {
      if (r.length > 1) {
        final n = double.tryParse(r[1]);
        if (n != null) m[r[0]] = n;
      }
    }
    const d = XpSettings();
    return XpSettings(
      dailyGoal: m['daily_goal'] ?? d.dailyGoal,
      weeklyGoal: m['weekly_goal'] ?? d.weeklyGoal,
      critChance: m['crit_chance'] ?? d.critChance,
      comboMinutes: m['combo_minutes'] ?? d.comboMinutes,
      dayStartHour: (m['day_start_hour'] ?? d.dayStartHour).round(),
    );
  }
}

class Quest {
  const Quest({required this.id, required this.name, required this.cat, required this.xp, required this.cap});
  final String id, name, cat;
  final int xp, cap;
}

const defaultQuests = [
  Quest(id: 'start', name: 'Started a planned block', cat: 'Start', xp: 10, cap: 8),
  Quest(id: 'timer', name: 'Finished a timer session', cat: 'Focus', xp: 15, cap: 6),
  Quest(id: 'break', name: 'Took the break (reverse pomodoro)', cat: 'Focus', xp: 5, cap: 6),
  Quest(id: 'block', name: 'Finished a planned block', cat: 'Finish', xp: 25, cap: 6),
  Quest(id: 'top3', name: 'Top 3 item done', cat: 'Finish', xp: 30, cap: 3),
  Quest(id: 'early', name: 'Submitted before the personal deadline', cat: 'Finish', xp: 50, cap: 3),
  Quest(id: 'plan', name: 'Daily Planning done', cat: 'Habits', xp: 15, cap: 1),
  Quest(id: 'log', name: 'Daily Log done', cat: 'Habits', xp: 15, cap: 1),
  Quest(id: 'anki', name: 'Anki reviews cleared', cat: 'Habits', xp: 15, cap: 1),
  Quest(id: 'sleep', name: 'In bed on time', cat: 'Habits', xp: 20, cap: 1),
  Quest(id: 'meal', name: 'Cooked or prepped a meal', cat: 'Habits', xp: 10, cap: 2),
  Quest(id: 'move', name: 'Workout or walk', cat: 'Habits', xp: 30, cap: 1),
  Quest(id: 'weekly', name: 'Weekly Planning done', cat: 'Habits', xp: 40, cap: 1),
  Quest(id: 'boss', name: 'Boss fight: exam or big deadline done', cat: 'Boss', xp: 100, cap: 2),
];

const categoryOrder = ['Start', 'Focus', 'Finish', 'Habits', 'Boss'];
const titles = ['Rookie', 'Spark', 'Starter', 'Momentum', 'Focus Cadet', 'Streaker', 'Deep Diver', 'Flow Knight', 'Time Lord', 'Deadline Slayer'];

List<Quest> parseQuests(List<List<String>> rows) {
  final out = <Quest>[];
  for (final r in rows) {
    if (r.length < 2 || r[0].isEmpty || r[1].isEmpty) continue;
    String c(int i) => i < r.length ? r[i] : '';
    final active = !RegExp(r'^(false|no|0)$', caseSensitive: false).hasMatch(r.length > 5 ? r[5] : 'TRUE');
    if (!active) continue;
    out.add(Quest(id: r[0], name: r[1], cat: c(2).isEmpty ? 'Other' : c(2), xp: double.tryParse(c(3))?.round() ?? 10, cap: math.max(1, double.tryParse(c(4))?.round() ?? 99)));
  }
  return out;
}

/// One line of the XP sheet's Log tab: time (ms), day, quest id, name, base xp, multiplier, xp, kind.
class XpRow {
  const XpRow({required this.t, required this.q, required this.name, required this.base, required this.mult, required this.xp, required this.kind});
  final int t;
  final String q, name, kind; // kind: quest, boss, auto or undo
  final double base, mult;
  final int xp;

  static XpRow? fromSheet(List<String> r) {
    String c(int i) => i < r.length ? r[i] : '';
    final t = double.tryParse(c(0))?.round() ?? 0;
    if (t <= 0 || c(2).isEmpty) return null;
    return XpRow(t: t, q: c(2), name: c(3), base: double.tryParse(c(4)) ?? 0, mult: double.tryParse(c(5)) ?? 1, xp: double.tryParse(c(6))?.round() ?? 0, kind: c(7).isEmpty ? 'quest' : c(7));
  }

  List<String> toSheet(int dayStartHour) => ['$t', dayKey(t, dayStartHour), q, name, '$base', '$mult', '$xp', kind];
}

String _p(int n) => n.toString().padLeft(2, '0');

/// The day a moment belongs to, where the day rolls over at [startHour] (so late nights count for yesterday).
String dayKey(int tMs, int startHour) {
  final d = DateTime.fromMillisecondsSinceEpoch(tMs).subtract(Duration(hours: startHour));
  return '${d.year}-${_p(d.month)}-${_p(d.day)}';
}

DateTime _parseKey(String k) {
  final p = k.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2], 12);
}

String addDays(String key, int n) {
  final d = _parseKey(key).add(Duration(days: n));
  return '${d.year}-${_p(d.month)}-${_p(d.day)}';
}

/// Weeks start on Monday here, as in the Quest Log.
String weekStartKey(String key) => addDays(key, -((_parseKey(key).weekday - 1) % 7));

int dayDiff(String a, String b) => _parseKey(b).difference(_parseKey(a)).inHours ~/ 24;

int levelFor(num xp) => math.max(1, ((1 + math.sqrt(1 + 4 * math.max(0, xp) / 25)) / 2).floor());
int levelFloor(int l) => 25 * l * (l - 1);
String titleFor(int l) => l - 1 < titles.length ? titles[l - 1] : 'Legend ${l - 10}';

class StreakInfo {
  const StreakInfo({this.streak = 0, this.best = 0, this.shields = 0, this.atRisk = false, this.todayMet = false});
  final int streak, best, shields;
  final bool atRisk, todayMet;
}

Map<String, int> sumByDay(List<XpRow> rows, int sh) {
  final m = <String, int>{};
  for (final r in rows) {
    final k = dayKey(r.t, sh);
    m[k] = (m[k] ?? 0) + r.xp;
  }
  return m;
}

/// A streak counts days that hit the goal; every 7th day earns a shield (up to 2) that forgives a miss.
StreakInfo streakInfo(Map<String, int> byDay, String today, double goal) {
  final keys = byDay.keys.toList()..sort();
  final todayMet = (byDay[today] ?? 0) >= goal;
  if (keys.isEmpty) return const StreakInfo();
  var streak = 0, best = 0, shields = 0;
  for (var d = keys.first; d.compareTo(today) <= 0; d = addDays(d, 1)) {
    final met = (byDay[d] ?? 0) >= goal;
    if (met) {
      streak++;
      if (streak % 7 == 0) shields = math.min(2, shields + 1);
    } else if (d != today) {
      if (shields > 0) {
        shields--;
      } else {
        streak = 0;
      }
    }
    best = math.max(best, streak);
  }
  return StreakInfo(streak: streak, best: best, shields: shields, atRisk: streak > 0 && !todayMet, todayMet: todayMet);
}

/// How many quests in a row were logged, each within [windowMs] of the next.
int comboChain(List<XpRow> earn, int now, int windowMs) {
  var n = 0, ref = now;
  for (var i = earn.length - 1; i >= 0; i--) {
    if (ref - earn[i].t <= windowMs) {
      n++;
      ref = earn[i].t;
    } else {
      break;
    }
  }
  return n;
}

Map<String, int> countsOn(List<XpRow> rows, String day, int sh) {
  final c = <String, int>{};
  for (final r in rows) {
    if (dayKey(r.t, sh) != day) continue;
    c[r.q] = (c[r.q] ?? 0) + (r.kind == 'undo' ? -1 : 1);
  }
  return c;
}

int netCount(List<XpRow> rows, String id) => rows.where((r) => r.q == id).fold(0, (n, r) => n + (r.kind == 'undo' ? -1 : 1));

Map<String, int> weekTotals(Map<String, int> byDay) {
  final w = <String, int>{};
  byDay.forEach((k, v) => w[weekStartKey(k)] = (w[weekStartKey(k)] ?? 0) + v);
  return w;
}

const badgeList = [
  ('first', 'First Blood', 'Log your first quest'),
  ('roll3', 'On a Roll', 'Hit the daily goal 3 days running'),
  ('week7', 'Week Warrior', '7-day streak'),
  ('century', 'Century', '100 XP in one day'),
  ('fullweek', 'Full Week', 'Hit the weekly goal'),
  ('ahead', 'Ahead of the Clock', 'Submit 5 things before the personal deadline'),
  ('tamer', 'Timer Tamer', 'Finish 10 timer sessions'),
  ('comeback', 'Comeback Kid', 'Log again after 2 quiet days'),
  ('boss', 'Boss Slayer', 'Beat a boss fight'),
];

Set<String> earnedBadges(List<XpRow> rows, Map<String, int> byDay, StreakInfo info, double weeklyGoal) {
  final days = byDay.keys.toList()..sort();
  var comeback = false;
  for (var i = 1; i < days.length; i++) {
    if (dayDiff(days[i - 1], days[i]) >= 3) {
      comeback = true;
      break;
    }
  }
  final best = byDay.values.fold(0, math.max);
  final wk = weekTotals(byDay).values.fold(0, math.max);
  return {
    if (rows.isNotEmpty) 'first',
    if (info.best >= 3) 'roll3',
    if (info.best >= 7) 'week7',
    if (best >= 100) 'century',
    if (wk >= weeklyGoal) 'fullweek',
    if (netCount(rows, 'early') >= 5) 'ahead',
    if (netCount(rows, 'timer') >= 10) 'tamer',
    if (comeback) 'comeback',
    if (netCount(rows, 'boss') >= 1) 'boss',
  };
}

/// Everything the Quest Log shows, worked out from the log at one moment.
class QuestModel {
  QuestModel(this.rows, this.settings, int now)
      : today = dayKey(now, settings.dayStartHour),
        earn = rows.where((r) => r.kind != 'undo').toList() {
    total = rows.fold(0, (a, r) => a + r.xp);
    byDay = sumByDay(rows, settings.dayStartHour);
    info = streakInfo(byDay, today, settings.dailyGoal);
    level = levelFor(total);
    floor = levelFloor(level);
    next = levelFloor(level + 1);
    windowMs = (settings.comboMinutes * 60000).round();
    final chain = comboChain(earn, now, windowMs);
    comboLevel = math.min(5, chain);
    multiplier = 1 + 0.1 * comboLevel;
    final last = earn.isEmpty ? 0 : earn.last.t;
    comboLeftMs = chain > 0 ? math.max(0, windowMs - (now - last)) : 0;
    todayXp = byDay[today] ?? 0;
    weekXp = weekTotals(byDay)[weekStartKey(today)] ?? 0;
    counts = countsOn(rows, today, settings.dayStartHour);
  }
  final List<XpRow> rows;
  final List<XpRow> earn;
  final XpSettings settings;
  final String today;
  late final int total, level, floor, next, windowMs, comboLevel, comboLeftMs, todayXp, weekXp;
  late final Map<String, int> byDay, counts;
  late final StreakInfo info;
  late final double multiplier;
}

class XpRepository {
  XpRepository(this.sheets);
  final SheetsApi sheets;

  Future<({List<Quest> quests, List<XpRow> log, XpSettings settings})> load() async {
    final r = await Future.wait([sheets.get('Quests!A2:F80'), sheets.get('Log!A2:H20000'), sheets.get('Settings!A2:B30')]);
    final quests = parseQuests(r[0]);
    return (quests: quests.isEmpty ? defaultQuests : quests, log: [for (final x in r[1]) ?XpRow.fromSheet(x)], settings: XpSettings.parse(r[2]));
  }

  Future<void> append(List<XpRow> rows, int dayStartHour) => sheets.append('Log!A1', [for (final r in rows) r.toSheet(dayStartHour)]);
}

/// The row to log when [q] is done now: the combo multiplier, doubled on a crit.
XpRow questRow(Quest q, QuestModel m, int now, {required bool crit}) {
  final mult = ((m.multiplier * (crit ? 2 : 1)) * 100).round() / 100;
  return XpRow(t: now, q: q.id, name: q.name, base: q.xp.toDouble(), mult: mult, xp: (q.xp * mult).round(), kind: q.cat == 'Boss' ? 'boss' : 'quest');
}

/// The latest logged row that has not already been undone, or null.
XpRow? lastUndoable(List<XpRow> rows) {
  final seen = <String, int>{};
  for (var i = rows.length - 1; i >= 0; i--) {
    final r = rows[i];
    if (r.kind == 'undo') {
      seen[r.q] = (seen[r.q] ?? 0) + 1;
    } else if ((seen[r.q] ?? 0) > 0) {
      seen[r.q] = seen[r.q]! - 1;
    } else {
      return r;
    }
  }
  return null;
}

XpRow undoRow(XpRow r, int now) => XpRow(t: now, q: r.q, name: r.name, base: r.base, mult: r.mult, xp: -r.xp, kind: 'undo');
