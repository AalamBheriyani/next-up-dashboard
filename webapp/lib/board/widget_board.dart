// The widget board: panels on a 12-column grid that can be moved, resized and hidden, the same idea as the
// current site's Customise mode. It works by touch and mouse (a drag handle plus plain buttons and menus),
// and the saved layout is the same on every device: wide screens use the widths, narrow ones stack.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:next_up_core/board_layout.dart';
import 'package:next_up_core/theme.dart';

import '../motion.dart';

/// One panel the board can place. [span] is its default width out of 12.
class BoardItem {
  const BoardItem({required this.id, required this.name, required this.span, required this.child});
  final String id, name;
  final int span;
  final Widget child;
}

const _heightPx = {'s': 280.0, 'm': 440.0, 'l': 680.0};
const _spanNames = {3: '¼ width', 4: '⅓ width', 6: '½ width', 8: '⅔ width', 9: '¾ width', 12: 'Full width'};
const _heightNames = {null: 'Auto height', 's': 'Compact', 'm': 'Medium', 'l': 'Tall'};
const boardGap = 16.0;

/// Columns a panel takes at this width: as saved on a wide screen, at least half on a medium one, full on a phone.
int effectiveSpan(int saved, double width) => width >= 1100 ? saved : (width >= 700 ? (saved < 6 ? 6 : saved) : 12);

/// How fast (pixels per frame, negative = up) the page should scroll while a panel is dragged at [y], given the
/// scrolling area's [top] and [bottom]. Zero in the middle; it speeds up as the pointer nears an edge.
double autoScrollSpeed(double y, double top, double bottom, {double edge = 90, double max = 20}) {
  if (y < top + edge) return -((top + edge - y) / edge).clamp(0.0, 1.0) * max;
  if (y > bottom - edge) return ((y - (bottom - edge)) / edge).clamp(0.0, 1.0) * max;
  return 0;
}

class WidgetBoard extends StatefulWidget {
  const WidgetBoard({super.key, required this.items, required this.layout, required this.editing, required this.onChanged, this.onEdit});
  final List<BoardItem> items;
  final BoardLayout layout;
  final bool editing;
  final ValueChanged<BoardLayout> onChanged;
  /// Asked to start customising when a panel is held (Android-style); null leaves long-press alone.
  final VoidCallback? onEdit;

  @override
  State<WidgetBoard> createState() => _WidgetBoardState();
}

class _WidgetBoardState extends State<WidgetBoard> {
  bool _dragging = false;
  double _speed = 0;
  Timer? _timer;

  /// While a panel is being dragged near the top or bottom of the page, keep scrolling so it can reach far places.
  void _follow(Offset global) {
    final scroll = Scrollable.maybeOf(context);
    final box = scroll?.context.findRenderObject();
    if (!_dragging || scroll == null || box is! RenderBox) return;
    final top = box.localToGlobal(Offset.zero).dy;
    _speed = autoScrollSpeed(global.dy, top, top + box.size.height);
    if (_speed == 0) {
      _stop();
    } else {
      _timer ??= Timer.periodic(const Duration(milliseconds: 16), (_) {
        final p = Scrollable.maybeOf(context)?.position;
        if (p == null) return _stop();
        p.jumpTo((p.pixels + _speed).clamp(p.minScrollExtent, p.maxScrollExtent));
      });
    }
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  void _drag(bool on) {
    _dragging = on;
    _over = null;
    if (!on) _stop();
  }

  // Moving a held panel over another one swaps their places at once, once per visit, so the others reflow
  // while you drag. Passing over the held panel's own slot lets you go back.
  String? _over;
  void _hover(String dragged, String target) {
    if (dragged == target) {
      _over = null;
      return;
    }
    if (_over == target) return;
    _over = target;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) onChanged(layout.resolved([for (final i in items) i.id]).moveTo(dragged, target));
    });
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  List<BoardItem> get items => widget.items;
  BoardLayout get layout => widget.layout;
  bool get editing => widget.editing;
  ValueChanged<BoardLayout> get onChanged => widget.onChanged;

  @override
  Widget build(BuildContext context) {
    final byId = {for (final i in items) i.id: i};
    final l = layout.resolved([for (final i in items) i.id]);
    final shown = [for (final id in l.order) if (editing || !l.isHidden(id)) byId[id]!];
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      double widthFor(int cols) => ((w - boardGap * 11) / 12 * cols + boardGap * (cols - 1)).floorToDouble();
      return Listener(
        onPointerMove: (e) => _follow(e.position),
        onPointerUp: (_) => _drag(false),
        onPointerCancel: (_) => _drag(false),
        child: Wrap(spacing: boardGap, runSpacing: boardGap, children: [
        for (final item in shown)
          AnimatedContainer(
            key: ValueKey(item.id),
            duration: reduceMotion(context) ? Duration.zero : motionBase,
            curve: motionCurve,
            width: widthFor(effectiveSpan(l.spanOf(item.id, item.span), w)),
            child: _Tile(
              item: item,
              layout: l,
              editing: editing,
              span: l.spanOf(item.id, item.span),
              boardWidth: w,
              onChanged: onChanged,
              onDrag: _drag,
              onHover: _hover,
              onEdit: widget.onEdit,
            ),
          ),
        ]),
      );
    });
  }
}

class _Tile extends StatefulWidget {
  const _Tile({required this.item, required this.layout, required this.editing, required this.span, required this.boardWidth, required this.onChanged, required this.onDrag, required this.onHover, this.onEdit});
  final BoardItem item;
  final BoardLayout layout;
  final bool editing;
  final int span;
  final double boardWidth;
  final ValueChanged<BoardLayout> onChanged;
  final ValueChanged<bool> onDrag;
  /// A dragged panel ([String] 1) is over this one ([String] 2): the board makes room.
  final void Function(String dragged, String over) onHover;
  /// Long-pressing a panel outside customise mode starts customising, as holding a widget does on Android.
  final VoidCallback? onEdit;

  @override
  State<_Tile> createState() => _TileState();
}

class _TileState extends State<_Tile> with SingleTickerProviderStateMixin {
  // The small wiggle that says "these can be moved", like Android's home screen.
  late final AnimationController _wiggle = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
  double _startW = 0, _startH = 0;
  Offset _acc = Offset.zero;
  String? _badge;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(_Tile old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.editing && !reduceMotion(context)) {
      if (!_wiggle.isAnimating) _wiggle.repeat(reverse: true);
    } else {
      _wiggle.stop();
      _wiggle.value = 0;
    }
  }

  @override
  void dispose() {
    _wiggle.dispose();
    super.dispose();
  }

  /// Drag the corner: width snaps to the nearest of the allowed shares, height to compact, medium or tall
  /// (drag back up past compact for automatic height), as on the current site.
  void _resizeStart() {
    final box = context.size ?? Size.zero;
    _acc = Offset.zero;
    _startW = box.width;
    _startH = box.height;
  }

  void _resize(Offset delta) {
    final id = widget.item.id;
    final colW = (widget.boardWidth + boardGap) / 12;
    var l = widget.layout;
    if (widget.boardWidth >= 700) {
      final cols = (_startW + delta.dx + boardGap) / colW;
      final span = boardSpans.reduce((a, b) => (b - cols).abs() < (a - cols).abs() ? b : a);
      l = l.withSpan(id, span);
    }
    if (delta.dy.abs() > 24) {
      final h = _startH + delta.dy;
      final key = h < _heightPx['s']! - 60 ? null : _heightPx.entries.reduce((a, b) => (b.value - h).abs() < (a.value - h).abs() ? b : a).key;
      l = l.withHeight(id, key);
    }
    setState(() => _badge = '${_spanNames[l.spanOf(id, widget.item.span)]} · ${_heightNames[l.height[id]]}');
    widget.onChanged(l);
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.item.id;
    final layout = widget.layout;
    final hidden = layout.isHidden(id);
    final h = _heightPx[layout.height[id]];
    Widget body = widget.item.child;
    if (h != null) body = SizedBox(height: h, child: SingleChildScrollView(child: body));
    if (!widget.editing) return widget.onEdit == null ? body : GestureDetector(behavior: HitTestBehavior.translucent, onLongPress: widget.onEdit, child: body);

    Widget pill(Widget child) => Material(color: NextUpColors.panel.withValues(alpha: .92), shape: const StadiumBorder(), elevation: 2, child: child);
    final tile = Container(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), border: Border.all(color: NextUpColors.accent.withValues(alpha: .6), width: 1.5)),
      padding: const EdgeInsets.all(4),
      // A slim strip above the panel holds its name and buttons, so nothing covers the panel's own content.
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 2, 2, 6),
          child: Row(children: [
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: NextUpColors.accent, borderRadius: BorderRadius.circular(20)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.open_with_rounded, size: 14, color: Colors.white),
                  const SizedBox(width: 6),
                  Flexible(child: Text(widget.item.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: NextUpType.caption, fontWeight: FontWeight.w700, color: Colors.white))),
                ]),
              ),
            ),
            const Spacer(),
            pill(PopupMenuButton<String>(
              tooltip: 'Size',
              padding: EdgeInsets.zero,
              icon: Icon(Icons.aspect_ratio_rounded, size: 18, color: NextUpColors.muted),
              onSelected: (v) {
                final l = v.startsWith('w') ? layout.withSpan(id, int.parse(v.substring(1))) : layout.withHeight(id, v == 'h' ? null : v.substring(1));
                widget.onChanged(l);
              },
              itemBuilder: (_) => [
                for (final e in _spanNames.entries) CheckedPopupMenuItem(value: 'w${e.key}', checked: e.key == widget.span, child: Text(e.value)),
                const PopupMenuDivider(),
                for (final e in _heightNames.entries) CheckedPopupMenuItem(value: e.key == null ? 'h' : 'h${e.key}', checked: layout.height[id] == e.key, child: Text(e.value)),
              ],
            )),
            const SizedBox(width: 6),
            pill(IconButton(
              tooltip: hidden ? 'Show' : 'Hide',
              onPressed: () => widget.onChanged(layout.toggleHidden(id)),
              visualDensity: VisualDensity.compact,
              icon: Icon(hidden ? Icons.visibility_outlined : Icons.close_rounded, size: 18, color: NextUpColors.muted),
            )),
          ]),
        ),
        // passthrough: the panel keeps the tile's full width, as it has outside customise mode.
        Stack(fit: StackFit.passthrough, children: [
        AnimatedOpacity(duration: motionFast, opacity: hidden ? .35 : 1, child: IgnorePointer(child: body)),
        Positioned(
          right: 0,
          bottom: 0,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) => _resizeStart(),
            onPanUpdate: (d) {
              _acc += d.delta;
              _resize(_acc);
            },
            onPanEnd: (_) => setState(() => _badge = null),
            child: MouseRegion(cursor: SystemMouseCursors.resizeDownRight, child: Container(width: 40, height: 40, alignment: Alignment.bottomRight, padding: const EdgeInsets.all(8), child: Icon(Icons.south_east_rounded, size: 20, color: NextUpColors.accent))),
          ),
        ),
        if (_badge != null) Positioned(left: 8, bottom: 8, child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: NextUpColors.accent, borderRadius: BorderRadius.circular(8)), child: Text(_badge!, style: const TextStyle(fontSize: NextUpType.caption, fontWeight: FontWeight.w700, color: Colors.white)))),
        ]),
      ]),
    );

    // Hold anywhere on the panel and drag; the others move aside as you go over them.
    final draggable = LongPressDraggable<String>(
      data: id,
      delay: const Duration(milliseconds: 150),
      hapticFeedbackOnStart: true,
      hitTestBehavior: HitTestBehavior.opaque,
      onDragStarted: () => widget.onDrag(true),
      onDragEnd: (_) => widget.onDrag(false),
      childWhenDragging: Opacity(opacity: .3, child: tile),
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(color: NextUpColors.accent, borderRadius: BorderRadius.circular(16), boxShadow: const [BoxShadow(blurRadius: 28, color: Colors.black54)]),
          child: Text(widget.item.name, style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
        ),
      ),
      child: tile,
    );
    return DragTarget<String>(
      onWillAcceptWithDetails: (d) {
        widget.onHover(d.data, id);
        return false;
      },
      builder: (context, _, _) => AnimatedBuilder(
        animation: _wiggle,
        builder: (context, child) => Transform.rotate(angle: (_wiggle.value - .5) * .006, child: child),
        child: draggable,
      ),
    );
  }
}

/// The bar shown while customising: what to do, hidden panels to bring back, reset, done.
class BoardBar extends StatelessWidget {
  const BoardBar({super.key, required this.items, required this.layout, required this.onChanged, required this.onReset, required this.onDone});
  final List<BoardItem> items;
  final BoardLayout layout;
  final ValueChanged<BoardLayout> onChanged;
  final VoidCallback onReset, onDone;

  @override
  Widget build(BuildContext context) {
    final hidden = [for (final i in items) if (layout.isHidden(i.id)) i];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: NextUpColors.panel, borderRadius: BorderRadius.circular(16), border: Border.all(color: NextUpColors.accent.withValues(alpha: .6))),
      child: Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        const Text('Customising:', style: TextStyle(fontWeight: FontWeight.w800)),
        Text('hold a panel and drag it, pull the corner to resize, ✕ hides.', style: TextStyle(color: NextUpColors.muted, fontSize: NextUpType.caption)),
        for (final i in hidden) ActionChip(label: Text('+ ${i.name}'), onPressed: () => onChanged(layout.toggleHidden(i.id))),
        OutlinedButton(onPressed: onReset, child: const Text('Reset layout')),
        FilledButton(onPressed: onDone, child: const Text('Done')),
      ]),
    );
  }
}
