// A deadline list in a box of fixed height that scrolls, so every list panel is the same size however many
// items it holds.
import 'package:flutter/material.dart';
import 'package:next_up_core/deadline.dart';
import 'package:next_up_core/theme.dart';
import 'package:next_up_core/today_screen.dart';

const deadlineBoxHeight = 340.0;

class DeadlineBox extends StatefulWidget {
  const DeadlineBox({super.key, required this.title, required this.color, required this.items, required this.now, required this.onFinish, this.showDate = false, this.onEdit, this.empty = 'Nothing here.', this.height = deadlineBoxHeight});
  final String title;
  final Color color;
  final List<Deadline> items;
  final DateTime now;
  final void Function(Deadline) onFinish;
  final void Function(Deadline)? onEdit;
  final bool showDate;
  final String empty;
  final double height;

  @override
  State<DeadlineBox> createState() => _DeadlineBoxState();
}

class _DeadlineBoxState extends State<DeadlineBox> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: widget.items.isEmpty
          ? Text(widget.empty, style: TextStyle(color: NextUpColors.muted))
          : Scrollbar(
              controller: _scroll,
              child: SingleChildScrollView(
                controller: _scroll,
                child: DeadlineSection(title: widget.title, color: widget.color, items: widget.items, now: widget.now, onFinish: widget.onFinish, showDate: widget.showDate, bare: true, onEdit: widget.onEdit),
              ),
            ),
    );
  }
}
