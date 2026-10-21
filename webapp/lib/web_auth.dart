// Sign-in on the web. The main way is the Worker's permanent sign-in, the same one the current site uses: you
// sign in with Google once, the Worker keeps the Google refresh token, and this page keeps only a long-lived
// session token, trading it for a fresh one-hour Google access token whenever one is needed. A reload, or an
// hour passing, therefore doesn't sign you out. If the Worker can't do that, it falls back to the Google pop-up
// (an access token that lasts an hour and is forgotten on reload). The pop-up must start from a button press.
import 'dart:async';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:next_up_core/session.dart';

import 'platform/platform.dart';

/// The web OAuth client; same public value as docs/config.js.
const webClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID',
    defaultValue: '385720599418-u8qoimd49q4s9rpb612fteug3ocpkk27.apps.googleusercontent.com');

// Deadlines need only the first two; the dashboard reads Calendar events and "Add to Calendar" writes one
// (the same scopes as the Worker's sign-in and the old site), and Track, Adherence and Rate read and write
// the person's own Time Tracker sheet.
const webScopes = <String>['openid', 'email', 'https://www.googleapis.com/auth/calendar.events', 'https://www.googleapis.com/auth/spreadsheets'];

const _sessionKey = 'nu.web.session';

class WebAuth {
  WebAuth({LocalStore? store, WorkerSession? server, String Function()? readHash, void Function()? clearAddressHash, void Function(String)? navigate, bool? native, void Function(Map<String, Object?>)? post, void Function(void Function(String?, int, String?))? listen})
      : _native = native ?? inNativeApp,
        _post = post ?? postNative,
        _store = store ?? openLocalStore(),
        _server = server ?? WorkerSession(),
        _clearHash = clearAddressHash ?? clearHash,
        _navigate = navigate ?? navigateTo {
    // Coming back from the Worker's sign-in page: the session token is in the address after the '#'.
    final m = RegExp(r'nu_session=(nu_[0-9a-f]+)').firstMatch((readHash ?? currentHash)());
    if (m != null) {
      _store.set(_sessionKey, m[1]!);
      _clearHash();
    }
    final saved = _store.get(_sessionKey);
    _session = saved == null || saved.isEmpty ? null : saved;
    _permanent = _server.permanent();
    if (_native) (listen ?? onNativeAuth)(_nativeAnswer);
  }

  final bool _native; // inside the Android/iOS app, which signs in with Google natively
  final void Function(Map<String, Object?>) _post;
  Completer<void>? _nativeWait;
  final LocalStore _store;
  final WorkerSession _server;
  final void Function() _clearHash;
  final void Function(String) _navigate;
  late final Future<bool> _permanent;

  String? _session; // the long-lived Worker session, when signed in permanently
  String? _token;
  DateTime _expires = DateTime.fromMillisecondsSinceEpoch(0);
  Future<String?>? _pending;

  // Started at launch but never awaited before the first frame: if Google's script is blocked or slow
  // the page still shows, and signing in reports the failure.
  static final Future<void> ready = GoogleSignIn.instance.initialize(clientId: webClientId);

  bool get _fresh => _token != null && _expires.isAfter(DateTime.now().add(const Duration(minutes: 2)));

  /// True when there is a usable sign-in: a live access token, or a saved session that can get one.
  bool get signedIn => _fresh || _session != null || (_token != null && DateTime.now().isBefore(_expires));

  Future<void> signIn() async {
    // Google refuses sign-in inside an app's web view, so the app signs in and hands over an access token.
    if (_native) {
      final wait = _nativeWait = Completer<void>();
      _post({'type': 'signin'});
      return wait.future;
    }
    if (await _permanent) {
      _navigate(_server.startUrl());
      return Completer<void>().future; // the page is leaving for Google; nothing more to do here
    }
    await ready;
    final auth = await GoogleSignIn.instance.authorizationClient.authorizeScopes(webScopes);
    _token = auth.accessToken;
    _expires = DateTime.now().add(const Duration(minutes: 50)); // Google tokens last an hour
  }

  void _nativeAnswer(String? token, int expiresIn, String? error) {
    final wait = _nativeWait;
    _nativeWait = null;
    if (token != null && token.isNotEmpty) {
      _token = token;
      _expires = DateTime.now().add(Duration(seconds: expiresIn > 0 ? expiresIn : 3300));
      wait?.complete();
    } else {
      wait?.completeError(Exception(error ?? 'Sign-in failed.'));
    }
  }

  void signOut() {
    if (_native) _post({'type': 'signout'});
    final s = _session;
    _token = null;
    _session = null;
    _store.set(_sessionKey, '');
    if (s != null) unawaited(_server.logout(s));
  }

  /// A current token, or null when signed out or expired (the screen then asks to sign in again).
  Future<String?> token() async {
    if (_fresh) return _token;
    if (_session != null) return _pending ??= _renew().whenComplete(() => _pending = null);
    return signedIn ? _token : null;
  }

  Future<String?> _renew() async {
    final s = _session;
    if (s == null) return null;
    final r = await _server.exchange(s);
    if (r.token != null) {
      _token = r.token;
      _expires = DateTime.now().add(Duration(seconds: r.expiresIn));
      return _token;
    }
    if (r.expired && _session == s) {
      _session = null;
      _store.set(_sessionKey, '');
    }
    return null;
  }
}
