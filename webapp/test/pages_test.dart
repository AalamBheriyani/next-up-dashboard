import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_up_core/hours.dart';
import 'package:next_up_core/track.dart';
import 'package:next_up_core/worker_api.dart';
import 'package:next_up_web/pages/adherence_screen.dart';
import 'package:next_up_web/pages/settings_screen.dart';
import 'package:next_up_web/pages/track_screen.dart';

import 'fakes.dart';

void main() {
  final now = DateTime(2026, 10, 10, 15);
  TrackData data() => TrackData(
        blocks: [
          TrackBlock(row: 2, start: DateTime(2026, 10, 10, 9), end: DateTime(2026, 10, 10, 10, 30), cat: 'Class', id: 'a'),
          TrackBlock(row: 3, start: DateTime(2026, 10, 10, 14), cat: 'Study', id: 'b'),
        ],
        targets: [const TrackTarget('Class', day: 1)],
        sheetCategories: ['Class', 'Study', 'Homework'],
      );

  Future<void> big(WidgetTester t) async {
    t.view.physicalSize = const Size(1300, 1400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
  }

  testWidgets('Track shows the running block, switches category and stops', (tester) async {
    await big(tester);
    final track = FakeTrack(data());
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: TrackScreen(services: fakeServices(track: track), config: const AppConfig(sheetId: 's'), now: () => now))));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Study'), findsWidgets);
    expect(find.text('1:00:00'), findsOneWidget); // running since 14:00, now 15:00
    await tester.tap(find.text('Homework').first);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(track.calls, ['start Homework']);
    await tester.tap(find.text('Stop'));
    await tester.pump();
    expect(track.calls.last, 'stop');
  });

  testWidgets('Track without a sheet asks for one', (tester) async {
    await big(tester);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: TrackScreen(services: fakeServices(), config: const AppConfig(), now: () => now))));
    await tester.pump();
    expect(find.textContaining('Add your Time Tracker sheet'), findsOneWidget);
  });

  testWidgets('Adherence shows the summary and rates a block', (tester) async {
    await big(tester);
    final dash = List.generate(21, (_) => List.filled(10, ''));
    dash[1][1] = '82%';
    dash[1][3] = 'Chem';
    dash[1][7] = '4';
    dash[1][8] = '3';
    final log = [
      ['2026-10-10', '', '9:00 AM', '10:00 AM', 'Chem class', '', 'Class', '1', ''],
    ];
    final sheets = FakeSheetsForHours(dash, log);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: AdherenceScreen(services: fakeServices(hours: HoursRepository(sheets)), config: const AppConfig(sheetId: 's'), now: () => now))));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('82%'), findsOneWidget);
    expect(find.text('Chem'), findsOneWidget);
    expect(find.text('Chem class'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(sheets.writes, ['Log!I2:J2 DONE|']);
  });

  test('sheetIdFrom accepts links and ids', () {
    const id = '1lxnTxm9qe5P-HsN0N-ZK5tXFo0lumgyuEfHjhxgYQog';
    expect(sheetIdFrom('https://docs.google.com/spreadsheets/d/$id/edit#gid=0'), id);
    expect(sheetIdFrom(id), id);
    expect(sheetIdFrom(''), '');
    expect(sheetIdFrom('not a sheet'), isNull);
  });

  testWidgets('Settings saves pasted sheet links', (tester) async {
    await big(tester);
    final cfg = FakeConfig();
    AppConfig? saved;
    const id = '1lxnTxm9qe5P-HsN0N-ZK5tXFo0lumgyuEfHjhxgYQog';
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SettingsScreen(services: fakeServices(config: cfg), config: const AppConfig(email: 'a@b.c'), onSaved: (c) => saved = c, onSignOut: () {}))));
    await tester.pump(const Duration(seconds: 1));
    await tester.enterText(find.byType(TextField).first, 'https://docs.google.com/spreadsheets/d/$id/edit');
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(cfg.saved, ['$id|']);
    expect(saved?.sheetId, id);
  });
}
