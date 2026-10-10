import 'package:next_up_core/calendar.dart';
import 'package:next_up_core/deadline.dart';
import 'package:next_up_core/deadline_source.dart';
import 'package:next_up_core/hours.dart';
import 'package:next_up_core/quest.dart';
import 'package:next_up_core/sheets.dart';
import 'package:next_up_core/track.dart';
import 'package:next_up_core/worker_api.dart';
import 'package:next_up_web/services.dart';

class FakeDeadlines implements DeadlineSource {
  FakeDeadlines([this.items = const []]);
  final List<Deadline> items;
  @override
  Future<List<Deadline>> load() async => items;
  @override
  Future<void> complete(Deadline d) async {}
}

class FakeCalendar implements CalendarSource {
  FakeCalendar([this.events = const []]);
  final List<CalendarEvent> events;
  @override
  Future<List<CalendarEvent>> load(DateTime from, DateTime to) async => events;
}

class FakeConfig implements ConfigSource {
  FakeConfig([this.config = const AppConfig(email: 'a@b.c', sheetId: 'sheet')]);
  AppConfig config;
  final saved = <String>[];
  @override
  Future<AppConfig> load() async => config;
  @override
  Future<void> save({String? sheetId, String? questSheetId, String? accent, bool? redDeadlines}) async {
    saved.add('$sheetId|$questSheetId');
    config = AppConfig(email: config.email, sheetId: sheetId ?? config.sheetId, questSheetId: questSheetId ?? config.questSheetId);
  }
}

class FakeTrack implements TrackRepository {
  FakeTrack(this.data);
  final TrackData data;
  final calls = <String>[];
  @override
  Future<TrackData> load() async => data;
  @override
  Future<void> start(TrackData d, String cat, String note, DateTime now) async {
    calls.add('start $cat');
    d.running?.end = now;
    d.blocks.add(TrackBlock(row: 9, start: now, cat: cat, id: 'n'));
  }
  @override
  Future<void> stop(TrackData d, DateTime now) async {
    calls.add('stop');
    d.running?.end = now;
  }
  @override
  Future<void> add(TrackData d, TrackBlock b) async => d.blocks.add(b);
  @override
  Future<void> update(TrackData d, TrackBlock b) async {}
  @override
  Future<void> delete(TrackData d, TrackBlock b) async => d.blocks.remove(b);
  @override
  Future<void> saveTargets(TrackData d, List<TrackTarget> targets) async => d.targets = targets;
}

class FakeSheetsForHours implements SheetsApi {
  FakeSheetsForHours(this.dash, this.log);
  final List<List<String>> dash;
  final List<List<String>> log;
  final writes = <String>[];
  @override
  Future<List<List<String>>> get(String range) async => range.startsWith('Dashboard!A1') ? dash : range.startsWith('Log!') ? log : [];
  @override
  Future<void> putRaw(String range, List<List<String>> values) async {}
  @override
  Future<void> put(String range, List<List<Object>> values) async => writes.add('$range ${values.first.join('|')}');
  @override
  Future<int> append(String range, List<List<String>> values) async => 0;
  @override
  Future<List<String>> tabs() async => [];
  @override
  Future<void> addTab(String title) async {}
}

Services fakeServices({bool signedIn = true, FakeTrack? track, HoursRepository? hours, XpRepository? xp, FakeConfig? config, List<Deadline> deadlines = const [], List<CalendarEvent> events = const []}) => Services(
      config: config ?? FakeConfig(),
      deadlines: FakeDeadlines(deadlines),
      calendar: FakeCalendar(events),
      signedIn: () => signedIn,
      signIn: () async {},
      trackFactory: track == null ? null : (_) => track,
      hoursFactory: hours == null ? null : (_) => hours,
      xpFactory: xp == null ? null : (_) => xp,
    );

class FakeXp extends XpRepository {
  FakeXp([this.log = const []]) : super(FakeSheetsForHours(const [], const []));
  final List<XpRow> log;
  final appended = <XpRow>[];
  @override
  Future<({List<Quest> quests, List<XpRow> log, XpSettings settings})> load() async => (quests: defaultQuests, log: log, settings: const XpSettings());
  @override
  Future<void> append(List<XpRow> rows, int dayStartHour) async => appended.addAll(rows);
}
