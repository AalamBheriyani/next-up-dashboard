// Today's calendar from Google Calendar, for the dashboard's "Now and next" panel.
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'deadline.dart';
import 'deadline_source.dart';

class CalendarEvent {
  CalendarEvent({required this.id, required this.title, required this.start, required this.end, required this.allDay, this.location = '', this.description = '', this.link = ''});
  final String id;
  final String title;
  final DateTime start;
  final DateTime end; // exclusive for all-day events, like Google's API
  final bool allDay;
  final String location;
  /// The event's notes as plain text (Google sends simple HTML).
  final String description;
  /// The event's page in Google Calendar (https only), opened when the event is tapped.
  final String link;

  /// "First step: ..." and "Done when: ..." lines in the notes, which planned blocks carry.
  String? get firstStep => _line('First step');
  String? get doneWhen => _line('Done when');
  String? _line(String name) => RegExp('$name:\\s*([^\\n]+)', caseSensitive: false).firstMatch(description)?.group(1)?.trim();

  /// Null for cancelled events and ones the person declined.
  static CalendarEvent? fromJson(Map<String, dynamic> e) {
    if (e['status'] == 'cancelled') return null;
    for (final a in (e['attendees'] as List? ?? const [])) {
      if (a is Map && a['self'] == true && a['responseStatus'] == 'declined') return null;
    }
    final s = e['start'] as Map?, en = e['end'] as Map?;
    if (s == null || en == null) return null;
    final allDay = s['dateTime'] == null;
    final start = _parse(s), end = _parse(en);
    if (start == null || end == null) return null;
    final title = '${e['summary'] ?? ''}'.trim();
    return CalendarEvent(id: '${e['id']}', title: title.isEmpty ? '(no title)' : title, start: start, end: end, allDay: allDay, location: '${e['location'] ?? ''}', description: plainNotes('${e['description'] ?? ''}'), link: '${e['htmlLink'] ?? ''}'.startsWith('https://') ? '${e['htmlLink']}' : '');
  }

  /// Google's notes HTML as text: line breaks kept, tags dropped, the common entities decoded.
  static String plainNotes(String html) => html
      .replaceAll(RegExp(r'<br\s*/?>|</p>|</div>|</li>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&amp;', '&')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();

  static DateTime? _parse(Map m) {
    final dt = m['dateTime'];
    if (dt is String) return DateTime.tryParse(dt)?.toLocal();
    final d = m['date'];
    if (d is String) {
      final p = RegExp(r'^(\d{4})-(\d\d)-(\d\d)').firstMatch(d);
      if (p != null) return DateTime(int.parse(p[1]!), int.parse(p[2]!), int.parse(p[3]!));
    }
    return null;
  }

  Duration get length => end.difference(start);
  bool isOn(DateTime day) {
    final a = DateTime(day.year, day.month, day.day), b = a.add(const Duration(days: 1));
    return start.isBefore(b) && end.isAfter(a);
  }
}

/// What is on right now, what is next, and how much of the day is booked.
class DaySchedule {
  DaySchedule(List<CalendarEvent> all, this.now)
      : allDay = all.where((e) => e.allDay && e.isOn(now)).toList(),
        timed = (all.where((e) => !e.allDay && e.isOn(now)).toList()..sort((a, b) => a.start.compareTo(b.start)));
  final DateTime now;
  final List<CalendarEvent> allDay;
  final List<CalendarEvent> timed;

  CalendarEvent? get current {
    for (final e in timed) {
      if (!e.start.isAfter(now) && e.end.isAfter(now)) return e;
    }
    return null;
  }

  List<CalendarEvent> get upcoming => timed.where((e) => e.start.isAfter(now)).toList();
  CalendarEvent? get next => upcoming.isEmpty ? null : upcoming.first;
  Duration get bookedLeft => timed.fold(Duration.zero, (sum, e) {
        final from = e.start.isAfter(now) ? e.start : now;
        return e.end.isAfter(from) ? sum + e.end.difference(from) : sum;
      });
}

/// Puts events into Google Calendar ("Add to Calendar" on a deadline).
abstract class CalendarWriter {
  Future<void> add(Map<String, dynamic> event);
}

/// A deadline as a calendar event, like the old site: a timed one becomes a 1-hour block ending at its due
/// time, an all-day one an all-day event on its date. The notes carry the task's notes and its list.
Map<String, dynamic> eventForDeadline(Deadline d) {
  String ymd(DateTime t) => '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  final note = [if (d.notes.isNotEmpty) d.notes, 'From Next Up (TickTick: ${d.list.isEmpty ? 'Inbox' : d.list})'].join('\n\n');
  if (d.allDay) {
    final day = DateTime(d.due.year, d.due.month, d.due.day);
    return {'summary': d.title, 'description': note, 'start': {'date': ymd(day)}, 'end': {'date': ymd(DateTime(day.year, day.month, day.day + 1))}};
  }
  return {
    'summary': d.title,
    'description': note,
    'start': {'dateTime': d.due.subtract(const Duration(hours: 1)).toUtc().toIso8601String()},
    'end': {'dateTime': d.due.toUtc().toIso8601String()},
  };
}

abstract class CalendarSource {
  Future<List<CalendarEvent>> load(DateTime from, DateTime to);
}

/// Reads the primary calendar with a Google access token.
class GoogleCalendarSource implements CalendarSource, CalendarWriter {
  GoogleCalendarSource(this.token);
  final Future<String?> Function() token;

  @override
  Future<List<CalendarEvent>> load(DateTime from, DateTime to) async {
    final t = await token();
    if (t == null) throw SourceException('Sign in to see your calendar.', signedOut: true);
    final uri = Uri.https('www.googleapis.com', '/calendar/v3/calendars/primary/events', {
      'singleEvents': 'true',
      'orderBy': 'startTime',
      'maxResults': '100',
      'timeMin': from.toUtc().toIso8601String(),
      'timeMax': to.toUtc().toIso8601String(),
    });
    http.Response res;
    try {
      res = await http.get(uri, headers: {'Authorization': 'Bearer $t'});
    } on http.ClientException {
      throw SourceException("Can't reach Google Calendar. Check your connection.");
    }
    if (res.statusCode == 401) throw SourceException('Your sign-in expired. Sign in again.', signedOut: true);
    if (res.statusCode == 403) throw SourceException('Calendar needs your permission. Sign in again and allow Calendar.', signedOut: true);
    if (res.statusCode >= 400) throw SourceException('Calendar failed to load (${res.statusCode}).');
    final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return [
      for (final e in (data['items'] as List? ?? const [])) ?CalendarEvent.fromJson(e as Map<String, dynamic>),
    ];
  }

  @override
  Future<void> add(Map<String, dynamic> event) async {
    final t = await token();
    if (t == null) throw SourceException('Sign in to add it to your calendar.', signedOut: true);
    http.Response res;
    try {
      res = await http.post(Uri.https('www.googleapis.com', '/calendar/v3/calendars/primary/events'), headers: {'Authorization': 'Bearer $t', 'Content-Type': 'application/json'}, body: jsonEncode(event));
    } on http.ClientException {
      throw SourceException("Can't reach Google Calendar. Check your connection.");
    }
    if (res.statusCode == 401) throw SourceException('Your sign-in expired. Sign in again.', signedOut: true);
    if (res.statusCode == 403) throw SourceException('Sign in again and allow calendar access to add events.', signedOut: true);
    if (res.statusCode >= 400) throw SourceException("Couldn't add it to Google Calendar (${res.statusCode}).");
  }
}
