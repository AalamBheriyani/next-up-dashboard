// XP waiting to reach the XP sheet. A quest tap or a finished timer is kept on this device until the sheet
// takes it, so XP earned offline or signed out is not lost (the old site's xp.js queue).
import 'dart:convert';

import 'package:next_up_core/quest.dart';

import 'platform/platform_base.dart';

/// The account that last signed in on this device, so its queued XP is not sent for someone else.
const lastEmailKey = 'nu.web.lastEmail';

class XpQueue {
  XpQueue(this.store);
  final LocalStore store;
  static const key = 'nu.web.xp.queue';

  List<XpRow> get pending {
    try {
      final j = jsonDecode(store.get(key) ?? '[]');
      if (j is! List) return const [];
      return [
        for (final r in j)
          if (r is Map) XpRow(t: (r['t'] as num).toInt(), q: '${r['q']}', name: '${r['name']}', base: (r['base'] as num).toDouble(), mult: (r['mult'] as num).toDouble(), xp: (r['xp'] as num).toInt(), kind: '${r['kind']}'),
      ];
    } catch (_) {
      return const []; // a damaged queue is dropped rather than blocking every save
    }
  }

  void _write(List<XpRow> rows) => store.set(key, jsonEncode([for (final r in rows) {'t': r.t, 'q': r.q, 'name': r.name, 'base': r.base, 'mult': r.mult, 'xp': r.xp, 'kind': r.kind}]));

  void add(Iterable<XpRow> rows) => _write([...pending, ...rows]);

  /// Sends everything waiting in one append; on success the queue is emptied. Throws when the sheet refuses.
  Future<int> flush(XpRepository repo, int dayStartHour) async {
    final rows = pending;
    if (rows.isEmpty) return 0;
    await repo.append(rows, dayStartHour);
    // Keep anything queued while the append was in flight.
    final sent = {for (final r in rows) '${r.t}|${r.q}'};
    _write([for (final r in pending) if (!sent.contains('${r.t}|${r.q}')) r]);
    return rows.length;
  }
}
