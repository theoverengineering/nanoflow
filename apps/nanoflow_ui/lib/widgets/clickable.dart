import 'package:flutter/widgets.dart';

/// Builds a widget for the pointer [hovered] over it or not.
typedef HoverBuilder = Widget Function(BuildContext context, bool hovered);

/// Something to click: the pointing hand over it and [onTap] on a click.
///
/// [Clickable.hover] builds its child again as the pointer comes over it and
/// leaves, for a look that changes on hover.
class Clickable extends StatefulWidget {
  const Clickable({super.key, required this.onTap, required Widget this.child})
    : builder = null;

  const Clickable.hover({
    super.key,
    required this.onTap,
    required HoverBuilder this.builder,
  }) : child = null;

  final VoidCallback onTap;

  /// What is clicked, the same with the pointer over it or not.
  final Widget? child;

  /// What is clicked, built for the pointer over it or not.
  final HoverBuilder? builder;

  @override
  State<Clickable> createState() => _ClickableState();
}

class _ClickableState extends State<Clickable> {
  bool _hovered = false;

  void _hover(bool hovered) {
    if (widget.builder != null) setState(() => _hovered = hovered);
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    onEnter: (_) => _hover(true),
    onExit: (_) => _hover(false),
    child: GestureDetector(
      onTap: widget.onTap,
      child: widget.child ?? widget.builder!(context, _hovered),
    ),
  );
}
