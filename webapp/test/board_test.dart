import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_up_core/board_layout.dart';
import 'package:next_up_web/board/widget_board.dart';
import 'package:next_up_web/dashboard/dashboard_screen.dart' show migrateDashboardLayout;

void main() {
  resizeTests();
  const items = [
    BoardItem(id: 'a', name: 'Alpha', span: 6, child: SizedBox(height: 160, child: Text('A body'))),
    BoardItem(id: 'b', name: 'Beta', span: 6, child: SizedBox(height: 160, child: Text('B body'))),
    BoardItem(id: 'c', name: 'Gamma', span: 12, child: SizedBox(height: 160, child: Text('C body'))),
  ];

  Future<BoardLayout> pump(WidgetTester t, {required double width, BoardLayout layout = const BoardLayout(), bool editing = false, ValueChanged<BoardLayout>? onChanged}) async {
    t.view.physicalSize = Size(width, 1200);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    var current = layout;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, set) => SingleChildScrollView(
            child: WidgetBoard(items: items, layout: current, editing: editing, onChanged: (l) {
              set(() => current = l);
              onChanged?.call(l);
            }),
          ),
        ),
      ),
    ));
    await t.pump(const Duration(seconds: 1));
    return current;
  }

  testWidgets('wide screens put two half-width panels side by side', (t) async {
    await pump(t, width: 1400);
    expect(t.getTopLeft(find.text('A body')).dy, t.getTopLeft(find.text('B body')).dy);
  });

  testWidgets('phones stack the same layout', (t) async {
    await pump(t, width: 420);
    expect(t.getTopLeft(find.text('B body')).dy, greaterThan(t.getTopLeft(find.text('A body')).dy + 40));
  });

  testWidgets('hidden panels are not shown, but come back while customising', (t) async {
    await pump(t, width: 1400, layout: const BoardLayout(hidden: ['b']));
    expect(find.text('B body'), findsNothing);
    await pump(t, width: 1400, layout: const BoardLayout(hidden: ['b']), editing: true);
    expect(find.text('B body'), findsOneWidget);
  });

  testWidgets('holding a panel and dragging it over another swaps their places', (t) async {
    final saved = <BoardLayout>[];
    await pump(t, width: 1400, editing: true, onChanged: saved.add);
    final g = await t.startGesture(t.getCenter(find.text('Alpha')));
    await t.pump(const Duration(milliseconds: 400));
    await g.moveTo(t.getCenter(find.text('Beta')));
    await t.pump(const Duration(milliseconds: 200));
    await t.pump(const Duration(milliseconds: 200));
    await g.up();
    await t.pump(const Duration(seconds: 1));
    expect(saved.last.order, ['b', 'a', 'c']);
  });

  testWidgets('the cross hides a panel', (t) async {
    final saved = <BoardLayout>[];
    await pump(t, width: 1400, editing: true, onChanged: saved.add);
    await t.tap(find.byTooltip('Hide').last);
    await t.pump(const Duration(seconds: 1));
    expect(saved.last.hidden, ['c']);
  });

  testWidgets('holding a panel outside customise mode asks to start customising', (t) async {
    var asked = 0;
    t.view.physicalSize = const Size(1400, 1200);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: WidgetBoard(items: items, layout: const BoardLayout(), editing: false, onChanged: (_) {}, onEdit: () => asked++)))));
    await t.longPress(find.text('A body'));
    expect(asked, 1);
  });

  testWidgets('the size menu changes a panel to full width', (t) async {
    final saved = <BoardLayout>[];
    await pump(t, width: 1400, editing: true, onChanged: saved.add);
    await t.tap(find.byTooltip('Size').first);
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    expect(find.text('Full width'), findsWidgets);
    await t.tap(find.text('Full width').last);
    await t.pump(const Duration(seconds: 1));
    expect(saved.last.span['a'], 12);
  });

  test('effective span follows the old site breakpoints', () {
    expect(effectiveSpan(4, 1400), 4);
    expect(effectiveSpan(4, 900), 6);
    expect(effectiveSpan(9, 900), 9);
    expect(effectiveSpan(4, 420), 12);
  });
}

void resizeTests() {
  testWidgets('dragging the corner snaps the width and height', (t) async {
    t.view.physicalSize = const Size(1400, 1200);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final saved = <BoardLayout>[];
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: WidgetBoard(
            items: const [BoardItem(id: 'a', name: 'Alpha', span: 6, child: SizedBox(height: 300, child: Text('A body')))],
            layout: const BoardLayout(),
            editing: true,
            onChanged: saved.add,
          ),
        ),
      ),
    ));
    await t.pump(const Duration(seconds: 1));
    await t.drag(find.byIcon(Icons.south_east_rounded), const Offset(900, 0));
    await t.pump(const Duration(seconds: 1));
    expect(saved.last.span['a'], 12);
    await t.drag(find.byIcon(Icons.south_east_rounded), const Offset(0, 300));
    await t.pump(const Duration(seconds: 1));
    expect(saved.last.height['a'], isNotNull);
  });

  test('panels pack into rows of 12 columns, in order', () {
    expect(boardRows([4, 4, 4, 8, 4, 6, 12, 6]), [[0, 1, 2], [3, 4], [5], [6], [7]]);
  });

  testWidgets('panels in a row are as tall as the tallest one', (t) async {
    t.view.physicalSize = const Size(1400, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: WidgetBoard(
            layout: const BoardLayout(),
            editing: false,
            onChanged: (_) {},
            items: const [
              BoardItem(id: 'a', name: 'A', span: 6, child: ColoredBox(key: Key('panel-a'), color: Colors.red, child: SizedBox(height: 100))),
              BoardItem(id: 'b', name: 'B', span: 6, child: ColoredBox(key: Key('panel-b'), color: Colors.red, child: SizedBox(height: 300))),
            ],
          ),
        ),
      ),
    ));
    await t.pump(const Duration(seconds: 1));
    expect(t.getSize(find.byKey(const Key('panel-a'))).height, 300);
    expect(t.getSize(find.byKey(const Key('panel-b'))).height, 300);
  });

  test('a layout saved with the four deadline lists starts again from the old-site order', () {
    const old = BoardLayout(order: ['overdue', 'next', 'calendar', 'quest-level', 'links'], span: {'next': 6, 'quest-level': 6}, hidden: ['later', 'anki']);
    final m = migrateDashboardLayout(old);
    expect(m.order, ['quest-level'], reason: 'other pages keep their order');
    expect(m.span, {'quest-level': 6});
    expect(m.hidden, ['anki']);
    const fresh = BoardLayout(order: ['deadlines', 'next'], span: {'next': 8});
    expect(identical(migrateDashboardLayout(fresh), fresh), isTrue, reason: 'a new layout is left alone');
  });
}
