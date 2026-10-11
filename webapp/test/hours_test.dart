import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_up_web/dashboard/clock_header.dart';
import 'package:next_up_web/pages/settings_screen.dart';

void main() {
  test('times are saved as HH:MM and shown as 12-hour text', () {
    expect(clockText(450), '07:30');
    expect(clockText(1320), '22:00');
    expect(clockLabel(450), '7:30 AM');
    expect(clockLabel(0), '12:00 AM');
    expect(clockLabel(13 * 60), '1:00 PM');
  });

  testWidgets('the header counts down to the wind-down time you set', (t) async {
    Future<void> show(int wind) async {
      await t.pumpWidget(MaterialApp(home: Scaffold(body: ClockHeader(now: () => DateTime(2026, 10, 10, 20), wakeMinutes: 7 * 60, windDownMinutes: wind))));
    }

    await show(22 * 60);
    expect(find.text('2h 0m until wind-down'), findsOneWidget);
    await show(21 * 60);
    expect(find.text('1h 0m until wind-down'), findsOneWidget);
    expect(find.text('Work time left today'), findsOneWidget);
    expect(find.text('Wake 7:00 AM'), findsOneWidget);
    expect(find.text('Wind-down 9:00 PM'), findsOneWidget);
    await show(19 * 60);
    expect(find.text('Wind-down time. Log XP and rest.'), findsOneWidget);
  });
}
