// The Worker's per-person settings: which sheets to use, the accent colour, TickTick connected or not.
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'board_layout.dart';
import 'deadline_source.dart';

const defaultWakeMinutes = 7 * 60;
const defaultWindDownMinutes = 22 * 60;

/// Minutes after midnight for a "HH:MM" text ("7:30" and "07:30" both work), or [fallback] when it isn't one.
int clockMinutes(Object? text, int fallback) {
  final m = RegExp(r'^\s*(\d{1,2}):(\d{2})\s*$').firstMatch('${text ?? ''}');
  if (m == null) return fallback;
  final h = int.parse(m[1]!), min = int.parse(m[2]!);
  return h > 23 || min > 59 ? fallback : h * 60 + min;
}

class AppConfig {
  const AppConfig({this.email = '', this.owner = false, this.sheetId = '', this.questSheetId = '', this.accent = '', this.redDeadlines = true, this.ticktick = false, this.claudeApi = false, this.relay = false, this.layout, this.profileName = '', this.profileRules = '', this.profilePlace = '', this.sleepMinutes, this.wakeMinutes = defaultWakeMinutes, this.windDownMinutes = defaultWindDownMinutes, this.links = const [], this.calendars = const []});
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
  final int wakeMinutes, windDownMinutes; // the waking day, as minutes after midnight
  final String profilePlace; // where the owner is, shown next to the date (the old "Next up · place")
  final int? sleepMinutes; // lights out, shown under the day bar when set
  final BoardLayout? layout; // the arrangement of dashboard panels, shared by every device
  final List<QuickLink> links; // the owner's own "Jump to" links (the Worker's LINKS)
  final List<String> calendars; // calendar ids shown with the primary one

  factory AppConfig.fromJson(Map<String, dynamic> j) {
    final profile = j['profile'] is Map ? j['profile'] as Map : const {};
    final theme = j['theme'] is Map ? j['theme'] as Map : const {};
    // Hours the person chose themselves win over the owner's server profile; otherwise 7:00 and 22:00.
    final hours = j['hours'] is Map ? j['hours'] as Map : const {};
    int pick(String key, int fallback) => clockMinutes(hours[key], clockMinutes(profile[key], fallback));
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
      profilePlace: '${profile['place'] ?? ''}',
      sleepMinutes: switch (clockMinutes(profile['sleep'], -1)) { < 0 => null, final m => m },
      wakeMinutes: pick('wake', defaultWakeMinutes),
      windDownMinutes: pick('windDown', defaultWindDownMinutes),
      layout: j['webLayout'] is Map ? BoardLayout.fromJson(j['webLayout']) : null,
      links: [for (final l in (j['links'] is List ? j['links'] as List : const [])) ?QuickLink.fromJson(l)],
      calendars: [for (final c in (j['calendars'] is List ? j['calendars'] as List : const [])) if (c is String && c.isNotEmpty) c],
    );
  }
}

/// A link on the dashboard's "Jump to" panel.
class QuickLink {
  const QuickLink(this.name, this.url, {this.note = ''});
  final String name, url, note;

  /// Only https links are kept, as on the current site.
  static QuickLink? fromJson(Object? j) {
    if (j is! Map) return null;
    final url = '${j['url'] ?? ''}';
    if (!url.startsWith('https://')) return null;
    final name = '${j['name'] ?? ''}'.trim();
    return QuickLink(name.isEmpty ? 'Link' : name, url, note: '${j['note'] ?? ''}');
  }
}

abstract class ConfigSource {
  Future<AppConfig> load();
  Future<void> save({String? sheetId, String? questSheetId, String? accent, bool? redDeadlines, BoardLayout? layout, String? wake, String? windDown, List<String>? calendars});
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
  Future<void> save({String? sheetId, String? questSheetId, String? accent, bool? redDeadlines, BoardLayout? layout, String? wake, String? windDown, List<String>? calendars}) async {
    final body = <String, Object?>{
      'sheetId': ?sheetId,
      'questSheetId': ?questSheetId,
      'calendars': ?calendars,
      if (layout != null) 'webLayout': layout.toJson(),
      if (wake != null || windDown != null) 'hours': {'wake': wake ?? '', 'windDown': windDown ?? ''},
      if (accent != null || redDeadlines != null) 'theme': {'accent': accent ?? '', 'redDeadlines': redDeadlines ?? true},
    };
    await _send((h) => http.post(Uri.parse('$workerUrl/settings'), headers: h, body: jsonEncode(body)));
  }
}
