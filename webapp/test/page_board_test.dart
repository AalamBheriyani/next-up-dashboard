import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_up_core/board_layout.dart';
import 'package:next_up_web/board/page_board.dart';
import 'package:next_up_web/board/widget_board.dart';

void main() {
  test('auto-scroll speeds up near the edges and stays still in the middle', () {
    expect(autoScrollSpeed(300, 0, 600), 0);
    expect(autoScrollSpeed(0, 0, 600), -20);
    expect(autoScrollSpeed(600, 0, 600), 20);
    expect(autoScrollSpeed(45, 0, 600), closeTo(-10, 0.01));
    expect(autoScrollSpeed(555, 0, 600), closeTo(10, 0.01));
  });

  final items = [
    for (final id in ['p1', 'p2', 'p3'])
      BoardItem(id: id, name: id.toUpperCase(), span: 12, child: SizedBox(height: 300, child: Text('$id body'))),
  ];

  Future<void> pump(WidgetTester t, {BoardLayout layout = const BoardLayout(), ValueChanged<BoardLayout>? onLayout, ScrollController? scroll, double height = 500}) async {
    t.view.physicalSize = Size(1000, height);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      home: Scaffold(body: ListView(controller: scroll, children: [PageBoard(items: items, layout: layout, onLayout: onLayout)])),
    ));
    await t.pump(const Duration(seconds: 1));
  }

  testWidgets('hiding a panel saves it without touching the other pages', (t) async {
    BoardLayout? saved;
    await pump(t, layout: const BoardLayout(order: ['x1', 'x2'], span: {'x1': 4}, hidden: ['x2']), onLayout: (l) => saved = l);
    await t.tap(find.byTooltip('Customise panels'));
    await t.pump(const Duration(seconds: 1));
    await t.tap(find.byTooltip('Hide').first);
    await t.pump(const Duration(seconds: 1));
    expect(saved!.hidden, ['x2', 'p1']);
    expect(saved!.span, {'x1': 4});
    expect(saved!.order, ['x1', 'x2', 'p1', 'p2', 'p3']);
  });

  testWidgets('dragging a panel to the bottom edge scrolls the page', (t) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await pump(t, scroll: scroll);
    await t.tap(find.byTooltip('Customise panels'));
    await t.pump(const Duration(seconds: 1));
    expect(scroll.offset, 0);
    final g = await t.startGesture(t.getCenter(find.byIcon(Icons.drag_indicator_rounded).first));
    await t.pump(const Duration(milliseconds: 300));
    await g.moveTo(const Offset(500, 490));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    expect(scroll.offset, greaterThan(50));
    await g.up();
    await t.pump(const Duration(milliseconds: 300));
    final after = scroll.offset;
    await t.pump(const Duration(milliseconds: 300));
    expect(scroll.offset, after, reason: 'scrolling stops once the drag ends');
  });
}
