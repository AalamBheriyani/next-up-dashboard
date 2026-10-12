import 'package:flutter_test/flutter_test.dart';
import 'package:next_up_core/worker_api.dart';

void main() {
  test('clock text becomes minutes after midnight, or the fallback', () {
    expect(clockMinutes('07:30', 0), 450);
    expect(clockMinutes('7:05', 0), 425);
    expect(clockMinutes('24:00', 99), 99);
    expect(clockMinutes('late', 99), 99);
    expect(clockMinutes(null, 99), 99);
  });

  test('the waking day comes from the person, then the owner profile, then 7:00 and 22:00', () {
    expect(AppConfig.fromJson({}).wakeMinutes, 420);
    expect(AppConfig.fromJson({}).windDownMinutes, 1320);
    final owner = AppConfig.fromJson({'profile': {'wake': '06:30', 'windDown': '23:00'}});
    expect((owner.wakeMinutes, owner.windDownMinutes), (390, 1380));
    final own = AppConfig.fromJson({'profile': {'wake': '06:30'}, 'hours': {'wake': '08:00', 'windDown': ''}});
    expect((own.wakeMinutes, own.windDownMinutes), (480, 1320));
  });

  test('the owner\'s links keep only https ones', () {
    final c = AppConfig.fromJson({
      'links': [
        {'name': 'Notion', 'url': 'https://notion.so', 'note': 'archive'},
        {'name': 'Bad', 'url': 'javascript:alert(1)'},
        {'url': 'https://example.com'},
        'nonsense',
      ],
    });
    expect([for (final l in c.links) '${l.name} ${l.url} ${l.note}'], ['Notion https://notion.so archive', 'Link https://example.com ']);
  });

  test('place and sleep come from the profile, and a bad sleep time is dropped', () {
    final c = AppConfig.fromJson({'profile': {'place': 'Toronto', 'sleep': '23:30'}});
    expect((c.profilePlace, c.sleepMinutes), ('Toronto', 1410));
    expect(AppConfig.fromJson({'profile': {'sleep': 'late'}}).sleepMinutes, null);
    expect(AppConfig.fromJson({}).sleepMinutes, null);
  });
}
