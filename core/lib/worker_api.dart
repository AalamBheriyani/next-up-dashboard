// The Worker's per-person settings: which sheets to use, the accent colour, TickTick connected or not.
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'board_layout.dart';
import 'deadline_source.dart';

class AppConfig {
  const AppConfig({this.email = '', this.owner = false, this.sheetId = '', this.questSheetId = '', this.accent = '', this.redDeadlines = true, this.ticktick = false, this.claudeApi = false, this.relay = false, this.layout, this.profileName = '', this.profileRules = ''});
  final String email;
  final bool owner;
  final String sheetId; // Weekly Time Tracker
  final String questSheetId; // XP Tracker
  final String accent; // '#rrggbb' or empty for the default
  final bool redDeadlines;
  final bool ticktick;
  final bool claudeApi;
  final bool relay;
  final String profileName, profileRules; // from the server's PROFILE (owner only), used by Ask Claude
  final BoardLayout? layout; // the arrangement of dashboard panels, shared by every device

  factory AppConfig.fromJson(Map<String, dynamic> j) {
    final profile = j['profile'] is Map ? j['profile'] as Map : const {};
    final theme = j['theme'] is Map ? j['theme'] as Map : const {};
    return AppConfig(
      email: '${j['email'] ?? ''}',
      owner: j['owner'] == true,
      sheetId: '${j['sheetId'] ?? ''}',
      questSheetId: '${j['questSheetId'] ?? ''}',
      accent: '${theme['accent'] ?? ''}',
      redDeadlines: theme['redDeadlines'] != false,
      ticktick: j['ticktick'] == true,
      claudeApi: j['claudeApi'] == true,
      relay: j['relay'] == true,
      profileName: '${profile['name'] ?? ''}',
      profileRules: '${profile['rules'] ?? ''}',
      layout: j['webLayout'] is Map ? BoardLayout.fromJson(j['webLayout']) : null,
    );
  }
}

abstract class ConfigSource {
  Future<AppConfig> load();
  Future<void> save({String? sheetId, String? questSheetId, String? accent, bool? redDeadlines, BoardLayout? layout});
}

class WorkerConfigSource implements ConfigSource {
  WorkerConfigSource(this.token);
  final Future<String?> Function() token;

  Future<http.Response> _send(Future<http.Response> Function(Map<String, String> h) go) async {
    final t = await token();
    if (t == null) throw SourceException('Sign in first.', signedOut: true);
    try {
      final res = await go({'Authorization': 'Bearer $t', 'Content-Type': 'application/json'});
      if (res.statusCode == 401) throw SourceException('Your sign-in expired. Sign in again.', signedOut: true);
      if (res.statusCode == 403) throw SourceException("This Google account isn't allowed yet. Ask the owner to add it.");
      if (res.statusCode >= 400) {
        String? msg;
        try {
          msg = (jsonDecode(res.body) as Map)['error'] as String?;
        } catch (_) {}
        throw SourceException(msg ?? 'Something went wrong (${res.statusCode}).');
      }
      return res;
    } on http.ClientException {
      throw SourceException("Can't reach Next Up. Check your connection.");
    }
  }

  @override
  Future<AppConfig> load() async {
    final res = await _send((h) => http.get(Uri.parse('$workerUrl/config'), headers: h));
    return AppConfig.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  @override
  Future<void> save({String? sheetId, String? questSheetId, String? accent, bool? redDeadlines, BoardLayout? layout}) async {
    final body = <String, Object?>{
      'sheetId': ?sheetId,
      'questSheetId': ?questSheetId,
      if (layout != null) 'webLayout': layout.toJson(),
      if (accent != null || redDeadlines != null) 'theme': {'accent': accent ?? '', 'redDeadlines': redDeadlines ?? true},
    };
    await _send((h) => http.post(Uri.parse('$workerUrl/settings'), headers: h, body: jsonEncode(body)));
  }
}
