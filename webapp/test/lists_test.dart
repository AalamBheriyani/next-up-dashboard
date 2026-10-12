import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_up_core/deadline.dart';
import 'package:next_up_web/dashboard/deadline_box.dart';
import 'package:next_up_web/pages/lists_screen.dart';

import 'fakes.dart';

void main() {
  final now = DateTime(2026, 10, 10, 12);
  Deadline d(String title, Duration due, int priority) => Deadline(id: title, projectId: 'p', title: title, due: now.add(due), allDay: false, priority: priority, list: 'Uni');

  Future<void> pump(WidgetTester t, List<Deadline> items) async {
    t.view.physicalSize = const Size(1300, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(home: Scaffold(body: ListsScreen(services: fakeServices(deadlines: items), now: () => now))));
    await t.pump(const Duration(seconds: 1));
  }

  testWidgets('the Urgent / Important view shows four boxes of the same size', (t) async {
    await pump(t, [d('Essay', const Duration(hours: 3), 5), d('Plan year', const Duration(days: 9), 3), for (var i = 0; i < 30; i++) d('Chore $i', const Duration(days: 20), 0)]);
    expect(find.text('DO FIRST'), findsOneWidget);
    expect(find.text('SCHEDULE'), findsOneWidget);
    expect(find.text('QUICK WINS'), findsOneWidget);
    expect(find.text('LATER'), findsOneWidget);
    expect(find.text('Essay'), findsOneWidget);
    final heights = {for (final b in t.widgetList(find.byType(DeadlineBox))) t.getSize(find.byWidget(b)).height};
    expect(heights, {deadlineBoxHeight}, reason: 'a box with 30 items is as tall as one with 1; long lists scroll');
  });

  testWidgets('switching the view regroups the same deadlines', (t) async {
    await pump(t, [d('Essay', const Duration(hours: 3), 5), d('Plan year', const Duration(days: 9), 3)]);
    await t.tap(find.text('Priority'));
    await t.pump(const Duration(seconds: 1));
    expect(find.text('HIGH'), findsOneWidget);
    expect(find.text('NO PRIORITY'), findsOneWidget);
    await t.tap(find.text('By list'));
    await t.pump(const Duration(seconds: 1));
    expect(find.text('UNI'), findsOneWidget);
  });

  testWidgets('finishing a deadline removes it from its box', (t) async {
    await pump(t, [d('Essay', const Duration(hours: 3), 5)]);
    await t.tap(find.byTooltip('Finish Essay'));
    await t.pump(const Duration(seconds: 1));
    expect(find.text('Essay'), findsNothing);
  });

  testWidgets('search and the list chips narrow the boxes', (t) async {
    final home = Deadline(id: 'h', projectId: 'q', title: 'Laundry', due: now.add(const Duration(hours: 5)), allDay: false, priority: 0, list: 'Home');
    await pump(t, [d('Essay', const Duration(hours: 3), 5), d('Plan year', const Duration(days: 9), 3), home]);
    await t.enterText(find.byType(TextField), 'ess');
    await t.pump();
    expect(find.text('Essay'), findsOneWidget);
    expect(find.text('Plan year'), findsNothing);
    await t.enterText(find.byType(TextField), '');
    await t.tap(find.widgetWithText(FilterChip, 'Home'));
    await t.pump();
    expect(find.text('Laundry'), findsOneWidget);
    expect(find.text('Essay'), findsNothing);
  });
}
