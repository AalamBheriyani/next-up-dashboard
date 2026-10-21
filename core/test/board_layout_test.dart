import 'package:flutter_test/flutter_test.dart';
import 'package:next_up_core/board_layout.dart';

void main() {
  const known = ['a', 'b', 'c', 'd'];

  test('resolved keeps the saved order, drops unknown ids and adds new panels last', () {
    final l = BoardLayout.fromJson({'order': ['c', 'zzz', 'a'], 'hidden': ['zzz', 'b']}).resolved(known);
    expect(l.order, ['c', 'a', 'b', 'd']);
    expect(l.hidden, ['b']);
  });

  test('moveTo takes the target place in either direction', () {
    final l = const BoardLayout(order: known);
    expect(l.moveTo('a', 'c').order, ['b', 'c', 'a', 'd']);
    expect(l.moveTo('d', 'b').order, ['a', 'd', 'b', 'c']);
  });

  test('step skips over hidden panels', () {
    final l = const BoardLayout(order: known, hidden: ['b']);
    expect(l.step('a', 1, ['a', 'c', 'd']).order, ['b', 'c', 'a', 'd']);
    expect(l.step('a', -1, ['a', 'c', 'd']).order, known);
  });

  test('width, height and hide round-trip through JSON; bad values are ignored', () {
    final l = const BoardLayout(order: known).withSpan('a', 6).withHeight('b', 'm').toggleHidden('c');
    final back = BoardLayout.fromJson(l.toJson());
    expect(back.span, {'a': 6});
    expect(back.height, {'b': 'm'});
    expect(back.hidden, ['c']);
    expect(BoardLayout.fromJson({'span': {'a': 5}, 'h': {'a': 'xl'}}).span, isEmpty);
    expect(l.withHeight('b', null).height, isEmpty);
    expect(l.toggleHidden('c').hidden, isEmpty);
  });

  test('saving one page keeps the other pages\' panels', () {
    final full = const BoardLayout(order: ['a', 'b', 'x', 'y'], span: {'a': 6, 'x': 4}, hidden: ['y']);
    final page = const BoardLayout(order: ['b', 'a'], span: {'b': 3}, hidden: ['a']);
    final merged = full.withPage(page, ['a', 'b']);
    expect(merged.order, ['x', 'y', 'b', 'a']);
    expect(merged.span, {'x': 4, 'b': 3});
    expect(merged.hidden, ['y', 'a']);
    // resetting a page (empty layout) puts its panels back in their default order and drops its sizes
    final reset = merged.withPage(const BoardLayout(), ['a', 'b']);
    expect(reset.order, ['x', 'y', 'a', 'b']);
    expect(reset.span, {'x': 4});
    expect(reset.hidden, ['y']);
  });
}
