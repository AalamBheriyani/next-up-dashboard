// Track: Timelines-style time tracking kept in the Time Tracker sheet's "Tracked" tab.
// A: start, B: end (blank while running), C: category, D: note, E: id. Targets sit in G:I
// (category, daily hours, weekly hours) so they can also be edited in the sheet.
import 'sheets.dart';

const trackTab = 'Tracked';
const defaultCategories = ['Class', 'Study', 'Homework', 'Debate', 'Meals', 'Commute', 'Chores', 'Personal', 'Free Time'];

class TrackBlock {
  TrackBlock({required this.row, required this.start, this.end, required this.cat, this.note = '', required this.id});
  int row; // 1-based sheet row, 0 until known
  DateTime start;
  DateTime? end; // null while running
  String cat;
  String note;
  final String id;

  DateTime endOr(DateTime now) => end ?? now;
  bool get running => end == null;
}

class TrackTarget {
  const TrackTarget(this.cat, {this.day = 0, this.week = 0});
  final String cat;
  final double day; // hours
  final double week;
}

class TrackData {
  TrackData({required this.blocks, required this.targets, required this.sheetCategories});
  final List<TrackBlock> blocks;
  List<TrackTarget> targets;
  final List<String> sheetCategories;

  TrackBlock? get running {
    final r = blocks.where((b) => b.running).toList()..sort((a, b) => b.start.compareTo(a.start));
    return r.isEmpty ? null : r.first;
  }

  /// The categories to offer: the sheet's list (or the defaults) plus any already used.
  List<String> get categories {
    final base = sheetCategories.isEmpty ? defaultCategories : sheetCategories;
    return {...base, ...blocks.map((b) => b.cat), ...targets.map((t) => t.cat)}.where((c) => c.isNotEmpty).toList();
  }

  /// Milliseconds per category inside [from, to).
  Map<String, Duration> totals(DateTime from, DateTime to, DateTime now) {
    final out = <String, Duration>{};
    for (final b in blocks) {
      final a = b.start.isAfter(from) ? b.start : from;
      final z = b.endOr(now).isBefore(to) ? b.endOr(now) : to;
      if (z.isAfter(a)) out[b.cat] = (out[b.cat] ?? Duration.zero) + z.difference(a);
    }
    return out;
  }

  List<TrackBlock> onDay(DateTime day, DateTime now) {
    final a = DateTime(day.year, day.month, day.day), z = a.add(const Duration(days: 1));
    return blocks.where((b) => b.start.isBefore(z) && b.endOr(now).isAfter(a)).toList();
  }

  TrackTarget? targetFor(String cat) {
    for (final t in targets) {
      if (t.cat.toLowerCase() == cat.toLowerCase()) return t;
    }
    return null;
  }
}

/// Weeks run Sunday to Saturday, like the Time Tracker.
DateTime weekStart(DateTime now) {
  final d = DateTime(now.year, now.month, now.day);
  return d.subtract(Duration(days: d.weekday % 7));
}

abstract class TrackRepository {
  Future<TrackData> load();
  Future<void> start(TrackData d, String cat, String note, DateTime now); // stops whatever was running at the same moment
  Future<void> stop(TrackData d, DateTime now);
  Future<void> add(TrackData d, TrackBlock b);
  Future<void> update(TrackData d, TrackBlock b);
  Future<void> delete(TrackData d, TrackBlock b);
  Future<void> saveTargets(TrackData d, List<TrackTarget> targets);
}

String newId() => DateTime.now().millisecondsSinceEpoch.toRadixString(36) + (DateTime.now().microsecond).toRadixString(36);

class SheetsTrackRepository implements TrackRepository {
  SheetsTrackRepository(this.sheets);
  final SheetsApi sheets;
  bool _ready = false;

  Future<void> _ensureTab() async {
    if (_ready) return;
    if (!(await sheets.tabs()).contains(trackTab)) {
      await sheets.addTab(trackTab);
      await sheets.putRaw('$trackTab!A1:I1', [['Start', 'End', 'Category', 'Note', 'Id', '', 'Target category', 'Daily target (h)', 'Weekly target (h)']]);
    }
    _ready = true;
  }

  @override
  Future<TrackData> load() async {
    await _ensureTab();
    final res = await Future.wait([
      sheets.get('$trackTab!A2:E5000'),
      sheets.get('$trackTab!G2:I60'),
      sheets.get('Dashboard!D24:F40').catchError((_) => <List<String>>[]),
    ]);
    final blocks = <TrackBlock>[];
    for (var i = 0; i < res[0].length; i++) {
      final r = res[0][i];
      String c(int k) => k < r.length ? r[k] : '';
      final start = DateTime.tryParse(c(0))?.toLocal();
      final end = c(1).isEmpty ? null : DateTime.tryParse(c(1))?.toLocal();
      if (start == null || c(2).trim().isEmpty || (c(1).isNotEmpty && end == null)) continue;
      blocks.add(TrackBlock(row: i + 2, start: start, end: end, cat: c(2).trim(), note: c(3), id: c(4)));
    }
    final targets = [
      for (final r in res[1])
        if (r.isNotEmpty && r[0].trim().isNotEmpty) TrackTarget(r[0].trim(), day: r.length > 1 ? double.tryParse(r[1]) ?? 0 : 0, week: r.length > 2 ? double.tryParse(r[2]) ?? 0 : 0),
    ];
    final cats = [
      for (final r in res[2])
        if (r.isNotEmpty && r[0].trim().isNotEmpty && !RegExp(r'^(type|buffer)$', caseSensitive: false).hasMatch(r[0].trim())) r[0].trim(),
    ];
    return TrackData(blocks: blocks, targets: targets, sheetCategories: cats);
  }

  Future<void> _append(TrackData d, TrackBlock b) async {
    b.row = await sheets.append('$trackTab!A1:E1', [[b.start.toUtc().toIso8601String(), b.end?.toUtc().toIso8601String() ?? '', b.cat, b.note, b.id]]);
    d.blocks.add(b);
  }

  @override
  Future<void> start(TrackData d, String cat, String note, DateTime now) async {
    final run = d.running;
    if (run != null && run.cat == cat && note.isEmpty) return;
    if (run != null) await _writeEnd(run, now);
    await _append(d, TrackBlock(row: 0, start: now, cat: cat, note: note, id: newId()));
  }

  Future<void> _writeEnd(TrackBlock b, DateTime end) async {
    await sheets.putRaw('$trackTab!B${b.row}', [[end.toUtc().toIso8601String()]]);
    b.end = end;
  }

  @override
  Future<void> stop(TrackData d, DateTime now) async {
    final run = d.running;
    if (run != null) await _writeEnd(run, now);
  }

  @override
  Future<void> add(TrackData d, TrackBlock b) => _append(d, b);

  @override
  Future<void> update(TrackData d, TrackBlock b) =>
      sheets.putRaw('$trackTab!A${b.row}:D${b.row}', [[b.start.toUtc().toIso8601String(), b.end?.toUtc().toIso8601String() ?? '', b.cat, b.note]]);

  @override
  Future<void> delete(TrackData d, TrackBlock b) async {
    await sheets.putRaw('$trackTab!A${b.row}:E${b.row}', [['', '', '', '', '']]);
    d.blocks.remove(b);
  }

  @override
  Future<void> saveTargets(TrackData d, List<TrackTarget> targets) async {
    final rows = [for (final t in targets) [t.cat, if (t.day > 0) '${t.day}' else '', if (t.week > 0) '${t.week}' else '']];
    final pad = [for (var i = rows.length; i < 59; i++) ['', '', '']];
    await sheets.putRaw('$trackTab!G2:I60', [...rows, ...pad]);
    d.targets = targets;
  }
}
