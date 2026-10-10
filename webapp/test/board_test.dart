import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_up_core/board_layout.dart';
import 'package:next_up_web/board/widget_board.dart';

void main() {
  const items = [
    BoardItem(id: 'a', name: 'Alpha', span: 6, child: SizedBox(height: 50, child: Text('A body'))),
    BoardItem(id: 'b', name: 'Beta', span: 6, child: SizedBox(height: 50, child: Text('B body'))),
    BoardItem(id: 'c', name: 'Gamma', span: 12, child: SizedBox(height: 50, child: Text('C body'))),
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

  testWidgets('arrows reorder and the menu hides a panel', (t) async {
    final saved = <BoardLayout>[];
    await pump(t, width: 1400, editing: true, onChanged: saved.add);
    await t.tap(find.byTooltip('Move later').first);
    await t.pump(const Duration(seconds: 1));
    expect(saved.last.order, ['b', 'a', 'c']);
    await t.tap(find.byTooltip('Hide').last);
    await t.pump(const Duration(seconds: 1));
    expect(saved.last.hidden, ['c']);
  });

  testWidgets('width menu changes a panel to full width', (t) async {
    final saved = <BoardLayout>[];
    await pump(t, width: 1400, editing: true, onChanged: saved.add);
    await t.tap(find.byTooltip('Width').first);
    await t.pumpAndSettle();
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
