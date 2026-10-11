// Staying signed in: the Worker keeps a Google refresh token and swaps a long-lived session token for a fresh
// one-hour Google access token whenever one is needed. This is the same sign-in the current site uses.
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'deadline_source.dart';

class WorkerSession {
  WorkerSession({this.base = workerUrl, http.Client? client}) : _client = client ?? http.Client();
  final String base;
  final http.Client _client;

  /// Whether the Worker is set up to keep people signed in. False when unreachable, so callers can fall back.
  Future<bool> permanent() async {
    try {
      final r = await _client.get(Uri.parse('$base/auth/info')).timeout(const Duration(seconds: 8));
      return r.statusCode == 200 && (jsonDecode(r.body) as Map)['permanent'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Where to send the browser to sign in; it comes back to /beta/ with a session token in the address.
  String startUrl() => '$base/auth/start?return=beta';

  /// A fresh Google access token for this session. Null with [expired] true when the session is no longer
  /// good (sign in again); null with [expired] false when the Worker couldn't be reached (try again later).
  Future<({String? token, int expiresIn, bool expired})> exchange(String session) async {
    try {
      final r = await _client.post(Uri.parse('$base/auth/token'), headers: {'Authorization': 'Bearer $session'});
      if (r.statusCode == 401) return (token: null, expiresIn: 0, expired: true);
      if (r.statusCode != 200) return (token: null, expiresIn: 0, expired: false);
      final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map;
      return (token: '${j['access_token']}', expiresIn: (j['expires_in'] as num?)?.toInt() ?? 3000, expired: false);
    } catch (_) {
      return (token: null, expiresIn: 0, expired: false);
    }
  }

  Future<void> logout(String session) async {
    try {
      await _client.post(Uri.parse('$base/auth/logout'), headers: {'Authorization': 'Bearer $session'});
    } catch (_) {}
  }
}
