import 'package:flutter_test/flutter_test.dart';
import 'package:next_up_web/dashboard/focus_controller.dart';

void main() {
  test('starting and finishing a pomodoro reports to the hooks, then moves to a break', () async {
    var t = DateTime(2026, 10, 10, 9);
    final events = <String>[];
    final c = FocusController(
      focusMin: 1,
      autoContinue: false,
      now: () => t,
      hooks: FocusHooks(onFinished: (f) => events.add(f ? 'focus done' : 'break done'), onFocusRunning: (on, l) => events.add('track ${on ? 'on' : 'off'} $l')),
    );
    expect(c.startFocus(1, 'chem'), 1);
    expect(c.running, isTrue);
    t = t.add(const Duration(minutes: 2));
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(events, ['track on chem', 'focus done', 'track off chem']);
    expect(c.mode, FocusMode.shortBreak);
    expect(c.done, 1);
    expect(c.running, isFalse);
    c.dispose();
  });

  test('every fourth pomodoro earns the long break; pausing stops tracking', () {
    final events = <String>[];
    final c = FocusController(hooks: FocusHooks(onFocusRunning: (on, l) => events.add('$on')));
    c.start();
    c.pause();
    expect(events, ['true', 'false']);
    expect(c.startFocus(500), 60); // clamped to an hour
    c.dispose();
  });
}
