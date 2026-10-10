import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_up/data/deadline.dart';
import 'package:next_up/data/deadline_source.dart';
import 'package:next_up/features/today_screen.dart';
import 'package:next_up/theme.dart';

class FakeSource implements DeadlineSource {
  FakeSource(this.items, {this.fail});
  final List<Deadline> items;
  final SourceException? fail;
  final finished = <String>[];

  @override
  Future<List<Deadline>> load() async {
    if (fail != null) throw fail!;
    return items;
  }

  @override
  Future<void> complete(Deadline d) async => finished.add(d.id);
}

Deadline d(String id, String title, DateTime due, {bool allDay = true}) =>
    Deadline(id: id, projectId: 'p', title: title, due: due, allDay: allDay, priority: 3, list: '🏫School');

void main() {
  final now = DateTime(2026, 10, 10, 9, 0);

  test('parses TickTick dates: all-day uses the date part, timed uses the offset', () {
    final allDay = Deadline.fromTask(
      {'id': 'a', 'projectId': 'p', 'title': 'x', 'dueDate': '2026-10-04T00:00:00-0600', 'isAllDay': true},
      {'p': 'School'},
    )!;
    expect(allDay.due, DateTime(2026, 10, 4, 23, 59, 59));
    expect(allDay.list, 'School');
    final timed = Deadline.fromTask({'id': 'b', 'title': 'y', 'dueDate': '2026-10-04T15:30:00+0000', 'isAllDay': false}, {})!;
    expect(timed.due.toUtc(), DateTime.utc(2026, 10, 4, 15, 30));
    expect(Deadline.fromTask({'id': 'c', 'title': 'no date'}, {}), isNull);
  });

  test('groups overdue oldest first and picks the next upcoming deadline', () {
    final g = DeadlineGroups([
      d('1', 'late newer', DateTime(2026, 10, 6, 23, 59)),
      d('2', 'late older', DateTime(2026, 10, 4, 23, 59)),
      d('3', 'today', DateTime(2026, 10, 10, 23, 59)),
      d('4', 'next month', DateTime(2026, 11, 1, 23, 59)),
    ], now);
    expect(g.overdue.map((x) => x.id), ['2', '1']);
    expect(g.next!.id, '3');
    expect(g.later(now).map((x) => x.id), ['4']);
  });

  Future<void> pump(WidgetTester t, FakeSource s, {bool signedIn = true}) async {
    await t.binding.setSurfaceSize(const Size(400, 900));
    await t.pumpWidget(MaterialApp(
      theme: buildNextUpTheme(),
      home: TodayScreen(source: s, signedIn: () => signedIn, onSignIn: () async {}, now: () => now),
    ));
    await t.pump();
    await t.pump();
  }

  testWidgets('shows the next deadline, overdue list and finishes a task', (t) async {
    final s = FakeSource([
      d('1', 'Chem quiz', DateTime(2026, 10, 4, 23, 59)),
      d('3', 'Math exam prep', DateTime(2026, 10, 10, 23, 59)),
      d('4', 'Specsavers', DateTime(2026, 11, 1, 23, 59)),
    ]);
    await pump(t, s);
    expect(find.text('NEXT DEPARTURE'), findsOneWidget);
    expect(find.text('Math exam prep'), findsOneWidget);
    expect(find.text('OVERDUE'), findsOneWidget);
    expect(find.text('6d late'), findsOneWidget);
    await t.tap(find.byTooltip('Finish Chem quiz'));
    await t.pumpAndSettle();
    expect(s.finished, ['1']);
    expect(find.text('Chem quiz'), findsNothing);
  });

  testWidgets('asks to sign in when signed out', (t) async {
    await pump(t, FakeSource([]), signedIn: false);
    expect(find.text('Sign in with Google'), findsOneWidget);
  });

  testWidgets('explains when TickTick is not connected', (t) async {
    await pump(t, FakeSource([], fail: SourceException('Connect TickTick once in the Classic tab.', notConnected: true)));
    expect(find.textContaining('Connect TickTick'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });
}
