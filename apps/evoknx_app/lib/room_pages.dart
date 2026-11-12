import 'package:flutter/material.dart';

/// The pages of a room, swiped sideways. It owns its controller, so a room view always opens on
/// [initialPage] (the page the header shows) and two views that overlap during a fade never share one.
class RoomPages extends StatefulWidget {
  const RoomPages({
    super.key,
    required this.initialPage,
    required this.count,
    required this.onChanged,
    required this.onController,
    required this.onDetach,
    required this.itemBuilder,
  });
  final int initialPage, count;
  final ValueChanged<int> onChanged;

  /// Hands the controller to the screen (it needs it to change page from a button).
  final ValueChanged<PageController> onController;
  final ValueChanged<PageController> onDetach;
  final Widget Function(BuildContext context, int index, PageController controller) itemBuilder;

  @override
  State<RoomPages> createState() => _RoomPagesState();
}

class _RoomPagesState extends State<RoomPages> {
  late final PageController _pc = PageController(initialPage: widget.initialPage.clamp(0, widget.count < 1 ? 0 : widget.count - 1).toInt());

  @override
  void initState() {
    super.initState();
    widget.onController(_pc);
  }

  @override
  void dispose() {
    widget.onDetach(_pc);
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PageView.builder(
    controller: _pc,
    itemCount: widget.count,
    onPageChanged: widget.onChanged,
    itemBuilder: (context, i) => widget.itemBuilder(context, i, _pc),
  );
}
