// Anki stats the owner's laptop relay sends to the Worker: cards due per deck and reviews per day.
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'deadline_source.dart';

class AnkiDeck {
  const AnkiDeck(this.name, this.newCards, this.learn, this.review);
  final String name;
  final int newCards, learn, review;
  int get due => newCards + learn + review;
}

class AnkiStats {
  const AnkiStats({required this.decks, required this.days, this.at});
  final List<AnkiDeck> decks;
  final Map<String, int> days; // 'yyyy-mm-dd' -> reviews
  final DateTime? at;
  int get totalDue => decks.fold(0, (n, d) => n + d.due);

  static AnkiStats? parse(Object? j) {
    if (j is! Map || j['decks'] is! List) return null;
    int n(Object? v) => (v as num?)?.toInt() ?? 0;
    return AnkiStats(
      decks: [for (final d in j['decks'] as List) if (d is Map) AnkiDeck('${d['name']}', n(d['new']), n(d['learn']), n(d['review']))],
      days: {for (final e in (j['days'] as List? ?? const [])) if (e is List && e.length > 1) '${e[0]}': n(e[1])},
      at: j['at'] == null ? null : DateTime.tryParse('${j['at']}')?.toLocal(),
    );
  }
}

abstract class AnkiSource {
  Future<AnkiStats?> load();
}

class WorkerAnkiSource implements AnkiSource {
  WorkerAnkiSource(this.token);
  final Future<String?> Function() token;

  @override
  Future<AnkiStats?> load() async {
    final t = await token();
    if (t == null) return null;
    try {
      final r = await http.get(Uri.parse('$workerUrl/anki'), headers: {'Authorization': 'Bearer $t'});
      return r.statusCode == 200 ? AnkiStats.parse(jsonDecode(r.body)) : null;
    } catch (_) {
      return null; // Anki is optional; a missing panel is better than an error
    }
  }
}
