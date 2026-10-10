import 'package:flutter_test/flutter_test.dart';
import 'package:next_up_core/deadline.dart';

void main() {
  test('moving an all-day deadline changes only the date', () {
    final d = Deadline.fromTask({'id': 'a', 'projectId': 'p', 'title': 'x', 'dueDate': '2026-10-12T04:00:00+0000', 'isAllDay': true}, {})!;
    expect(d.dueOn(DateTime(2026, 10, 15)), '2026-10-15T04:00:00+0000');
  });

  test('moving a timed deadline keeps its local time of day', () {
    final d = Deadline.fromTask({'id': 'a', 'projectId': 'p', 'title': 'x', 'dueDate': '2026-10-12T13:30:00+0000'}, {})!;
    final moved = d.dueOn(DateTime(2026, 10, 14));
    final back = DateTime.parse(moved.replaceFirstMapped(RegExp(r'([+-]\d\d)(\d\d)$'), (m) => '${m[1]}:${m[2]}')).toLocal();
    expect((back.year, back.month, back.day, back.hour, back.minute), (2026, 10, 14, d.due.hour, d.due.minute));
  });

  test('a new all-day deadline is formatted the way TickTick expects', () {
    expect(newDueText(DateTime(2026, 10, 9), allDay: true), '2026-10-09T00:00:00+0000');
  });
}
