// Today's calendar from Google Calendar, for the dashboard's "Now and next" panel.
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'deadline_source.dart';

class CalendarEvent {
  CalendarEvent({required this.id, required this.title, required this.start, required this.end, required this.allDay, this.location = ''});
  final String id;
  final String title;
  final DateTime start;
  final DateTime end; // exclusive for all-day events, like Google's API
  final bool allDay;
  final String location;

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
    return CalendarEvent(id: '${e['id']}', title: title.isEmpty ? '(no title)' : title, start: start, end: end, allDay: allDay, location: '${e['location'] ?? ''}');
  }

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

abstract class CalendarSource {
  Future<List<CalendarEvent>> load(DateTime from, DateTime to);
}

/// Reads the primary calendar with a Google access token.
class GoogleCalendarSource implements CalendarSource {
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
}
