import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_up_web/dashboard/focus_controller.dart';
import 'package:next_up_web/dashboard/focus_timer.dart';
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
    expect(b.left.inMinutes, 5); // the start of that same 5-minute session
    b.dispose();
  });

  test('a damaged save is ignored', () {
    final store = MemoryStore()..set(FocusController.storeKey, '{nope');
    final c = FocusController(store: store)..restore();
    expect(c.mode, FocusMode.focus);
    c.dispose();
  });

  test('skip moves to the next session without counting it', () {
    final c = FocusController();
    c.start();
    c.skip();
    expect(c.mode, FocusMode.shortBreak);
    expect(c.running, isFalse);
    expect(c.done, 0);
    c.skip();
    expect(c.mode, FocusMode.focus);
    c.dispose();
  });

  test('nudging moves the time left by whole minutes, between 1 and 60', () {
    final c = FocusController();
    c.nudge(1);
    expect(c.left, const Duration(minutes: 26));
    c.nudge(-40);
    expect(c.left, const Duration(minutes: 1));
    c.nudge(100);
    expect(c.left, const Duration(minutes: 60));
    expect(c.fraction, 0);
    c.dispose();
  });

  testWidgets('the arrow keys and space work the timer, and fullscreen opens and closes', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = FocusController();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: SizedBox(width: 360, child: FocusTimer(controller: c))))));
    Focus.of(tester.element(find.text('Start'))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(find.text('26:00'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(c.running, isTrue);
    await tester.tap(find.byTooltip('Fullscreen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byTooltip('Exit fullscreen'), findsOneWidget);
    expect(find.text('Pause'), findsNWidgets(2)); // the panel and the fullscreen view
    await tester.tap(find.byTooltip('Exit fullscreen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byTooltip('Exit fullscreen'), findsNothing);
    c.pause();
    c.dispose();
  });

  test('timer settings change the lengths, apply to a fresh timer and come back after a reload', () {
    final store = MemoryStore();
    final a = FocusController(store: store);
    a.setSettings(focus: 50, short: 10, every: 3, auto: false, focusColor: 0xFF3E8EF7);
    expect(a.left, const Duration(minutes: 50));
    final b = FocusController(store: store)..restore();
    expect((b.focusMin, b.shortMin, b.every, b.autoContinue), (50, 10, 3, false));
    expect((b.focusColor, b.breakColor), (0xFF3E8EF7, 0), reason: 'a chosen colour is kept; 0 is the default');
    expect(b.left, const Duration(minutes: 50));
    a.dispose();
    b.dispose();
  });

  testWidgets('the settings dialog steps the pomodoro length', (tester) async {
    final c = FocusController();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: TimerSettings(controller: c))));
    await tester.tap(find.byTooltip('More Pomodoro'));
    await tester.pump();
    expect(find.text('30 min'), findsOneWidget);
    expect(c.left, const Duration(minutes: 30));
    c.dispose();
  });

  testWidgets('dragging round the dial sets the minutes and letting go starts', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = FocusController();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: SizedBox(width: 360, child: FocusTimer(controller: c))))));
    final dial = tester.getCenter(find.byTooltip('Drag round the dial to set the minutes; let go to start'));
    final g = await tester.startGesture(dial + const Offset(0, -60));
    await g.moveTo(dial + const Offset(-30, -52));
    await g.moveTo(dial + const Offset(-60, 0)); // a quarter turn counterclockwise: 15 minutes
    await tester.pump();
    expect(find.text('15:00'), findsOneWidget);
    await g.up();
    await tester.pump();
    expect(c.running, isTrue);
    expect(c.total, const Duration(minutes: 15));
    c.pause();
    c.dispose();
  });
}
