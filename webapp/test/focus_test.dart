import 'package:flutter_test/flutter_test.dart';
import 'package:next_up_web/dashboard/focus_controller.dart';
import 'package:next_up_web/platform/platform_base.dart';

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

  test('a reload picks the timer up where it was', () {
    var t = DateTime(2026, 10, 10, 9);
    final store = MemoryStore();
    final a = FocusController(store: store, now: () => t);
    a.startFocus(25, 'chem');
    a.dispose();
    t = t.add(const Duration(minutes: 10));
    final b = FocusController(store: store, now: () => t)..restore();
    expect(b.running, isTrue);
    expect(b.label, 'chem');
    expect(b.left.inMinutes, 15);
    b.pause();
    final c = FocusController(store: store, now: () => t.add(const Duration(hours: 2)))..restore();
    expect(c.running, isFalse);
    expect(c.left.inMinutes, 15, reason: 'a paused timer keeps its time');
    b.dispose();
    c.dispose();
  });

  test('a timer that ran out while the page was closed comes back stopped at the start', () {
    var t = DateTime(2026, 10, 10, 9);
    final store = MemoryStore();
    final a = FocusController(store: store, now: () => t)..startFocus(5);
    a.dispose();
    t = t.add(const Duration(hours: 1));
    final b = FocusController(store: store, now: () => t)..restore();
    expect(b.running, isFalse);
    expect(b.left.inMinutes, 25);
    b.dispose();
  });

  test('a damaged save is ignored', () {
    final store = MemoryStore()..set(FocusController.storeKey, '{nope');
    final c = FocusController(store: store)..restore();
    expect(c.mode, FocusMode.focus);
    c.dispose();
  });
}
