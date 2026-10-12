import 'package:flutter_test/flutter_test.dart';
import 'package:next_up_core/deadline_source.dart';
import 'package:next_up_core/hours.dart';

void main() {
  RateBlock b(int row, String name) => RateBlock(row: row, date: '2026-10-12', start: '9:00 AM', end: '10:00 AM', name: name, planned: '1', from: DateTime(2026, 10, 12, 9), to: DateTime(2026, 10, 12, 10));
  final blocks = [b(5, 'Chemistry'), b(6, 'Maths')];

  test('the prompt lists each block by row', () {
    final p = ratePrompt(blocks, 'did chem, skipped maths', DateTime(2026, 10, 12, 20));
    expect(p, contains('5 | 2026-10-12 9:00 AM-10:00 AM | Chemistry | 1h planned'));
    expect(p, contains('did chem, skipped maths'));
  });

  test('picks keep only real rows and known statuses, even with text around the JSON', () {
    final r = parseRatings('Sure! {"reply": "Chem done, maths half.", "ratings": [{"row": 5, "status": "done"}, {"row": 6, "status": "PARTIAL", "hours": 0.5}, {"row": 99, "status": "DONE"}, {"row": 5, "status": "MAYBE"}]}', blocks);
    expect(r.reply, 'Chem done, maths half.');
    expect([for (final p in r.picks) '${p.block.name} ${p.status} ${p.hours}'], ['Chemistry DONE null', 'Maths PARTIAL 0.5']);
  });

  test('an answer without JSON is an error', () {
    expect(() => parseRatings('I could not tell.', blocks), throwsA(isA<SourceException>()));
  });
}
