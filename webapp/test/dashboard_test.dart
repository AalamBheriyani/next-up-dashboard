import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_up_core/calendar.dart';
import 'package:next_up_core/deadline.dart';
import 'package:next_up_core/deadline_source.dart';
import 'package:next_up_web/dashboard/dashboard_screen.dart';

class _Deadlines implements DeadlineSource {
  _Deadlines(this.items);
  final List<Deadline> items;
  @override
  Future<List<Deadline>> load() async => items;
  @override
  Future<void> complete(Deadline d) async => items.remove(d);
}

class _Calendar implements CalendarSource {
  _Calendar(this.events, {this.fail});
  final List<CalendarEvent> events;
  final SourceException? fail;
  @override
  Future<List<CalendarEvent>> load(DateTime from, DateTime to) async => fail != null ? throw fail! : events;
}

void main() {
  final now = DateTime(2026, 10, 10, 10, 30);
  Deadline dl(String id, String title, DateTime due) => Deadline(id: id, projectId: 'p', title: title, due: due, allDay: false, priority: 0, list: 'School');

  Future<void> show(WidgetTester tester, CalendarSource cal) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: DashboardScreen(
        deadlines: _Deadlines([dl('1', 'Chem quiz', DateTime(2026, 10, 12, 9)), dl('2', 'Late essay', DateTime(2026, 10, 8, 9))]),
        calendar: cal,
        signedIn: () => true,
        onSignIn: () async {},
        now: () => now,
      ),
    ));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('shows the next deadline, the current event and the sections', (tester) async {
    final events = [
      CalendarEvent(id: 'e', title: 'Chemistry class', start: DateTime(2026, 10, 10, 10), end: DateTime(2026, 10, 10, 11), allDay: false),
      CalendarEvent(id: 'f', title: 'Piano', start: DateTime(2026, 10, 10, 16), end: DateTime(2026, 10, 10, 17), allDay: false),
    ];
    await show(tester, _Calendar(events));
    expect(find.text('Chem quiz'), findsWidgets);
    expect(find.text('Chemistry class'), findsOneWidget);
    expect(find.text('Piano'), findsOneWidget);
    expect(find.text('OVERDUE'), findsWidgets);
    expect(find.text('Late essay'), findsWidgets); // the "do this first" strip and the list
    expect(find.text('NEXT 7 DAYS'), findsOneWidget);
  });

  testWidgets('a calendar failure leaves the deadlines on screen', (tester) async {
    await show(tester, _Calendar(const [], fail: SourceException('Calendar needs your permission.', signedOut: true)));
    expect(find.text('Calendar needs your permission.'), findsOneWidget);
    expect(find.text('Chem quiz'), findsWidgets);
  });

  testWidgets('the focus timer starts and counts down', (tester) async {
    await show(tester, _Calendar(const []));
    expect(find.text('25:00'), findsOneWidget);
    await tester.tap(find.text('Start'));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Pause'), findsOneWidget);
    expect(find.text('25:00'), findsNothing);
    await tester.tap(find.text('Pause'));
    await tester.pump();
  });
}
