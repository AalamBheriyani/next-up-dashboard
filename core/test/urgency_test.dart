import 'package:flutter_test/flutter_test.dart';
import 'package:next_up_core/deadline.dart';
import 'package:next_up_core/urgency.dart';

void main() {
  final now = DateTime(2026, 10, 10, 12);
  Deadline due(Duration d) => Deadline(id: 'a', projectId: 'p', title: 'x', due: now.add(d), allDay: false, priority: 0, list: '');

  test('urgency grows as the deadline gets close', () {
    expect(urgencyOf(due(const Duration(days: 20)), now), Urgency.later);
    expect(urgencyOf(due(const Duration(days: 3)), now), Urgency.week);
    expect(urgencyOf(due(const Duration(hours: 10)), now), Urgency.soon);
    expect(urgencyOf(due(const Duration(hours: 1)), now), Urgency.critical);
    expect(urgencyOf(due(const Duration(hours: -2)), now), Urgency.overdue);
  });

  test('the nudge says what to do', () {
    expect(urgencyLine(due(const Duration(hours: 2, minutes: 10)), now), 'Due in 2h 10m. Start now.');
    expect(urgencyLine(due(const Duration(days: 3, hours: 5)), now), 'Due in 3 days.');
    expect(urgencyLine(due(const Duration(days: -11)), now), '11 days late. Start it now.');
  });
}
