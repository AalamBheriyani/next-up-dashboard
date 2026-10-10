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
}
