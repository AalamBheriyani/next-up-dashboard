import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_up_core/anki.dart';
import 'package:next_up_core/quest.dart';
import 'package:next_up_core/worker_api.dart';
import 'package:next_up_web/dashboard/anki_panel.dart';
import 'package:next_up_web/dashboard/habits_panel.dart';
import 'package:next_up_web/dashboard/heat_grid.dart';
import 'package:next_up_web/dashboard/links_panel.dart';

import 'fakes.dart';

class _Anki implements AnkiSource {
  int loads = 0;
  @override
  Future<AnkiStats?> load() async {
    loads++;
    return const AnkiStats(decks: [AnkiDeck('Chem', 5, 2, 10), AnkiDeck('Empty', 0, 0, 0)], days: {'2026-10-10': 40, '2026-10-09': 20});
  }
}

void main() {
  final now = DateTime(2026, 10, 10, 15);

  test('heat summary counts the streak back from today', () {
    final s = HeatSummary({'2026-10-10': 2, '2026-10-09': 1, '2026-10-07': 3}, now);
    expect((s.total, s.days, s.streak), (6, 3, 2));
    // Nothing yet today: yesterday's streak still stands.
    expect(HeatSummary({'2026-10-09': 1, '2026-10-08': 1}, now).streak, 2);
  });

  testWidgets('the heat grid fills a wide panel and shows fewer weeks on a narrow one', (tester) async {
    Future<int> cellsAt(double width) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: SizedBox(width: width, child: HeatGrid(counts: const {'2026-10-10': 3}, today: now))))));
      return find.byType(Tooltip).evaluate().length;
    }

    expect(await cellsAt(1200), greaterThan(53 * 7 - 7)); // a full year
    expect(await cellsAt(300), lessThan(30 * 7));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Anki shows total due and only decks with cards', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: AnkiPanel(source: _Anki(), now: () => now))));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('17'), findsOneWidget);
    expect(find.textContaining('Chem'), findsOneWidget);
    expect(find.textContaining('Empty'), findsNothing);
  });

  testWidgets('Habits counts only habit quests', (tester) async {
    final log = [
      XpRow(t: DateTime(2026, 10, 10, 9).millisecondsSinceEpoch, q: 'plan', name: 'Daily Planning done', base: 15, mult: 1, xp: 15, kind: 'quest'),
      XpRow(t: DateTime(2026, 10, 10, 9).millisecondsSinceEpoch, q: 'start', name: 'x', base: 10, mult: 1, xp: 10, kind: 'quest'),
    ];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: HabitsPanel(repo: FakeXp(log), now: () => now))));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.textContaining('1 habit check-in on 1 days'), findsOneWidget);
  });

  testWidgets('Anki and Habits reload from their own refresh buttons', (tester) async {
    final anki = _Anki();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: AnkiPanel(source: anki, now: () => now))));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byTooltip('Refresh Anki'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(anki.loads, 2);

    final xp = FakeXp();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: HabitsPanel(repo: xp, now: () => now))));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byTooltip('Refresh habits'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(xp.loads, 2);
  });

  testWidgets('Jump to lists TickTick, Calendar, your sheets and the owner\'s links, and opens them', (tester) async {
    final opened = <Uri>[];
    const cfg = AppConfig(sheetId: 'abc', links: [QuickLink('Notion', 'https://notion.so')]);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: LinksPanel(links: quickLinks(cfg), open: opened.add))));
    expect(find.text('TickTick'), findsOneWidget);
    expect(find.text('Time Tracker'), findsOneWidget);
    expect(find.text('XP Tracker'), findsNothing);
    await tester.tap(find.text('Notion'));
    expect(opened.single.toString(), 'https://notion.so');
  });
}
