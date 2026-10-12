import 'package:flutter_test/flutter_test.dart';
import 'package:next_up_core/deadline.dart';
import 'package:next_up_core/list_views.dart';

void main() {
  final now = DateTime(2026, 10, 10, 12);
  Deadline d(String id, Duration due, {int priority = 0, String list = 'Uni'}) => Deadline(id: id, projectId: 'p', title: id, due: now.add(due), allDay: false, priority: priority, list: list);

  final all = [
    d('late-high', const Duration(hours: -3), priority: 5),
    d('soon-low', const Duration(hours: 5), priority: 1),
    d('week-med', const Duration(days: 4), priority: 3, list: 'Home'),
    d('far-none', const Duration(days: 30), list: ''),
    d('tomorrow', const Duration(hours: 20), priority: 3),
  ];

  List<String> titles(ListGroup g) => [for (final x in g.items) x.id];

  test('urgent and important land in the four boxes', () {
    final g = groupsFor(ListViewKind.matrix, all, now);
    expect(g.map((x) => x.title), ['Do first', 'Schedule', 'Quick wins', 'Later']);
    expect(titles(g[0]), ['late-high', 'tomorrow']);
    expect(titles(g[1]), ['week-med']);
    expect(titles(g[2]), ['soon-low']);
    expect(titles(g[3]), ['far-none']);
  });

  test('every deadline appears exactly once in every view', () {
    for (final k in ListViewKind.values) {
      final ids = [for (final g in groupsFor(k, all, now)) ...titles(g)]..sort();
      expect(ids, [for (final x in all) x.id]..sort(), reason: '$k');
    }
  });

  test('priority view groups high, medium, low and none', () {
    final g = groupsFor(ListViewKind.priority, all, now);
    expect([for (final x in g) titles(x)], [['late-high'], ['tomorrow', 'week-med'], ['soon-low'], ['far-none']]);
  });

  test('due view splits overdue, today, tomorrow, this week and later', () {
    final g = groupsFor(ListViewKind.due, all, now);
    expect([for (final x in g) titles(x)], [['late-high'], ['soon-low'], ['tomorrow'], ['week-med'], ['far-none']]);
  });

  test('list view groups by TickTick list, with unnamed ones last', () {
    final g = groupsFor(ListViewKind.list, all, now);
    expect(g.map((x) => x.title), ['Home', 'Uni', 'No list']);
  });

  test('the week view has Overdue, then one box per day', () {
    final g = groupsFor(ListViewKind.week, [d('late', const Duration(hours: -3)), d('today', const Duration(hours: 2)), d('fri', const Duration(days: 6))], now);
    expect(g.map((x) => x.title), ['Overdue', 'Sat 10', 'Sun 11', 'Mon 12', 'Tue 13', 'Wed 14', 'Thu 15', 'Fri 16', 'Later']);
    expect(g[0].items.single.id, 'late');
    expect(g[1].items.single.id, 'today');
    expect(g[1].hint, 'Today');
    expect(g[7].items.single.id, 'fri');
  });
}
