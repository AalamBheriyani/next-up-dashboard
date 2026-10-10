import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_up_core/worker_api.dart';
import 'package:next_up_web/pages/quest_screen.dart';

import 'fakes.dart';

void main() {
  final now = DateTime(2026, 10, 10, 15);

  Future<void> pump(WidgetTester t, FakeXp xp, {String sheet = 'xp'}) async {
    t.view.physicalSize = const Size(1300, 1800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(home: Scaffold(body: QuestScreen(services: fakeServices(xp: xp), config: AppConfig(sheetId: 's', questSheetId: sheet), now: () => now, random: Random(1)))));
    await t.pump(const Duration(seconds: 1));
  }

  testWidgets('tapping a quest logs XP to the sheet, undo reverses it', (tester) async {
    final xp = FakeXp();
    await pump(tester, xp);
    await tester.tap(find.text('Daily Planning done'));
    await tester.pump(const Duration(seconds: 1));
    expect(xp.appended.single.q, 'plan');
    expect(xp.appended.single.xp, greaterThanOrEqualTo(15));
    await tester.tap(find.text('Undo last'));
    await tester.pump(const Duration(seconds: 1));
    expect(xp.appended.last.kind, 'undo');
    expect(xp.appended.last.xp, -xp.appended.first.xp);
  });

  testWidgets('asks for the XP sheet when none is set', (tester) async {
    await pump(tester, FakeXp(), sheet: '');
    expect(find.textContaining('XP Tracker sheet'), findsOneWidget);
  });
}
