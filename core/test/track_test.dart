import 'package:flutter_test/flutter_test.dart';
import 'package:next_up_core/hours.dart';
import 'package:next_up_core/sheets.dart';
import 'package:next_up_core/track.dart';

class FakeSheets implements SheetsApi {
  final Map<String, List<List<String>>> data = {};
  final List<String> writes = [];
  final List<String> tabNames = ['Dashboard', 'Log', 'Tracked'];
  int nextRow = 4;
  @override
  Future<List<List<String>>> get(String range) async => data[range] ?? [];
  @override
  Future<void> putRaw(String range, List<List<String>> values) async => writes.add('$range ${values.first.join('|')}');
  @override
  Future<void> put(String range, List<List<Object>> values) async => writes.add('$range ${values.first.join('|')}');
  @override
  Future<int> append(String range, List<List<String>> values) async {
    writes.add('append ${values.first.join('|')}');
    return nextRow++;
  }
  @override
  Future<List<String>> tabs() async => tabNames;
  @override
  Future<void> addTab(String title) async => tabNames.add(title);
}

void main() {
  final now = DateTime(2026, 10, 10, 15);
  String iso(int h, [int m = 0]) => DateTime(2026, 10, 10, h, m).toUtc().toIso8601String();

  test('loads blocks, targets and categories, and finds the running block', () async {
    final s = FakeSheets();
    s.data['Tracked!A2:E5000'] = [
      [iso(9), iso(10), 'Class', '', 'a'],
      [iso(14), '', 'Study', 'pomodoro', 'b'],
      ['not a date', '', 'Junk', '', 'c'],
    ];
    s.data['Tracked!G2:I60'] = [['Study', '2', '10']];
    s.data['Dashboard!D24:F40'] = [['Type', 'Planned', 'Done'], ['Class'], ['Buffer']];
    final d = await SheetsTrackRepository(s).load();
    expect(d.blocks.map((b) => b.cat), ['Class', 'Study']);
    expect(d.running?.id, 'b');
    expect(d.targetFor('study')?.day, 2);
    expect(d.categories.take(1), ['Class']);
    expect(d.totals(DateTime(2026, 10, 10), DateTime(2026, 10, 11), now)['Class'], const Duration(hours: 1));
    expect(d.totals(DateTime(2026, 10, 10), DateTime(2026, 10, 11), now)['Study'], const Duration(hours: 1));
  });

  test('starting a category stops the running one at the same moment', () async {
    final s = FakeSheets();
    s.data['Tracked!A2:E5000'] = [[iso(14), '', 'Study', '', 'b']];
    final repo = SheetsTrackRepository(s);
    final d = await repo.load();
    await repo.start(d, 'Homework', '', now);
    expect(s.writes.first, startsWith('Tracked!B2 '));
    expect(s.writes.last, startsWith('append '));
    expect(d.running?.cat, 'Homework');
    expect(d.running?.row, 4);
  });

  test('weeks start on Sunday', () {
    expect(weekStart(DateTime(2026, 10, 10)), DateTime(2026, 10, 4));
    expect(weekStart(DateTime(2026, 10, 4, 12)), DateTime(2026, 10, 4));
  });

  test('parses the dashboard summary', () {
    final dash = List.generate(21, (_) => List.filled(10, ''));
    dash[1][1] = '82%';
    dash[2][1] = '70%';
    dash[4][1] = '2.5';
    dash[8][1] = '10';
    dash[9][1] = '6';
    dash[1][3] = 'Chem';
    dash[1][7] = '4';
    dash[1][8] = '3';
    dash[9][3] = 'Sat Oct 10';
    dash[9][5] = '5';
    dash[9][6] = '4';
    dash[9][7] = '3';
    final h = HoursSummary.parse(dash, [['Class', '10', '8']]);
    expect(h.timeAdherence, 82);
    expect(h.courses.single.fraction, 0.75);
    expect(h.days.single.rated, isTrue);
    expect(h.types.single.done, 8);
  });

  test('lists unrated blocks from the last two days, newest first', () {
    String d(int off) => DateTime(2026, 10, 10 + off).toIso8601String().substring(0, 10);
    final log = [
      [d(0), '', '9:00 AM', '10:00 AM', 'Chem', '', 'Class', '1', ''],
      [d(0), '', '11:00 AM', '12:00 PM', 'Math', '', 'Class', '1', 'DONE'],
      [d(0), '', '5:00 PM', '6:00 PM', 'Future', '', 'Class', '1', ''],
      [d(-5), '', '9:00 AM', '10:00 AM', 'Old', '', 'Class', '1', ''],
    ];
    final r = blocksToRate(log, now);
    expect(r.map((b) => b.name), ['Chem']);
    expect(r.single.row, 2);
  });
}
