import 'package:flutter_test/flutter_test.dart';
import 'package:next_up_core/deadline.dart';

void main() {
  test('lists keep their TickTick colour, others get distinct palette colours', () {
    final c = listColors({'a': 'School', 'b': 'Personal', 'c': 'Work'}, {'a': '#4d8dff', 'c': 'nope'});
    expect(c['a'], 0xFF4D8DFF);
    expect(c['b'], isNot(0xFF4D8DFF));
    expect(c['c'], isNot(c['b']));
  });

  test('tags and colour come through from a task', () {
    final d = Deadline.fromTask({'id': '1', 'projectId': 'a', 'title': 'Essay', 'dueDate': '2026-10-12T09:00:00.000+0000', 'tags': ['school']}, {'a': 'School'}, {'a': 0xFF22C55E})!;
    expect(d.tags, ['school']);
    expect(d.color, 0xFF22C55E);
  });
}
