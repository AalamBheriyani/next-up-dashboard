import 'package:flutter_test/flutter_test.dart';
import 'package:next_up_core/calendar.dart';

Map<String, dynamic> ev(String id, String s, String e, {String? summary, bool allDay = false, Map? extra}) => {
      'id': id,
      'summary': summary ?? id,
      'start': allDay ? {'date': s} : {'dateTime': s},
      'end': allDay ? {'date': e} : {'dateTime': e},
      ...?extra?.cast<String, dynamic>(),
    };

void main() {
  final now = DateTime(2026, 10, 10, 10, 30);
  String iso(int h, [int m = 0]) => DateTime(2026, 10, 10, h, m).toIso8601String();

  test('parses timed and all-day events, skips cancelled and declined', () {
    final events = [
      ev('a', iso(9), iso(10)),
      ev('b', '2026-10-10', '2026-10-11', allDay: true),
      ev('c', iso(11), iso(12), extra: {'status': 'cancelled'}),
      ev('d', iso(11), iso(12), extra: {'attendees': [{'self': true, 'responseStatus': 'declined'}]}),
    ].map(CalendarEvent.fromJson).whereType<CalendarEvent>().toList();
    expect(events.map((e) => e.id), ['a', 'b']);
    expect(events[1].allDay, isTrue);
  });

  test('current, next and booked time left', () {
    final all = [
      ev('past', iso(8), iso(9)),
      ev('now', iso(10), iso(11)),
      ev('next', iso(13), iso(14)),
      ev('later', iso(15), iso(15, 30)),
    ].map(CalendarEvent.fromJson).whereType<CalendarEvent>().toList();
    final day = DaySchedule(all, now);
    expect(day.current?.id, 'now');
    expect(day.next?.id, 'next');
    expect(day.bookedLeft, const Duration(minutes: 30 + 60 + 30));
  });

  test('an untitled event gets a placeholder title', () {
    final e = CalendarEvent.fromJson({'id': 'x', 'start': {'dateTime': iso(9)}, 'end': {'dateTime': iso(10)}})!;
    expect(e.title, '(no title)');
  });
}
