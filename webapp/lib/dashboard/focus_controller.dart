// The focus timer's state, kept outside the widget so other parts (Ask Claude's "start the timer", XP
// and time tracking) can use it. Same rules as the current site: a pomodoro, then a short break, with a
// long break after every fourth, and the next session starting by itself.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../platform/platform_base.dart';

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
  FocusController({this.focusMin = 25, this.shortMin = 5, this.longMin = 15, this.every = 4, this.autoContinue = true, this.hooks = const FocusHooks(), this.store, DateTime Function()? now}) : _now = now ?? DateTime.now {
    _left = _duration(FocusMode.focus);
  }

  int focusMin, shortMin, longMin, every;
  bool autoContinue;
  FocusHooks hooks;

  /// Where the timer is remembered on this device, so a reload does not lose it.
  final LocalStore? store;
  static const storeKey = 'nu.web.focus';
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
  double get fraction => total.inMilliseconds == 0 ? 0 : (1 - left.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);

  Duration _duration(FocusMode m) => Duration(minutes: switch (m) { FocusMode.focus => focusMin, FocusMode.shortBreak => shortMin, FocusMode.longBreak => longMin });

  void setMode(FocusMode m) {
    _halt();
    mode = m;
    label = '';
    _left = _duration(m);
    _save();
    notifyListeners();
  }

  void start() {
    if (running) return;
    _endsAt = _now().add(_left);
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) => _step());
    if (mode == FocusMode.focus) hooks.onFocusRunning?.call(true, label);
    _save();
    notifyListeners();
  }

  void pause() {
    if (!running) return;
    _left = left;
    _halt();
    if (mode == FocusMode.focus) hooks.onFocusRunning?.call(false, label);
    _save();
    notifyListeners();
  }

  void reset() => setMode(mode);

  /// Moves the time left by whole minutes (1 to 60), as the arrow keys on the old site's dial did.
  void nudge(int minutes) {
    final m = ((left.inSeconds + 59) ~/ 60 + minutes).clamp(1, 60);
    _left = Duration(minutes: m);
    if (running) _endsAt = _now().add(_left);
    _save();
    notifyListeners();
  }

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
    _save();
    notifyListeners();
    if (autoContinue) start();
  }

  void _save() {
    store?.set(storeKey, jsonEncode({'mode': mode.name, 'label': label, 'done': done, 'leftMs': left.inMilliseconds, 'endsAt': running ? _endsAt!.millisecondsSinceEpoch : null}));
  }

  /// Puts back what [_save] kept. A timer that was running and has not run out carries on; one that ran out
  /// while the page was closed comes back stopped at the start of the same session (nothing is logged for it).
  void restore() {
    try {
      final j = jsonDecode(store?.get(storeKey) ?? 'null');
      if (j is! Map) return;
      mode = FocusMode.values.firstWhere((m) => m.name == j['mode'], orElse: () => FocusMode.focus);
      label = '${j['label'] ?? ''}';
      done = (j['done'] as num?)?.toInt() ?? 0;
      final ends = (j['endsAt'] as num?)?.toInt();
      final remaining = ends == null ? Duration(milliseconds: (j['leftMs'] as num?)?.toInt() ?? 0) : DateTime.fromMillisecondsSinceEpoch(ends).difference(_now());
      _left = remaining > Duration.zero && remaining <= _duration(mode) ? remaining : _duration(mode);
      if (ends != null && remaining > Duration.zero) {
        _endsAt = _now().add(remaining);
        _tick = Timer.periodic(const Duration(milliseconds: 250), (_) => _step());
      }
      notifyListeners();
    } catch (_) {
      // A damaged save is simply ignored.
    }
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
