import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_up_core/deadline.dart';
import 'package:next_up_core/deadline_source.dart';
import 'package:next_up_web/dashboard/deadline_editor.dart';

class _Editor implements DeadlineEditor {
  final calls = <String>[];
  @override
  Future<void> update(Deadline d, {String? title, DateTime? day, int? priority}) async => calls.add('update ${title ?? '-'} ${day?.day ?? '-'} ${priority ?? '-'}');
  @override
  Future<void> delete(Deadline d) async => calls.add('delete');
  @override
  Future<void> create({required String title, DateTime? day, int priority = 0}) async => calls.add('create $title ${day?.day ?? '-'} $priority');
}

void main() {
  final d = Deadline.fromTask({'id': 'a', 'projectId': 'p', 'title': 'Chem quiz', 'dueDate': '2026-10-12T04:00:00+0000', 'isAllDay': true, 'priority': 1}, {})!;
  final now = DateTime(2026, 10, 10, 9);

  Future<void> open(WidgetTester t, _Editor e, {Deadline? d}) async {
    t.view.physicalSize = const Size(1000, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(home: Builder(builder: (c) => Scaffold(body: TextButton(onPressed: () => showDeadlineEditor(c, e, d: d, now: () => now), child: const Text('open'))))));
    await t.tap(find.text('open'));
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    await t.pump(const Duration(seconds: 1));
  }

  testWidgets('saving only sends what changed', (tester) async {
    final e = _Editor();
    await open(tester, e, d: d);
    await tester.tap(find.text('Tomorrow'));
    await tester.tap(find.text('High'));
    await tester.tap(find.text('Save'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(e.calls, ['update - 11 5']);
  });

  testWidgets('delete needs a second tap', (tester) async {
    final e = _Editor();
    await open(tester, e, d: d);
    await tester.tap(find.text('Delete'));
    await tester.pump();
    expect(e.calls, isEmpty);
    await tester.tap(find.text('Tap again to delete'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(e.calls, ['delete']);
  });

  testWidgets('adding needs a name, then creates', (tester) async {
    final e = _Editor();
    await open(tester, e);
    await tester.tap(find.text('Add'));
    await tester.pump();
    expect(find.text('Give it a name first.'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Essay draft');
    await tester.tap(find.text('Today'));
    await tester.tap(find.text('Add'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(e.calls, ['create Essay draft 10 0']);
  });
}
