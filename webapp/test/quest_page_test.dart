import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_up_core/quest.dart';
import 'package:next_up_core/worker_api.dart';
import 'package:next_up_web/platform/platform_base.dart';
import 'package:next_up_web/pages/quest_screen.dart';

import 'fakes.dart';

void main() {
  final now = DateTime(2026, 10, 10, 15);

  Future<void> pump(WidgetTester t, FakeXp xp, {String sheet = 'xp', LocalStore? store, void Function(List<double>)? beep}) async {
    t.view.physicalSize = const Size(1300, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(home: Scaffold(body: QuestScreen(services: fakeServices(xp: xp, store: store, beep: beep), config: AppConfig(sheetId: 's', questSheetId: sheet), now: () => now, random: Random(1)))));
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

  testWidgets('a quest makes a sound, undo is silent, and the sound switch is remembered', (tester) async {
    final beeps = <List<double>>[];
    final store = MemoryStore();
    await pump(tester, FakeXp(), store: store, beep: beeps.add);
    await tester.tap(find.text('Daily Planning done').first);
    await tester.pump(const Duration(seconds: 1));
    expect(beeps, hasLength(1));
    await tester.tap(find.text('Undo last'));
    await tester.pump(const Duration(seconds: 1));
    expect(beeps, hasLength(1));
    await tester.tap(find.byTooltip('Turn sound off'));
    await tester.pump();
    expect(store.get('nu.web.mute'), '1');
    await tester.tap(find.text('Daily Planning done').first);
    await tester.pump(const Duration(seconds: 1));
    expect(beeps, hasLength(1));
  });

  testWidgets('crossing the daily goal shows a toast', (tester) async {
    final earlier = XpRow(t: now.subtract(const Duration(hours: 1)).millisecondsSinceEpoch, q: 'other', name: 'Earlier', base: 50, mult: 1, xp: 50, kind: 'quest');
    await pump(tester, FakeXp([earlier]));
    await tester.tap(find.text('Daily Planning done').first);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Daily goal hit. Streak is safe.'), findsOneWidget);
  });

  testWidgets('XP that fails to save waits on the device and goes up on Retry, even after a reload', (tester) async {
    final xp = FakeXp()..offline = true;
    final store = MemoryStore();
    await pump(tester, xp, store: store);
    await tester.tap(find.text('Daily Planning done'));
    await tester.pump(const Duration(seconds: 1));
    expect(xp.appended, isEmpty);
    expect(find.text('1 not saved yet · Retry'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await pump(tester, xp, store: store);
    expect(find.text('1 not saved yet · Retry'), findsOneWidget, reason: 'the queue survives a reload');
    xp.offline = false;
    await tester.tap(find.text('1 not saved yet · Retry'));
    await tester.pump(const Duration(seconds: 1));
    expect(xp.appended.single.q, 'plan');
    expect(find.textContaining('not saved yet'), findsNothing);
  });
}
