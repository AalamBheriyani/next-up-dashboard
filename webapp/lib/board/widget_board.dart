// The widget board: panels on a 12-column grid that can be moved, resized and hidden, the same idea as the
// current site's Customise mode. It works by touch and mouse (a drag handle plus plain buttons and menus),
// and the saved layout is the same on every device: wide screens use the widths, narrow ones stack.
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

class WidgetBoard extends StatelessWidget {
  const WidgetBoard({super.key, required this.items, required this.layout, required this.editing, required this.onChanged});
  final List<BoardItem> items;
  final BoardLayout layout;
  final bool editing;
  final ValueChanged<BoardLayout> onChanged;

  @override
  Widget build(BuildContext context) {
    final byId = {for (final i in items) i.id: i};
    final l = layout.resolved([for (final i in items) i.id]);
    final shown = [for (final id in l.order) if (editing || !l.isHidden(id)) byId[id]!];
    final visibleIds = [for (final i in shown) if (!l.isHidden(i.id)) i.id];
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      double widthFor(int cols) => ((w - boardGap * 11) / 12 * cols + boardGap * (cols - 1)).floorToDouble();
      return Wrap(spacing: boardGap, runSpacing: boardGap, children: [
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
              visibleIds: visibleIds,
              span: l.spanOf(item.id, item.span),
              onChanged: onChanged,
            ),
          ),
      ]);
    });
  }
}

class _Tile extends StatefulWidget {
  const _Tile({required this.item, required this.layout, required this.editing, required this.visibleIds, required this.span, required this.onChanged});
  final BoardItem item;
  final BoardLayout layout;
  final bool editing;
  final List<String> visibleIds;
  final int span;
  final ValueChanged<BoardLayout> onChanged;

  @override
  State<_Tile> createState() => _TileState();
}

class _TileState extends State<_Tile> {
  bool _over = false;

  @override
  Widget build(BuildContext context) {
    final id = widget.item.id;
    final hidden = widget.layout.isHidden(id);
    final h = _heightPx[widget.layout.height[id]];
    Widget body = widget.item.child;
    if (h != null) body = SizedBox(height: h, child: SingleChildScrollView(child: body));
    if (!widget.editing) return body;

    return DragTarget<String>(
      onWillAcceptWithDetails: (d) {
        final ok = d.data != id;
        if (ok) setState(() => _over = true);
        return ok;
      },
      onLeave: (_) => setState(() => _over = false),
      onAcceptWithDetails: (d) {
        setState(() => _over = false);
        widget.onChanged(widget.layout.moveTo(d.data, id));
      },
      builder: (context, _, _) => AnimatedOpacity(
        duration: motionFast,
        opacity: hidden ? .4 : 1,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: NextUpColors.accent.withValues(alpha: _over ? 1 : .6), width: _over ? 3 : 1.5),
          ),
          padding: const EdgeInsets.all(4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _Tools(item: widget.item, layout: widget.layout, visibleIds: widget.visibleIds, span: widget.span, onChanged: widget.onChanged),
            const SizedBox(height: 4),
            IgnorePointer(child: body),
          ]),
        ),
      ),
    );
  }
}

/// The strip above a panel in edit mode: drag handle, earlier/later, width, height, hide.
class _Tools extends StatelessWidget {
  const _Tools({required this.item, required this.layout, required this.visibleIds, required this.span, required this.onChanged});
  final BoardItem item;
  final BoardLayout layout;
  final List<String> visibleIds;
  final int span;
  final ValueChanged<BoardLayout> onChanged;

  @override
  Widget build(BuildContext context) {
    final id = item.id;
    final hidden = layout.isHidden(id);
    Widget icon(IconData i, String tip, VoidCallback? f) => IconButton(tooltip: tip, onPressed: f, icon: Icon(i, size: 18), visualDensity: VisualDensity.compact, color: NextUpColors.muted);
    return Container(
      decoration: BoxDecoration(color: NextUpColors.raised, borderRadius: BorderRadius.circular(14)),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(children: [
        LongPressDraggable<String>(
          data: id,
          delay: const Duration(milliseconds: 120),
          feedback: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: NextUpColors.accent, borderRadius: BorderRadius.circular(12), boxShadow: const [BoxShadow(blurRadius: 24, color: Colors.black54)]),
              child: Text(item.name, style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
            ),
          ),
          child: Tooltip(message: 'Hold and drag to move', child: Padding(padding: const EdgeInsets.all(8), child: Icon(Icons.drag_indicator_rounded, size: 20, color: NextUpColors.muted))),
        ),
        Expanded(child: Text(item.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: NextUpType.caption, fontWeight: FontWeight.w700))),
        icon(Icons.arrow_back_rounded, 'Move earlier', hidden ? null : () => onChanged(layout.step(id, -1, visibleIds))),
        icon(Icons.arrow_forward_rounded, 'Move later', hidden ? null : () => onChanged(layout.step(id, 1, visibleIds))),
        PopupMenuButton<int>(
          tooltip: 'Width',
          icon: Icon(Icons.width_normal_rounded, size: 18, color: NextUpColors.muted),
          initialValue: span,
          onSelected: (s) => onChanged(layout.withSpan(id, s)),
          itemBuilder: (_) => [for (final e in _spanNames.entries) PopupMenuItem(value: e.key, child: Text(e.value))],
        ),
        PopupMenuButton<String>(
          tooltip: 'Height',
          icon: Icon(Icons.height_rounded, size: 18, color: NextUpColors.muted),
          initialValue: layout.height[id] ?? '',
          onSelected: (s) => onChanged(layout.withHeight(id, s.isEmpty ? null : s)),
          itemBuilder: (_) => [for (final e in _heightNames.entries) PopupMenuItem(value: e.key ?? '', child: Text(e.value))],
        ),
        icon(hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined, hidden ? 'Show' : 'Hide', () => onChanged(layout.toggleHidden(id))),
      ]),
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
        Text('hold ⠿ and drag a panel, or use the arrows and menus.', style: TextStyle(color: NextUpColors.muted, fontSize: NextUpType.caption)),
        for (final i in hidden) ActionChip(label: Text('+ ${i.name}'), onPressed: () => onChanged(layout.toggleHidden(i.id))),
        OutlinedButton(onPressed: onReset, child: const Text('Reset layout')),
        FilledButton(onPressed: onDone, child: const Text('Done')),
      ]),
    );
  }
}
