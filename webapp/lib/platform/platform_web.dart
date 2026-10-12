// Browser versions: localStorage and a Web Audio beep, through dart:js_interop (no extra packages).
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'platform_base.dart';

@JS('localStorage')
external _Storage? get _storage;

extension type _Storage._(JSObject _) implements JSObject {
  external String? getItem(String key);
  external void setItem(String key, String value);
}

/// localStorage can be missing or throw (private windows, blocked site data); then it behaves as memory.
class _WebStore implements LocalStore {
  final _fallback = MemoryStore();
  @override
  String? get(String key) {
    try {
      return _storage?.getItem(key) ?? _fallback.get(key);
    } catch (_) {
      return _fallback.get(key);
    }
  }

  @override
  void set(String key, String value) {
    _fallback.set(key, value);
    try {
      _storage?.setItem(key, value);
    } catch (_) {}
  }
}

LocalStore openLocalStore() => _WebStore();

@JS('AudioContext')
extension type _Ctx._(JSObject _) implements JSObject {
  external factory _Ctx();
  external double get currentTime;
  external JSObject get destination;
  external _Osc createOscillator();
  external _Gain createGain();
  external JSPromise<JSAny?> resume();
}

extension type _Param._(JSObject _) implements JSObject {
  external void setValueAtTime(double value, double time);
  external void exponentialRampToValueAtTime(double value, double time);
  external set value(double v);
}

extension type _Osc._(JSObject _) implements JSObject {
  external set type(String v);
  external _Param get frequency;
  external void connect(JSObject node);
  external void start(double when);
  external void stop(double when);
}

extension type _Gain._(JSObject _) implements JSObject {
  external _Param get gain;
  external void connect(JSObject node);
}

_Ctx? _ctx;

/// A few quick square-wave notes, like the current Quest Log. Browsers only allow sound after a click, which is
/// always how this is reached; any failure is ignored because sound is a nicety.
void playBeep(List<double> freqs) {
  try {
    final c = _ctx ??= _Ctx();
    c.resume();
    final t0 = c.currentTime;
    for (var i = 0; i < freqs.length; i++) {
      final o = c.createOscillator(), g = c.createGain();
      o.type = 'square';
      o.frequency.value = freqs[i];
      g.gain.setValueAtTime(.05, t0 + i * .07);
      g.gain.exponentialRampToValueAtTime(.001, t0 + i * .07 + .12);
      o.connect(g);
      g.connect(c.destination);
      o.start(t0 + i * .07);
      o.stop(t0 + i * .07 + .13);
    }
  } catch (_) {}
}

extension type _Location._(JSObject _) implements JSObject {
  external String get hash;
  external String get pathname;
  external String get search;
  external set href(String v);
}

extension type _History._(JSObject _) implements JSObject {
  external void replaceState(JSAny? state, String title, String url);
}

@JS('location')
external _Location get _location;

@JS('history')
external _History get _history;

String currentHash() => _location.hash;

/// Removes `#...` from the address without reloading, so a session token doesn't linger in the address bar.
void clearHash() => _history.replaceState(null, '', _location.pathname + _location.search);

void navigateTo(String url) => _location.href = url;

/// Shows [hash] after the '#' in the address without reloading or adding a history entry.
void setHash(String hash) => _history.replaceState(null, '', _location.pathname + _location.search + (hash.isEmpty ? '' : '#$hash'));

@JS('Notification')
extension type _Notification._(JSObject _) implements JSObject {
  external factory _Notification(String title, JSObject options);
  external static String get permission;
  external static JSPromise<JSString> requestPermission();
}

extension type _Doc._(JSObject _) implements JSObject {
  external String get visibilityState;
}

@JS('document')
external _Doc get _document;

bool get _canNotify => globalContext.has('Notification');

/// Asks once (the browser remembers the answer); called as a timer starts, so it follows a click.
void askNotifyPermission() {
  try {
    if (_canNotify && _Notification.permission == 'default') _Notification.requestPermission();
  } catch (_) {}
}

/// A system notification, only when the tab is in the background (on screen, the page itself shows it).
void notify(String title, String body) {
  try {
    if (!_canNotify || _Notification.permission != 'granted' || _document.visibilityState == 'visible') return;
    final options = JSObject()..['body'] = body.toJS..['tag'] = 'nextup-timer'.toJS;
    _Notification(title, options);
  } catch (_) {}
}
