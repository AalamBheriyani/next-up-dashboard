// The Time Tracker sheet's Dashboard tab (adherence) and Log tab (blocks to rate).
import 'dart:convert';

import 'deadline_source.dart';
import 'sheets.dart';

class HoursBar {
  const HoursBar(this.label, this.done, this.planned, {this.rated = true});
  final String label;
  final double done;
  final double planned;
  final bool rated;
  double get fraction => planned > 0 ? (done / planned).clamp(0.0, 1.0) : 0;
}

class HoursSummary {
  const HoursSummary({this.title = 'This week', this.timeAdherence, this.blocksDone, this.hoursMissed, this.uniDone = 0, this.uniPlanned = 0, this.courses = const [], this.days = const [], this.types = const []});
  final String title;
  final double? timeAdherence; // percent
  final double? blocksDone; // percent
  final double? hoursMissed;
  final double uniDone, uniPlanned;
  final List<HoursBar> courses, days, types;

  static double? _pct(String v) => double.tryParse(v.replaceAll('%', '').trim());
  static double _h(String v) => double.tryParse(v) ?? 0;

  /// [dash] is Dashboard!A1:J21 and [types] is Dashboard!D24:F40, as the site reads them.
  factory HoursSummary.parse(List<List<String>> dash, List<List<String>> types) {
    String g(int r, int c) => r < dash.length && c < dash[r].length ? dash[r][c] : '';
    return HoursSummary(
      title: g(0, 0).isEmpty ? 'This week' : g(0, 0),
      timeAdherence: _pct(g(1, 1)),
      blocksDone: _pct(g(2, 1)),
      hoursMissed: double.tryParse(g(4, 1)),
      uniDone: _h(g(9, 1)),
      uniPlanned: _h(g(8, 1)),
      courses: [
        for (var r = 1; r <= 5; r++)
          if (g(r, 3).isNotEmpty) HoursBar(g(r, 3), _h(g(r, 8)), _h(g(r, 7))),
      ],
      days: [
        for (var r = 9; r <= 15; r++)
          if (g(r, 3).isNotEmpty) HoursBar(g(r, 3), _h(g(r, 7)), _h(g(r, 5)), rated: _h(g(r, 6)) > 0),
      ],
      types: [
        for (final row in types)
          if (row.isNotEmpty && row[0].isNotEmpty && row[0] != 'Type' && row[0] != 'Buffer') HoursBar(row[0], row.length > 2 ? _h(row[2]) : 0, row.length > 1 ? _h(row[1]) : 0),
      ],
    );
  }
}

class RateBlock {
  RateBlock({required this.row, required this.date, required this.start, required this.end, required this.name, required this.planned, required this.from, required this.to});
  final int row; // sheet row in Log
  final String date, start, end, name, planned;
  final DateTime from, to;
  bool isLive(DateTime now) => to.isAfter(now);
}

DateTime? _clock(String date, String t) {
  final m = RegExp(r'(\d+):(\d+)\s*(am|pm)', caseSensitive: false).firstMatch(t);
  final d = DateTime.tryParse(date);
  if (m == null || d == null) return null;
  var h = int.parse(m[1]!) % 12;
  if (m[3]!.toLowerCase() == 'pm') h += 12;
  return DateTime(d.year, d.month, d.day, h, int.parse(m[2]!));
}

/// Blocks from the last two days that still have no status, newest first.
List<RateBlock> blocksToRate(List<List<String>> log, DateTime now) {
  final since = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 2));
  final out = <RateBlock>[];
  for (var i = 0; i < log.length; i++) {
    final r = log[i];
    String c(int k) => k < r.length ? r[k] : '';
    if (c(0).isEmpty || c(8).isNotEmpty || c(6) == 'Buffer' || c(4).isEmpty) continue;
    final st = _clock(c(0), c(2));
    var en = _clock(c(0), c(3));
    if (st == null || en == null) continue;
    if (en.isBefore(st)) en = en.add(const Duration(days: 1));
    if (st.isAfter(now) || en.isBefore(since)) continue;
    out.add(RateBlock(row: i + 2, date: c(0), start: c(2), end: c(3), name: c(4), planned: c(7), from: st, to: en));
  }
  out.sort((a, b) => b.from.compareTo(a.from));
  return out;
}

class HoursRepository {
  HoursRepository(this.sheets);
  final SheetsApi sheets;

  Future<HoursSummary> summary() async {
    final r = await Future.wait([sheets.get('Dashboard!A1:J21'), sheets.get('Dashboard!D24:F40')]);
    return HoursSummary.parse(r[0], r[1]);
  }

  Future<List<List<String>>> log() => sheets.get('Log!A2:J600');

  /// status is DONE, PARTIAL, MISSED or SKIP; actual hours only for PARTIAL.
  Future<void> rate(RateBlock b, String status, double? actual) =>
      sheets.put('Log!I${b.row}:J${b.row}', [[status, if (status == 'PARTIAL' && actual != null) actual else '']]);
}

/// One status Claude proposed for a block, from "Rate with Claude".
class RatePick {
  RatePick(this.block, this.status, this.hours);
  final RateBlock block;
  final String status; // DONE, PARTIAL, MISSED or SKIP
  final double? hours; // PARTIAL only
}

/// The question for "Rate with Claude": the unrated blocks and the day in the person's words. Same wording
/// as the old site.
String ratePrompt(List<RateBlock> blocks, String said, DateTime now) {
  final list = blocks.map((b) => '${b.row} | ${b.date} ${b.start}-${b.end} | ${b.name} | ${b.planned}h planned').join('\n');
  return 'Today is $now. These planned blocks from my time tracker have no status yet (row | when | block | planned hours):\n'
      '$list\n\nWhat I did, in my own words:\n$said\n\n'
      'Match what I said to the blocks. Statuses: DONE (did it as planned), PARTIAL (did some; give the hours actually done), '
      'MISSED (didn\'t do it), SKIP (block no longer applies). Only include blocks my words clearly cover; leave the rest out. '
      'Reply with only this JSON, no other text:\n'
      '{"reply": "<one short sentence summarising>", "ratings": [{"row": <row number>, "status": "DONE|PARTIAL|MISSED|SKIP", "hours": <number, only for PARTIAL>}]}';
}

/// Reads Claude's answer: its one-line summary and the picks that match a real block. Throws
/// [SourceException] when the answer isn't the JSON asked for.
({String reply, List<RatePick> picks}) parseRatings(String answer, List<RateBlock> blocks) {
  final m = RegExp(r'\{[\s\S]*\}').firstMatch(answer);
  Object? j;
  try {
    j = m == null ? null : jsonDecode(m[0]!);
  } catch (_) {}
  if (j is! Map) throw SourceException("Claude's answer wasn't in the expected format. Try again.");
  final byRow = {for (final b in blocks) b.row: b};
  final picks = <RatePick>[];
  for (final r in (j['ratings'] as List? ?? const []).whereType<Map>()) {
    final b = byRow[(r['row'] as num?)?.toInt()];
    final st = '${r['status']}'.toUpperCase();
    if (b == null || !const {'DONE', 'PARTIAL', 'MISSED', 'SKIP'}.contains(st)) continue;
    final h = (r['hours'] as num?)?.toDouble();
    picks.add(RatePick(b, st, st == 'PARTIAL' && h != null && h > 0 ? h : null));
  }
  return (reply: '${j['reply'] ?? ''}'.trim(), picks: picks);
}
