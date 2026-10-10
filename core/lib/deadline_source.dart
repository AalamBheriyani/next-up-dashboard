// Where deadlines come from. The app reads the same Cloudflare Worker as the website, so TickTick
// stays the single list and nothing personal is stored in the app.
import 'dart:convert';
import 'package:http/http.dart' as http;

import 'deadline.dart';

const workerUrl = String.fromEnvironment('WORKER_URL', defaultValue: 'https://next-up-dashboard.aalambheriyani.workers.dev');

class SourceException implements Exception {
  SourceException(this.message, {this.signedOut = false, this.notConnected = false});
  final String message;
  final bool signedOut; // token missing or expired: ask the person to sign in again
  final bool notConnected; // TickTick isn't connected yet
  @override
  String toString() => message;
}

abstract class DeadlineSource {
  Future<List<Deadline>> load();
  Future<void> complete(Deadline d);
}

/// Reads `/ticktick/tasks` and `/ticktick/complete` with a Google access token.
class WorkerDeadlineSource implements DeadlineSource {
  WorkerDeadlineSource(this.token);
  final Future<String?> Function() token;

  Future<Map<String, dynamic>> _call(String method, String path, {Object? body}) async {
    final t = await token();
    if (t == null) throw SourceException('Sign in to see your deadlines.', signedOut: true);
    final headers = {'Authorization': 'Bearer $t', if (body != null) 'Content-Type': 'application/json'};
    final uri = Uri.parse(workerUrl + path);
    http.Response res;
    try {
      res = method == 'POST' ? await http.post(uri, headers: headers, body: jsonEncode(body)) : await http.get(uri, headers: headers);
    } on http.ClientException {
      throw SourceException("Can't reach Next Up. Check your connection.");
    }
    Map<String, dynamic> data = {};
    try {
      data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {}
    if (res.statusCode == 401) throw SourceException('Your sign-in expired. Sign in again.', signedOut: true);
    if (res.statusCode == 403) throw SourceException("This Google account isn't allowed yet. Ask the owner to add it.");
    if (res.statusCode == 409) throw SourceException('Connect TickTick once in the Classic tab, then come back.', notConnected: true);
    if (res.statusCode >= 400) throw SourceException('${data['error'] ?? 'Something went wrong (${res.statusCode}).'}');
    return data;
  }

  @override
  Future<List<Deadline>> load() async {
    // Everything due up to a year ahead; overdue items have no lower bound.
    final to = DateTime.now().add(const Duration(days: 365)).toUtc().toIso8601String();
    final data = await _call('GET', '/ticktick/tasks?to=${Uri.encodeQueryComponent(to)}');
    final names = <String, String>{
      for (final p in (data['projects'] as List? ?? const []))
        '${(p as Map)['id']}': '${p['name'] ?? ''}',
    };
    return [
      for (final t in (data['tasks'] as List? ?? const []))
        ?Deadline.fromTask(t as Map<String, dynamic>, names),
    ];
  }

  @override
  Future<void> complete(Deadline d) =>
      _call('POST', '/ticktick/complete', body: {'projectId': d.projectId, 'taskId': d.id, 'title': d.title, 'list': d.list});
}
