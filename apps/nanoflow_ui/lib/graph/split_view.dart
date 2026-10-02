import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Which pane of a [SplitView] has the extent the border sets; the other
/// takes the rest.
enum SplitPane { first, second }

/// Two panes side by side or one over the other, with a 1 px border between
/// them that the user drags (docs/ui-spec.md «Экран графа»: «Границы
/// колонки и панели двигаются»).
///
/// The [sized] pane is [extent] long with the border line, as the mockups'
/// boxes are; dragging moves the border with the pointer, but the sized pane
/// stays within [minExtent] and [maxExtent], and the other keeps at least
/// [minOther]. While [fixedExtent] is set, the sized pane is that long and
/// the border does not move; then it comes back to where it was dragged.
class SplitView extends StatefulWidget {
  const SplitView({
    super.key,
    required this.axis,
    required this.sized,
    required this.extent,
    required this.minExtent,
    required this.maxExtent,
    required this.minOther,
    required this.border,
    required this.first,
    required this.second,
    this.fixedExtent,
  });

  /// [Axis.horizontal]: [first] on the left of [second]; vertical: over it.
  final Axis axis;

  final SplitPane sized;

  /// The sized pane's extent, with the border, until the border is dragged.
  final double extent;
  final double minExtent;
  final double maxExtent;
  final double minOther;

  /// The sized pane's extent, with the border, while it is folded.
  final double? fixedExtent;

  /// The border line's color.
  final Color border;

  final Widget first;
  final Widget second;

  @override
  State<SplitView> createState() => _SplitViewState();
}

class _SplitViewState extends State<SplitView> {
  /// How far either side of the border line the pointer takes hold of it.
  static const _grip = 4.0;

  late double _extent = widget.extent;

  /// The extent and the pointer when the drag started: the border follows
  /// the pointer from there.
  double _dragExtent = 0;
  double _dragFrom = 0;

  /// The whole length the panes share, as last laid out.
  double _length = 0;

  double _clamp(double extent) => math.max(
    0,
    math.min(
      math.min(widget.maxExtent, _length - widget.minOther),
      math.max(widget.minExtent, extent),
    ),
  );

  double _along(Offset position) =>
      widget.axis == Axis.horizontal ? position.dx : position.dy;

  void _dragStarted(DragStartDetails details) {
    _dragExtent = _clamp(_extent);
    _dragFrom = _along(details.globalPosition);
  }

  void _dragged(DragUpdateDetails details) {
    final moved = _along(details.globalPosition) - _dragFrom;
    final sign = widget.sized == SplitPane.first ? 1 : -1;
    setState(() => _extent = _clamp(_dragExtent + sign * moved));
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final horizontal = widget.axis == Axis.horizontal;
      _length = horizontal ? constraints.maxWidth : constraints.maxHeight;
      final fixed = widget.fixedExtent;
      final extent = fixed == null
          ? _clamp(_extent)
          : math.max(0.0, math.min(fixed, _length));
      final firstSized = widget.sized == SplitPane.first;
      // Where the border line starts, from the start of the first pane.
      final line = firstSized ? extent - 1 : _length - extent;
      Widget sized(Widget pane) => horizontal
          ? SizedBox(width: math.max(0, extent - 1), child: pane)
          : SizedBox(height: math.max(0, extent - 1), child: pane);
      final border = horizontal
          ? SizedBox(width: 1, child: ColoredBox(color: widget.border))
          : SizedBox(height: 1, child: ColoredBox(color: widget.border));
      return Stack(
        children: [
          Flex(
            direction: widget.axis,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: firstSized
                ? [sized(widget.first), border, Expanded(child: widget.second)]
                : [Expanded(child: widget.first), border, sized(widget.second)],
          ),
          if (fixed == null)
            Positioned(
              left: horizontal ? line + 0.5 - _grip : 0,
              top: horizontal ? 0 : line + 0.5 - _grip,
              width: horizontal ? 2 * _grip : null,
              height: horizontal ? null : 2 * _grip,
              right: horizontal ? null : 0,
              bottom: horizontal ? 0 : null,
              child: MouseRegion(
                cursor: horizontal
                    ? SystemMouseCursors.resizeColumn
                    : SystemMouseCursors.resizeRow,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  dragStartBehavior: DragStartBehavior.down,
                  onHorizontalDragStart: horizontal ? _dragStarted : null,
                  onHorizontalDragUpdate: horizontal ? _dragged : null,
                  onVerticalDragStart: horizontal ? null : _dragStarted,
                  onVerticalDragUpdate: horizontal ? null : _dragged,
                ),
              ),
            ),
        ],
      );
    },
  );
}
