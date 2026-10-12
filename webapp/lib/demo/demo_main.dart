// A local preview of the site with made-up data, for checking layout and motion without signing in.
// Build it with `flutter build web -t lib/demo/demo_main.dart`; the real site never imports this file.
import 'package:flutter/material.dart';
import 'package:next_up_core/anki.dart';
import 'package:next_up_core/ask_claude.dart';
import 'package:next_up_core/board_layout.dart';
import 'package:next_up_core/calendar.dart';
import 'package:next_up_core/deadline.dart';
import 'package:next_up_core/deadline_source.dart';
import 'package:next_up_core/hours.dart';
import 'package:next_up_core/quest.dart';
import 'package:next_up_core/sheets.dart';
import 'package:next_up_core/track.dart';
import 'package:next_up_core/worker_api.dart';

import '../main.dart';
import '../services.dart';


void main() {
  final now = DateTime.now();
  DateTime at(int dayOffset, int h, [int m = 0]) => DateTime(now.year, now.month, now.day + dayOffset, h, m);
  var n = 0;
  Deadline dl(String title, DateTime due, {int p = 0, String list = 'School', bool allDay = false, String notes = ''}) =>
      Deadline(id: '${n++}', projectId: list, title: title, due: due, allDay: allDay, priority: p, list: list, notes: notes);
  final deadlines = _Deadlines([
    dl('Physics lab report', at(-1, 17), p: 5, notes: 'Real deadline: Friday 9am. Write up method and results; graphs from Tuesday.'),
    dl('Reply to club email', at(-2, 12), list: 'Personal'),
    dl('Chem quiz revision', now.add(const Duration(hours: 3)), p: 5),
    dl('Maths problem set 4', at(0, 23, 59), p: 3, allDay: true),
    dl('Book dentist', at(1, 10), p: 1, list: 'Personal'),
    dl('English essay draft', at(2, 9), p: 3),
    dl('Molar mass worksheet', at(3, 15), p: 3),
    dl('History reading ch. 5', at(5, 18), p: 1),
    dl('Biology flashcards', at(6, 20)),
    dl('Uni application statement', at(12, 9), p: 5, list: 'Goals'),
    dl('Learn 20 Spanish words', at(20, 9), list: 'Goals'),
    for (var i = 1; i <= 8; i++) dl('Later task $i', at(8 + i, 12), list: i.isEven ? 'School' : 'Personal'),
  ]);
  final events = [
    CalendarEvent(id: 'a', title: 'Chemistry class', start: at(0, 9), end: at(0, 10, 30), allDay: false, location: 'Room 12'),
    CalendarEvent(id: 'b', title: 'Lunch with Sam', start: at(0, 12, 30), end: at(0, 13, 15), allDay: false),
    CalendarEvent(id: 'c', title: 'Maths tutoring', start: at(0, 15), end: at(0, 16), allDay: false),
    CalendarEvent(id: 'd', title: 'Piano', start: at(0, 18), end: at(0, 19), allDay: false),
    CalendarEvent(id: 'e', title: 'Mum’s birthday', start: at(0, 0), end: at(1, 0), allDay: true),
    // A planned block happening now, so the Now card and its notes show.
    CalendarEvent(
      id: 'f',
      title: 'History essay block',
      start: DateTime.now().subtract(const Duration(minutes: 20)),
      end: DateTime.now().add(const Duration(minutes: 25)),
      allDay: false,
      description: 'First step: reread the question and list three points\nDone when: intro paragraph drafted\nSources are in the History folder.',
    ),
  ];
  final track = _Track(TrackData(
    blocks: [
      TrackBlock(row: 2, start: now.subtract(const Duration(hours: 3)), end: now.subtract(const Duration(hours: 1, minutes: 40)), cat: 'Class', id: 't1'),
      TrackBlock(row: 3, start: now.subtract(const Duration(hours: 1, minutes: 30)), end: now.subtract(const Duration(minutes: 45)), cat: 'Study', note: 'chem', id: 't2'),
      TrackBlock(row: 4, start: at(-1, 14), end: at(-1, 16), cat: 'Homework', id: 't3'),
      TrackBlock(row: 5, start: now.subtract(const Duration(minutes: 37)), cat: 'Study', note: 'maths', id: 't4'),
    ],
    targets: [const TrackTarget('Study', day: 3, week: 15), const TrackTarget('Class', day: 2, week: 10)],
    sheetCategories: ['Class', 'Study', 'Homework', 'Exercise', 'Rest'],
  ));
  final dash = List.generate(21, (_) => List.filled(10, ''));
  dash[0][0] = 'This week';
  dash[1][1] = '78%';
  dash[2][1] = '71%';
  dash[4][1] = '3.5';
  dash[8][1] = '18';
  dash[9][1] = '13.5';
  for (final (i, c, p, d) in [(1, 'Chemistry', '6', '5'), (2, 'Maths', '5', '4.5'), (3, 'Physics', '4', '2'), (4, 'English', '3', '2')]) {
    dash[i][3] = c;
    dash[i][7] = p;
    dash[i][8] = d;
  }
  for (final (i, d, p, done) in [(9, 'Mon', '4', '3.5'), (10, 'Tue', '4', '4'), (11, 'Wed', '3', '1.5'), (12, 'Thu', '4', '3'), (13, 'Fri', '3', '1.5')]) {
    dash[i][3] = d;
    dash[i][5] = p;
    dash[i][6] = '1';
    dash[i][7] = done;
  }
  String ymd(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  final hoursLog = [
    [ymd(now), '', '9:00 AM', '10:30 AM', 'Chem class', '', 'Class', '1.5', ''],
    [ymd(now), '', '11:00 AM', '12:00 PM', 'Maths study', '', 'Study', '1', ''],
    [ymd(now.subtract(const Duration(days: 1))), '', '2:00 PM', '4:00 PM', 'Physics homework', '', 'Homework', '2', ''],
  ];
  final hoursSheets = _Sheets({'Dashboard!A1': dash, 'Dashboard!D24': [['Type', 'Planned', 'Done'], ['Class', '8', '7'], ['Study', '6', '4'], ['Homework', '4', '2.5']], 'Log!A2': hoursLog});
  final xpLog = <List<String>>[
    for (var d = 0; d < 40; d++)
      for (var k = 0; k < (d * 7) % 5; k++) ['${at(-d, 9 + k).millisecondsSinceEpoch}', '', defaultQuests[(d + k) % defaultQuests.length].id, defaultQuests[(d + k) % defaultQuests.length].name, '${defaultQuests[(d + k) % defaultQuests.length].xp}', '1', '${defaultQuests[(d + k) % defaultQuests.length].xp}', 'quest'],
  ];
  final xpSheets = _Sheets({'Quests!A2': [], 'Log!A2': xpLog, 'Settings!A2': []});
  final config = _Config(const AppConfig(email: 'demo@example.com', owner: true, sheetId: 'demo', questSheetId: 'demo-xp', ticktick: true, claudeApi: true));
  final services = Services(
    config: config,
    deadlines: deadlines,
    calendar: _Calendar(events),
    signedIn: () => true,
    signIn: () async {},
    trackFactory: (_) => track,
    hoursFactory: (_) => HoursRepository(hoursSheets),
    xpFactory: (_) => XpRepository(xpSheets),
    askTransport: _Ask(),
    anki: _Anki(AnkiStats(
      decks: const [AnkiDeck('Chemistry', 12, 3, 40), AnkiDeck('Spanish', 20, 0, 15), AnkiDeck('Biology', 0, 2, 8)],
      days: {for (var d = 0; d < 120; d++) ymd(now.subtract(Duration(days: d))): (d * 37) % 90},
      at: now.subtract(const Duration(minutes: 20)),
    )),
  );
  runApp(NextUpWeb(services: services));
}

class _Deadlines implements DeadlineSource, DeadlineEditor {
  _Deadlines(this.items);
  final List<Deadline> items;
  @override
  Future<List<Deadline>> load() async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return [...items];
  }

  @override
  Future<void> complete(Deadline d) async => items.removeWhere((x) => x.id == d.id);
  @override
  Future<void> update(Deadline d, {String? title, DateTime? day, int? priority}) async {
    final i = items.indexWhere((x) => x.id == d.id);
    if (i < 0) return;
    final due = day == null ? d.due : DateTime(day.year, day.month, day.day, d.due.hour, d.due.minute);
    items[i] = Deadline(id: d.id, projectId: d.projectId, title: title ?? d.title, due: due, allDay: d.allDay, priority: priority ?? d.priority, list: d.list);
  }

  @override
  Future<void> delete(Deadline d) async => items.removeWhere((x) => x.id == d.id);
  @override
  Future<void> create({required String title, DateTime? day, int priority = 0}) async {
    final due = day ?? DateTime.now();
    items.add(Deadline(id: 'new${items.length}', projectId: 'inbox', title: title, due: DateTime(due.year, due.month, due.day, 23, 59), allDay: true, priority: priority, list: 'Inbox'));
  }
}

class _Calendar implements CalendarSource {
  _Calendar(this.events);
  final List<CalendarEvent> events;
  @override
  Future<List<CalendarEvent>> load(DateTime from, DateTime to) async => [for (final e in events) if (e.end.isAfter(from) && e.start.isBefore(to)) e];
}

class _Config implements ConfigSource {
  _Config(this.config);
  AppConfig config;
  @override
  Future<AppConfig> load() async => config;
  @override
  Future<void> save({String? sheetId, String? questSheetId, String? accent, bool? redDeadlines, BoardLayout? layout, String? wake, String? windDown}) async {
    config = AppConfig(
      email: config.email,
      owner: config.owner,
      sheetId: sheetId ?? config.sheetId,
      questSheetId: questSheetId ?? config.questSheetId,
      accent: accent ?? config.accent,
      redDeadlines: redDeadlines ?? config.redDeadlines,
      ticktick: config.ticktick,
      claudeApi: config.claudeApi,
      layout: layout ?? config.layout,
      wakeMinutes: wake == null ? config.wakeMinutes : clockMinutes(wake, config.wakeMinutes),
      windDownMinutes: windDown == null ? config.windDownMinutes : clockMinutes(windDown, config.windDownMinutes),
    );
  }
}

class _Track implements TrackRepository {
  _Track(this.data);
  final TrackData data;
  @override
  Future<TrackData> load() async => data;
  @override
  Future<void> start(TrackData d, String cat, String note, DateTime now) async {
    d.running?.end = now;
    d.blocks.add(TrackBlock(row: d.blocks.length + 2, start: now, cat: cat, note: note, id: 'n${d.blocks.length}'));
  }

  @override
  Future<void> stop(TrackData d, DateTime now) async => d.running?.end = now;
  @override
  Future<void> add(TrackData d, TrackBlock b) async => d.blocks.add(b);
  @override
  Future<void> update(TrackData d, TrackBlock b) async {}
  @override
  Future<void> delete(TrackData d, TrackBlock b) async => d.blocks.remove(b);
  @override
  Future<void> saveTargets(TrackData d, List<TrackTarget> targets) async => d.targets = targets;
}

/// Answers each range by the prefix it starts with; writes are appended to the matching table.
class _Sheets implements SheetsApi {
  _Sheets(this.tables);
  final Map<String, List<List<String>>> tables;
  List<List<String>> _find(String range) => tables.entries.firstWhere((e) => range.startsWith(e.key), orElse: () => const MapEntry('', [])).value;
  @override
  Future<List<List<String>>> get(String range) async => _find(range);
  @override
  Future<void> putRaw(String range, List<List<String>> values) async {}
  @override
  Future<void> put(String range, List<List<Object>> values) async {}
  @override
  Future<int> append(String range, List<List<String>> values) async {
    final key = range.split('!').first;
    for (final e in tables.entries) {
      if (e.key.startsWith('$key!')) {
        e.value.addAll(values);
        return e.value.length;
      }
    }
    return 0;
  }

  @override
  Future<List<String>> tabs() async => const ['Dashboard', 'Log', 'Track'];
  @override
  Future<void> addTab(String title) async {}
}

class _Anki implements AnkiSource {
  _Anki(this.stats);
  final AnkiStats stats;
  @override
  Future<AnkiStats?> load() async => stats;
}

/// Answers every question with a short canned reply, after a moment, like a real round trip.
class _Ask implements AskTransport {
  @override
  Future<Map<String, dynamic>> claude(Map<String, dynamic> body) async {
    await Future<void>.delayed(const Duration(milliseconds: 900));
    // "Rate with Claude": mark the first listed block done.
    final asked = '${((body['messages'] as List).last as Map)['content']}';
    final row = RegExp(r'^(\d+) \|', multiLine: true).firstMatch(asked)?.group(1);
    if (row != null && asked.contains('time tracker')) {
      return {
        'content': [
          {'type': 'text', 'text': '{"reply": "Sounds like a solid morning.", "ratings": [{"row": $row, "status": "DONE"}]}'},
        ],
      };
    }
    return {
      'stop_reason': 'end_turn',
      'content': [
        {'type': 'text', 'text': 'Start with the Chem quiz revision: it is due in three hours. Do 25 minutes on the hardest topic first, then a 5 minute break.'},
      ],
    };
  }

  @override
  Future<bool> relayOnline() async => false;
  @override
  Future<String> relayAsk(String prompt) async => '';
  @override
  Future<Map<String, dynamic>> relayAnswer(String id) async => const {};
}
