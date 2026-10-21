// A widget board for a whole page (Track, Adherence, Quest Log): the same moving, resizing and hiding as the
// dashboard, in the one layout saved to the account. Each page owns the ids of its own panels, so saving here
// never touches the arrangement of the other pages.
import 'package:flutter/material.dart';
import 'package:next_up_core/board_layout.dart';

import 'widget_board.dart';

class PageBoard extends StatefulWidget {
  const PageBoard({super.key, required this.items, this.layout = const BoardLayout(), this.onLayout, this.editing});
  final List<BoardItem> items;

  /// Shared with a [CustomiseButton] in the page's own header; without it the board shows its own button.
  final ValueNotifier<bool>? editing;

  /// The whole account layout (every page); only this page's panels are read from it.
  final BoardLayout layout;
  final ValueChanged<BoardLayout>? onLayout;

  @override
  State<PageBoard> createState() => _PageBoardState();
}

class _PageBoardState extends State<PageBoard> {
  late final ValueNotifier<bool> _own = ValueNotifier(false);
  ValueNotifier<bool> get _switch => widget.editing ?? _own;
  bool get _editing => _switch.value;
  set _editing(bool v) => _switch.value = v;
  late BoardLayout _layout = widget.layout;

  List<String> get _ids => [for (final i in widget.items) i.id];

  @override
  void didUpdateWidget(PageBoard old) {
    super.didUpdateWidget(old);
    // A layout arriving from the account replaces ours unless we're mid-edit.
    if (!_editing && old.layout != widget.layout) _layout = widget.layout;
  }

  @override
  void initState() {
    super.initState();
    _switch.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _switch.removeListener(_changed);
    _own.dispose();
    super.dispose();
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
      if (widget.editing == null) Align(alignment: Alignment.centerRight, child: CustomiseButton(editing: _own)),
      if (_editing) ...[
        BoardBar(items: widget.items, layout: mine, onChanged: _set, onReset: () => _set(const BoardLayout()), onDone: () => setState(() => _editing = false)),
        const SizedBox(height: 16),
      ],
      WidgetBoard(items: widget.items, layout: mine, editing: _editing, onChanged: _set, onEdit: () => setState(() => _editing = true)),
    ]);
  }
}

/// The customise / done button, for a page header that shares its switch with a [PageBoard].
class CustomiseButton extends StatelessWidget {
  const CustomiseButton({super.key, required this.editing});
  final ValueNotifier<bool> editing;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: editing,
        builder: (context, on, _) => IconButton(
          tooltip: on ? 'Done customising' : 'Customise panels',
          onPressed: () => editing.value = !on,
          icon: Icon(on ? Icons.check_rounded : Icons.dashboard_customize_outlined),
        ),
      );
}
