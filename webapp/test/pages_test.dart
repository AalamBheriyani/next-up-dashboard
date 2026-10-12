import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_up_core/ask_claude.dart';
import 'package:next_up_core/hours.dart';
import 'package:next_up_core/track.dart';
import 'package:next_up_core/worker_api.dart';
import 'package:next_up_web/dashboard/track_panel.dart';
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

  testWidgets('the dashboard Track panel starts and stops blocks', (tester) async {
    await big(tester);
    final track = FakeTrack(data());
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: TrackPanel(repo: track, now: () => now))));
    await tester.pump();
    expect(find.text('1:00:00'), findsOneWidget);
    await tester.tap(find.text('Homework').first);
    await tester.pump();
    await tester.tap(find.text('Stop'));
    await tester.pump();
    expect(track.calls, ['start Homework', 'stop']);
    await tester.pumpWidget(const SizedBox()); // stops its timers
  });

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

  testWidgets('Rate with Claude proposes statuses and Apply writes the ticked ones', (tester) async {
    await big(tester);
    final dash = List.generate(21, (_) => List.filled(10, ''));
    dash[1][1] = '82%';
    final log = [
      ['2026-10-10', '', '9:00 AM', '10:00 AM', 'Chem class', '', 'Class', '1', ''],
    ];
    final sheets = FakeSheetsForHours(dash, log);
    final ask = AskService(transport: _Claude('{"reply": "Chem went fine.", "ratings": [{"row": 2, "status": "DONE"}]}'), mode: AskMode.api);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: AdherenceScreen(services: fakeServices(hours: HoursRepository(sheets)), config: const AppConfig(sheetId: 's'), now: () => now, ask: ask))));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.enterText(find.byType(TextField).first, 'did chem'); // above the Partial hours fields
    await tester.tap(find.text('Rate'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Chem went fine.'), findsOneWidget);
    await tester.tap(find.text('Apply to Time Tracker'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(sheets.writes, ['Log!I2:J2 DONE|']);
  });

  testWidgets('any accent colour can be picked and saved', (tester) async {
    await big(tester);
    final cfg = FakeConfig();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SettingsScreen(services: fakeServices(config: cfg), config: const AppConfig(email: 'a@b.c'), onSaved: (_) {}, onSignOut: () {}))));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byTooltip('Pick any colour'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Hex'), '#123abc');
    await tester.tap(find.text('Use it'));
    await tester.pumpAndSettle();
    expect(cfg.savedAccents, ['#123abc']);
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

class _Claude implements AskTransport {
  _Claude(this.answer);
  final String answer;
  @override
  Future<Map<String, dynamic>> claude(Map<String, dynamic> body) async => {
        'content': [{'type': 'text', 'text': answer}],
      };
  @override
  Future<bool> relayOnline() async => false;
  @override
  Future<String> relayAsk(String prompt) async => '';
  @override
  Future<Map<String, dynamic>> relayAnswer(String id) async => {};
}
