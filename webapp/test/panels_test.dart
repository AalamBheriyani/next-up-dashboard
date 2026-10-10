import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_up_core/anki.dart';
import 'package:next_up_core/quest.dart';
import 'package:next_up_web/dashboard/anki_panel.dart';
import 'package:next_up_web/dashboard/habits_panel.dart';
import 'package:next_up_web/dashboard/heat_grid.dart';

import 'fakes.dart';

class _Anki implements AnkiSource {
  @override
  Future<AnkiStats?> load() async => const AnkiStats(decks: [AnkiDeck('Chem', 5, 2, 10), AnkiDeck('Empty', 0, 0, 0)], days: {'2026-10-10': 40, '2026-10-09': 20});
}

void main() {
  final now = DateTime(2026, 10, 10, 15);

  test('heat summary counts the streak back from today', () {
    final s = HeatSummary({'2026-10-10': 2, '2026-10-09': 1, '2026-10-07': 3}, now);
    expect((s.total, s.days, s.streak), (6, 3, 2));
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
}
