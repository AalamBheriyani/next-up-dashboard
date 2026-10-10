// The focus timer's state, kept outside the widget so other parts (Ask Claude's "start the timer", XP
// and time tracking) can use it. Same rules as the current site: a pomodoro, then a short break, with a
// long break after every fourth, and the next session starting by itself.
import 'dart:async';

import 'package:flutter/foundation.dart';

enum FocusMode { focus, shortBreak, longBreak }

const focusLabels = {FocusMode.focus: 'Pomodoro', FocusMode.shortBreak: 'Short break', FocusMode.longBreak: 'Long break'};

/// What happens around the timer. The shell supplies real ones (log XP, track time); tests supply fakes.
class FocusHooks {
  const FocusHooks({this.onFinished, this.onFocusRunning});
  /// A session ran to its end (not skipped). [focus] is true for a pomodoro, false for a break.
  final void Function(bool focus)? onFinished;
  /// A pomodoro started ([on] true, with its label) or stopped (false): the time tracker follows it.
  final void Function(bool on, String label)? onFocusRunning;
}

class FocusController extends ChangeNotifier {
  FocusController({this.focusMin = 25, this.shortMin = 5, this.longMin = 15, this.every = 4, this.autoContinue = true, this.hooks = const FocusHooks(), DateTime Function()? now}) : _now = now ?? DateTime.now {
    _left = _duration(FocusMode.focus);
  }

  int focusMin, shortMin, longMin, every;
  bool autoContinue;
  FocusHooks hooks;
  final DateTime Function() _now;

  FocusMode mode = FocusMode.focus;
  String label = '';
  int done = 0;
  late Duration _left;
  DateTime? _endsAt;
  Timer? _tick;

  bool get running => _tick != null;
  Duration get total => _duration(mode);
  Duration get left => running ? _endsAt!.difference(_now()).isNegative ? Duration.zero : _endsAt!.difference(_now()) : _left;
  double get fraction => total.inMilliseconds == 0 ? 0 : 1 - left.inMilliseconds / total.inMilliseconds;

  Duration _duration(FocusMode m) => Duration(minutes: switch (m) { FocusMode.focus => focusMin, FocusMode.shortBreak => shortMin, FocusMode.longBreak => longMin });

  void setMode(FocusMode m) {
    _halt();
    mode = m;
    label = '';
    _left = _duration(m);
    notifyListeners();
  }

  void start() {
    if (running) return;
    _endsAt = _now().add(_left);
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) => _step());
    if (mode == FocusMode.focus) hooks.onFocusRunning?.call(true, label);
    notifyListeners();
  }

  void pause() {
    if (!running) return;
    _left = left;
    _halt();
    if (mode == FocusMode.focus) hooks.onFocusRunning?.call(false, label);
    notifyListeners();
  }

  void reset() => setMode(mode);

  /// Starts a pomodoro of [minutes] (1 to 60), as Ask Claude does when you agree to start.
  int startFocus(int minutes, [String text = '']) {
    final m = minutes.clamp(1, 60);
    if (running && mode == FocusMode.focus) pause();
    _halt();
    mode = FocusMode.focus;
    label = text;
    _left = Duration(minutes: m);
    start();
    return m;
  }

  void _step() {
    if (_endsAt!.difference(_now()) > Duration.zero) {
      notifyListeners();
      return;
    }
    final wasFocus = mode == FocusMode.focus;
    _halt();
    hooks.onFinished?.call(wasFocus);
    if (wasFocus) {
      hooks.onFocusRunning?.call(false, label);
      done++;
      mode = done % every == 0 ? FocusMode.longBreak : FocusMode.shortBreak;
    } else {
      mode = FocusMode.focus;
    }
    label = '';
    _left = _duration(mode);
    notifyListeners();
    if (autoContinue) start();
  }

  void _halt() {
    _tick?.cancel();
    _tick = null;
    _endsAt = null;
  }

  @override
  void dispose() {
    _halt();
    super.dispose();
  }
}
