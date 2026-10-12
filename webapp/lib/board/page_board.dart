// A widget board for a whole page (Track, Adherence, Quest Log): the same moving, resizing and hiding as the
// dashboard, in the one layout saved to the account. Each page owns the ids of its own panels, so saving here
// never touches the arrangement of the other pages.
import 'package:flutter/material.dart';
import 'package:next_up_core/board_layout.dart';

import 'widget_board.dart';

class PageBoard extends StatefulWidget {
  const PageBoard({super.key, required this.items, this.layout = const BoardLayout(), this.onLayout});
  final List<BoardItem> items;

  /// The whole account layout (every page); only this page's panels are read from it.
  final BoardLayout layout;
  final ValueChanged<BoardLayout>? onLayout;

  @override
  State<PageBoard> createState() => _PageBoardState();
}

class _PageBoardState extends State<PageBoard> {
  bool _editing = false;
  late BoardLayout _layout = widget.layout;

  List<String> get _ids => [for (final i in widget.items) i.id];

  @override
  void didUpdateWidget(PageBoard old) {
    super.didUpdateWidget(old);
    // A layout arriving from the account replaces ours unless we're mid-edit.
    if (!_editing && old.layout != widget.layout) _layout = widget.layout;
  }

  void _set(BoardLayout page) {
    final full = _layout.withPage(page, _ids);
    setState(() => _layout = full);
    widget.onLayout?.call(full);
  }

  @override
  Widget build(BuildContext context) {
    final mine = _layout.resolved(_ids);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Align(
        alignment: Alignment.centerRight,
        child: IconButton(tooltip: _editing ? 'Done customising' : 'Customise panels', onPressed: () => setState(() => _editing = !_editing), icon: Icon(_editing ? Icons.check_rounded : Icons.dashboard_customize_outlined)),
      ),
      if (_editing) ...[
        BoardBar(items: widget.items, layout: mine, onChanged: _set, onReset: () => _set(const BoardLayout()), onDone: () => setState(() => _editing = false)),
        const SizedBox(height: 16),
      ],
      WidgetBoard(items: widget.items, layout: mine, editing: _editing, onChanged: _set, onEdit: () => setState(() => _editing = true)),
    ]);
  }
}
