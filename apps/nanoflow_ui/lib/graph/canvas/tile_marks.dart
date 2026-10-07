import 'package:flutter/material.dart';

import '../../layout/layout.dart' show badgeHeight;
import '../../state/graph_marks.dart';
import '../../theme.dart';
import '../../widgets/spinner.dart';
import 'canvas_style.dart';

// What a session puts on a node's tile (docs/ui-spec.md «Граф»): its look
// in the state of its effects, the state's badge, and the badges over it.

/// The badge on the bottom right corner of a tile in [state]: a check
/// visited, `!` failed, the turning sign running, a pause interrupted; none
/// otherwise.
Widget? stateBadge(NodeState? state) => switch (state) {
  NodeState.visited => const StateBadge(
    fill: Color(0xFF2A9D61),
    mark: BadgeMark.check,
  ),
  NodeState.failed => const StateBadge(
    fill: Color(0xFFD9434A),
    mark: BadgeMark.exclamation,
  ),
  NodeState.running => const Spinner(
    size: 17,
    strokeWidth: 2.2,
    background: CanvasColors.background,
  ),
  NodeState.interrupted => const StateBadge(
    fill: AppColors.interrupted,
    mark: BadgeMark.pause,
  ),
  NodeState.notVisited || null => null,
};

/// The colors of a tile and its texts in a node state.
final class TileLook {
  const TileLook({
    required this.fill,
    required this.border,
    required this.borderWidth,
    required this.icon,
    required this.name,
    required this.nameWeight,
    required this.place,
    this.stack = CanvasColors.stackBorder,
  });

  final Color fill;
  final Color border;
  final double borderWidth;
  final Color icon;
  final Color name;
  final FontWeight nameWeight;
  final Color place;

  /// The outline of the tiles stacked behind copies.
  final Color stack;

  /// The effects of a call or copies under their icon: the icon's colour,
  /// muted.
  Color get inside => icon.withValues(alpha: icon.a * 0.7);

  static TileLook of(NodeState? state) => switch (state) {
    null => plain,
    NodeState.notVisited => notVisited,
    NodeState.visited => visited,
    NodeState.running => running,
    NodeState.interrupted => interrupted,
    NodeState.failed => failed,
  };

  /// `Current graph`, a fork the code did not go through, a marker: no state.
  static const plain = TileLook(
    fill: CanvasColors.tileFill,
    border: CanvasColors.tileBorder,
    borderWidth: 1.5,
    icon: CanvasColors.icon,
    name: CanvasColors.name,
    nameWeight: FontWeight.w600,
    place: CanvasColors.place,
  );

  static const notVisited = TileLook(
    fill: Color(0xFF2C2D32),
    border: Color(0xFF45464C),
    borderWidth: 1.5,
    icon: Color(0xFF6E6F76),
    name: Color(0xFF9A9BA2),
    nameWeight: FontWeight.w500,
    place: Color(0xFF8A8B92),
    stack: Color(0xFF45464C),
  );

  static const visited = TileLook(
    fill: CanvasColors.tileFill,
    border: Color(0xFF3CC47C),
    borderWidth: 2,
    icon: CanvasColors.icon,
    name: CanvasColors.name,
    nameWeight: FontWeight.w600,
    place: CanvasColors.place,
  );

  static const running = TileLook(
    fill: Color(0xFF36302A),
    border: Color(0xFFF2A93B),
    borderWidth: 2,
    icon: Color(0xFFF2A93B),
    name: Color(0xFFF7F3EA),
    nameWeight: FontWeight.w600,
    place: Color(0xFFC9A36A),
  );

  /// An effect that was running when the process of its session went: framed
  /// muted, as nothing goes on.
  static const interrupted = TileLook(
    fill: CanvasColors.tileFill,
    border: AppColors.interrupted,
    borderWidth: 2,
    icon: CanvasColors.icon,
    name: CanvasColors.name,
    nameWeight: FontWeight.w600,
    place: CanvasColors.place,
  );

  static const failed = TileLook(
    fill: Color(0xFF382A2C),
    border: Color(0xFFF0555C),
    borderWidth: 2,
    icon: Color(0xFFF0555C),
    name: Color(0xFFF7ECEC),
    nameWeight: FontWeight.w600,
    place: Color(0xFFC98A8D),
  );
}

/// What a [StateBadge] has on it.
enum BadgeMark {
  /// A visited node's check.
  check,

  /// A failed node's `!`.
  exclamation,

  /// An interrupted node's pause.
  pause,
}

/// The check of a visited node, the `!` of a failed one, or the pause of an
/// interrupted one: a 17 px disc in a ring of the canvas's color.
class StateBadge extends StatelessWidget {
  const StateBadge({super.key, required this.fill, required this.mark});

  final Color fill;
  final BadgeMark mark;

  @override
  Widget build(BuildContext context) => Container(
    width: 21,
    height: 21,
    decoration: BoxDecoration(
      color: fill,
      shape: BoxShape.circle,
      border: Border.all(color: CanvasColors.background, width: 2),
    ),
    alignment: Alignment.center,
    child: CustomPaint(size: const Size.square(9), painter: _MarkPainter(mark)),
  );
}

/// A check or an exclamation mark in white, or a pause in the canvas's
/// color on the light grey of interrupted: 10 units.
class _MarkPainter extends CustomPainter {
  _MarkPainter(this.mark);

  final BadgeMark mark;

  static const _white = Color(0xFFFFFFFF);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 10);
    final stroke = Paint()
      ..color = mark == BadgeMark.pause ? CanvasColors.background : _white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.9
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    switch (mark) {
      case BadgeMark.exclamation:
        canvas
          ..drawLine(const Offset(5, 1.2), const Offset(5, 5.6), stroke)
          ..drawCircle(const Offset(5, 8.4), 1.15, Paint()..color = _white);
      case BadgeMark.check:
        canvas.drawPath(
          Path()
            ..moveTo(1.6, 5.2)
            ..lineTo(3.8, 7.4)
            ..lineTo(8.4, 2.8),
          stroke,
        );
      case BadgeMark.pause:
        canvas
          ..drawLine(const Offset(3.4, 1.8), const Offset(3.4, 8.2), stroke)
          ..drawLine(const Offset(6.6, 1.8), const Offset(6.6, 8.2), stroke);
    }
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.mark != mark;
}

/// How many copies are on an effect now, in the color of running effects
/// (docs/design/code-first/copies-frame.html).
class RunningBadge extends StatelessWidget {
  const RunningBadge(this.copies, {super.key});

  final int copies;

  static const _size = 17.0;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: _size),
    height: _size,
    padding: const EdgeInsets.symmetric(horizontal: 4),
    alignment: Alignment.center,
    decoration: const BoxDecoration(
      color: Color(0xFFF2A93B),
      borderRadius: BorderRadius.all(Radius.circular(_size / 2)),
    ),
    child: Text(
      '$copies',
      style: CanvasText.badge.copyWith(
        color: const Color(0xFF1F1606),
        fontWeight: FontWeight.w500,
      ),
      textScaler: TextScaler.noScaling,
    ),
  );
}

/// `2×` over a node entered more than once.
class CountBadge extends StatelessWidget {
  const CountBadge(this.text);

  final String text;

  /// How wide the badge of [text] is.
  static double widthOf(String text) =>
      measureText(text, CanvasText.badge) + 14;

  @override
  Widget build(BuildContext context) => Container(
    width: widthOf(text),
    padding: const EdgeInsets.symmetric(vertical: 1),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: CanvasColors.badgeFill,
      border: Border.all(color: CanvasColors.badgeBorder),
      borderRadius: const BorderRadius.all(Radius.circular(999)),
    ),
    child: Text(
      text,
      style: CanvasText.badge,
      textScaler: TextScaler.noScaling,
    ),
  );
}

/// How many copies ran, across the top right of the stack of copies: `×3`;
/// `×0` muted while none has; `×n` without a session.
class CopiesBadge extends StatelessWidget {
  const CopiesBadge(this.text, {required this.muted});

  final String text;
  final bool muted;

  @override
  Widget build(BuildContext context) => Container(
    height: badgeHeight,
    padding: const EdgeInsets.symmetric(horizontal: 5),
    alignment: Alignment.center,
    decoration: const BoxDecoration(
      color: CanvasColors.badgeFill,
      border: Border.fromBorderSide(
        BorderSide(color: CanvasColors.badgeBorder),
      ),
      borderRadius: BorderRadius.all(Radius.circular(badgeHeight / 2)),
    ),
    child: Text(
      text,
      style: muted
          ? CanvasText.badge.copyWith(color: CanvasColors.markerText)
          : CanvasText.badge,
      textScaler: TextScaler.noScaling,
    ),
  );
}
