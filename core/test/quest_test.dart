import 'package:flutter_test/flutter_test.dart';
import 'package:next_up_core/quest.dart';

int ms(int d, int h, [int m = 0]) => DateTime(2026, 10, d, h, m).millisecondsSinceEpoch;
XpRow row(int t, int xp, {String q = 'start', String kind = 'quest'}) => XpRow(t: t, q: q, name: q, base: xp.toDouble(), mult: 1, xp: xp, kind: kind);

void main() {
  quest2();
  test('levels and titles', () {
    expect(levelFor(0), 1);
    expect(levelFor(50), 2); // level 2 starts at 50 XP
    expect(levelFloor(2), 50);
    expect(levelFor(150), 3);
    expect(titleFor(1), 'Rookie');
    expect(titleFor(12), 'Legend 2');
  });

  test('the day rolls over at the start hour', () {
    expect(dayKey(ms(10, 2), 4), '2026-10-09'); // 2 AM still counts for yesterday
    expect(dayKey(ms(10, 5), 4), '2026-10-10');
    expect(weekStartKey('2026-10-10'), '2026-10-05'); // Monday
    expect(addDays('2026-10-31', 1), '2026-11-01');
  });

  test('streaks need the goal each day, shields forgive a miss after 7', () {
    final byDay = {for (var i = 0; i < 8; i++) '2026-10-0${1 + i}': 60, '2026-10-09': 0, '2026-10-10': 60};
    final info = streakInfo(byDay, '2026-10-10', 60);
    expect(info.best, 9);
    expect(info.shields, 0); // the shield from day 7 was spent on the miss on the 9th
    expect(info.streak, 9); // the miss on the 9th was forgiven
    final broken = streakInfo({'2026-10-01': 60, '2026-10-04': 60}, '2026-10-04', 60);
    expect(broken.streak, 1);
    expect(streakInfo({'2026-10-03': 20}, '2026-10-04', 60).atRisk, isFalse);
  });

  test('combo chain counts quests logged within the window', () {
    final earn = [row(ms(10, 9), 10), row(ms(10, 9, 20), 10), row(ms(10, 9, 40), 10)];
    expect(comboChain(earn, ms(10, 9, 50), 45 * 60000), 3);
    expect(comboChain(earn, ms(10, 12), 45 * 60000), 0);
  });

  test('model totals, today counts and undo', () {
    final rows = [row(ms(10, 9), 10), row(ms(10, 9, 5), 15, q: 'timer'), row(ms(10, 9, 6), -15, q: 'timer', kind: 'undo')];
    final m = QuestModel(rows, const XpSettings(), ms(10, 9, 10));
    expect(m.total, 10);
    expect(m.counts['timer'], 0);
    expect(m.counts['start'], 1);
    expect(m.todayXp, 10);
    expect(m.comboLevel, 2); // the undo is not counted
    expect(m.multiplier, closeTo(1.2, 1e-9));
  });

  test('badges', () {
    final rows = [for (var i = 0; i < 5; i++) row(ms(1 + i, 10), 30, q: 'early'), row(ms(6, 10), 100, q: 'boss', kind: 'boss')];
    final byDay = sumByDay(rows, 4);
    final info = streakInfo(byDay, '2026-10-06', 30);
    final b = earnedBadges(rows, byDay, info, 500);
    expect(b, containsAll(['first', 'roll3', 'ahead', 'boss', 'century']));
    expect(b.contains('tamer'), isFalse);
  });

  test('parses sheet rows and writes them back in the same shape', () {
    final r = XpRow.fromSheet(['${ms(10, 9)}', '2026-10-10', 'timer', 'Finished a timer session', '15', '1.1', '17', 'auto'])!;
    expect(r.xp, 17);
    expect(r.kind, 'auto');
    expect(r.toSheet(4)[1], '2026-10-10');
    expect(XpRow.fromSheet(['0', '', 'x']), isNull);
    expect(parseQuests([['a', 'Quest A', 'Focus', '20', '2', 'FALSE'], ['b', 'Quest B']]).map((q) => q.id), ['b']);
    expect(XpSettings.parse([['daily_goal', '80'], ['bogus', '1']]).dailyGoal, 80);
  });
}

void quest2() {
  test('crit doubles the multiplier, undo skips rows already undone', () {
    final m = QuestModel([], const XpSettings(), ms(10, 9));
    final r = questRow(defaultQuests.first, m, ms(10, 9), crit: true);
    expect((r.mult, r.xp), (2.0, 20));
    final a = row(1, 10, q: 'a'), b = row(2, 15, q: 'b'), u = undoRow(b, 3);
    expect(lastUndoable([a, b, u]), a);
    expect(lastUndoable([a, b]), b);
    expect(lastUndoable([a, b, u, undoRow(a, 4)]), isNull);
  });
}
