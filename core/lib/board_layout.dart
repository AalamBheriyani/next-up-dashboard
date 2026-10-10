// The widget layout: which panels show, in what order, how wide and how tall. One layout per person,
// saved to their account, so the phone and the computer show the same arrangement. Widths are shares of
// a 12-column grid; a narrow screen simply stacks them, so nothing needs saving per device.

const boardSpans = [3, 4, 6, 8, 9, 12];
const boardHeights = ['s', 'm', 'l']; // compact, medium, tall; anything else is automatic

class BoardLayout {
  const BoardLayout({this.order = const [], this.span = const {}, this.height = const {}, this.hidden = const []});
  final List<String> order;
  final Map<String, int> span;
  final Map<String, String> height;
  final List<String> hidden;

  factory BoardLayout.fromJson(Object? j) {
    if (j is! Map) return const BoardLayout();
    List<String> ids(Object? v) => v is List ? [for (final x in v) '$x'] : const [];
    return BoardLayout(
      order: ids(j['order']),
      span: {for (final e in (j['span'] is Map ? j['span'] as Map : const {}).entries) if (boardSpans.contains((e.value as num?)?.toInt())) '${e.key}': (e.value as num).toInt()},
      height: {for (final e in (j['h'] is Map ? j['h'] as Map : const {}).entries) if (boardHeights.contains(e.value)) '${e.key}': '${e.value}'},
      hidden: ids(j['hidden']),
    );
  }

  Map<String, Object> toJson() => {'order': order, 'span': span, 'h': height, 'hidden': hidden};

  /// This layout limited to the panels that exist now: unknown ids are dropped, new panels go last.
  BoardLayout resolved(List<String> known) => BoardLayout(
        order: [...order.where(known.contains).toSet(), ...known.where((k) => !order.contains(k))],
        span: span,
        height: height,
        hidden: hidden.where(known.contains).toList(),
      );

  int spanOf(String id, int fallback) => span[id] ?? fallback;
  bool isHidden(String id) => hidden.contains(id);

  BoardLayout _with({List<String>? order, Map<String, int>? span, Map<String, String>? height, List<String>? hidden}) =>
      BoardLayout(order: order ?? this.order, span: span ?? this.span, height: height ?? this.height, hidden: hidden ?? this.hidden);

  /// Drops [id] into the place [target] holds now, so the others shift along.
  BoardLayout moveTo(String id, String target) {
    if (id == target || !order.contains(id) || !order.contains(target)) return this;
    final o = [...order]..remove(id);
    o.insert(o.indexOf(target) + (order.indexOf(id) < order.indexOf(target) ? 1 : 0), id);
    return _with(order: o);
  }

  /// One step earlier (-1) or later (+1) among [visible] ids, so a hidden panel is never in the way.
  BoardLayout step(String id, int dir, List<String> visible) {
    final k = visible.indexOf(id) + dir;
    if (k < 0 || k >= visible.length || !visible.contains(id)) return this;
    return moveTo(id, visible[k]);
  }

  BoardLayout withSpan(String id, int s) => _with(span: {...span, id: s});
  BoardLayout withHeight(String id, String? h) => _with(height: {...height}..remove(id)..addAll({'$id': ?h}));
  BoardLayout toggleHidden(String id) => _with(hidden: isHidden(id) ? hidden.where((x) => x != id).toList() : [...hidden, id]);
}
