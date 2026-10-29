import 'package:flutter/widgets.dart';

// The small line icons of the mockups, drawn from their SVG: each in a
// square of its size, its strokes as wide as in the units of its SVG's view
// box.

/// An icon drawn by [draw] in a view box [units] across; [kind] tells
/// icons apart for repainting.
class _LineIcon extends StatelessWidget {
  const _LineIcon({
    required this.kind,
    required this.units,
    required this.size,
    required this.color,
    required this.strokeWidth,
    required this.draw,
    this.round = true,
  });

  final String kind;
  final double units;
  final double size;
  final Color color;
  final double strokeWidth;
  final bool round;
  final void Function(Canvas canvas, Paint stroke) draw;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _LinePainter(this));
}

class _LinePainter extends CustomPainter {
  _LinePainter(this.icon);

  final _LineIcon icon;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / icon.units);
    final stroke = Paint()
      ..color = icon.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = icon.strokeWidth;
    if (icon.round) {
      stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
    }
    icon.draw(canvas, stroke);
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.icon.kind != icon.kind ||
      old.icon.color != icon.color ||
      old.icon.strokeWidth != icon.strokeWidth;
}

/// A check: `passes`, `Copied`, an effect that finished. 10 units.
class CheckIcon extends StatelessWidget {
  const CheckIcon({
    super.key,
    required this.size,
    required this.color,
    this.strokeWidth = 1.7,
  });

  final double size;
  final Color color;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) => _LineIcon(
    kind: 'check',
    units: 10,
    size: size,
    color: color,
    strokeWidth: strokeWidth,
    draw: (canvas, stroke) => canvas.drawPath(
      Path()
        ..moveTo(1.6, 5.2)
        ..lineTo(3.8, 7.4)
        ..lineTo(8.4, 2.8),
      stroke,
    ),
  );
}

/// Two sheets, one over the other: copy a path. 16 units.
class CopyIcon extends StatelessWidget {
  const CopyIcon({super.key, required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => _LineIcon(
    kind: 'copy',
    units: 16,
    size: size,
    color: color,
    strokeWidth: 1.4,
    round: false,
    draw: (canvas, stroke) => canvas
      ..drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(5.4, 5.4, 8.2, 8.2),
          const Radius.circular(1.6),
        ),
        stroke,
      )
      ..drawPath(
        Path()
          ..moveTo(10.6, 5.4)
          ..lineTo(10.6, 3.8)
          ..arcToPoint(
            const Offset(9.2, 2.4),
            radius: const Radius.circular(1.4),
            clockwise: false,
          )
          ..lineTo(3.8, 2.4)
          ..arcToPoint(
            const Offset(2.4, 3.8),
            radius: const Radius.circular(1.4),
            clockwise: false,
          )
          ..lineTo(2.4, 9.2)
          ..arcToPoint(
            const Offset(3.8, 10.6),
            radius: const Radius.circular(1.4),
            clockwise: false,
          )
          ..lineTo(5.4, 10.6),
        stroke,
      ),
  );
}

/// A chevron pointing left, or right when [right], or down when [down]:
/// back, the visit before or after, a list to open. 16 units.
class ChevronIcon extends StatelessWidget {
  const ChevronIcon({
    super.key,
    required this.size,
    required this.color,
    this.right = false,
    this.down = false,
  });

  final double size;
  final Color color;
  final bool right;
  final bool down;

  @override
  Widget build(BuildContext context) => _LineIcon(
    kind: down
        ? 'chevron down'
        : right
        ? 'chevron right'
        : 'chevron',
    units: 16,
    size: size,
    color: color,
    strokeWidth: 1.7,
    draw: (canvas, stroke) => canvas.drawPath(
      down
          ? (Path()
              ..moveTo(3, 6)
              ..lineTo(8, 11)
              ..lineTo(13, 6))
          : right
          ? (Path()
              ..moveTo(6, 3)
              ..lineTo(11, 8)
              ..lineTo(6, 13))
          : (Path()
              ..moveTo(10, 3)
              ..lineTo(5, 8)
              ..lineTo(10, 13)),
      stroke,
    ),
  );
}

/// A cross: close. 10 units.
class CloseIcon extends StatelessWidget {
  const CloseIcon({super.key, required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => _LineIcon(
    kind: 'close',
    units: 10,
    size: size,
    color: color,
    strokeWidth: 1.6,
    draw: (canvas, stroke) => canvas.drawPath(
      Path()
        ..moveTo(1.6, 1.6)
        ..lineTo(8.4, 8.4)
        ..moveTo(8.4, 1.6)
        ..lineTo(1.6, 8.4),
      stroke,
    ),
  );
}

/// An arrow out to the top right, ↗: open a called graph as the main graph.
/// 10 units, as the cross.
class OpenOutIcon extends StatelessWidget {
  const OpenOutIcon({super.key, required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => _LineIcon(
    kind: 'open out',
    units: 10,
    size: size,
    color: color,
    strokeWidth: 1.4,
    draw: (canvas, stroke) => canvas.drawPath(
      Path()
        ..moveTo(2, 8)
        ..lineTo(8, 2)
        ..moveTo(3.6, 2)
        ..lineTo(8, 2)
        ..lineTo(8, 6.4),
      stroke,
    ),
  );
}

/// Two upright bars, a pause: an effect interrupted — its process stopped,
/// a resume goes on with it. 10 units, as wide as the cross of a failed
/// effect.
class PauseIcon extends StatelessWidget {
  const PauseIcon({
    super.key,
    required this.size,
    required this.color,
    this.strokeWidth = 1.7,
  });

  final double size;
  final Color color;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) => _LineIcon(
    kind: 'pause',
    units: 10,
    size: size,
    color: color,
    strokeWidth: strokeWidth,
    draw: (canvas, stroke) => canvas.drawPath(
      Path()
        ..moveTo(3.6, 2.6)
        ..lineTo(3.6, 7.4)
        ..moveTo(6.4, 2.6)
        ..lineTo(6.4, 7.4),
      stroke,
    ),
  );
}

/// Two links of a chain: where data came from. 12 units.
class LinkIcon extends StatelessWidget {
  const LinkIcon({super.key, required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => _LineIcon(
    kind: 'link',
    units: 12,
    size: size,
    color: color,
    strokeWidth: 1.2,
    draw: (canvas, stroke) => canvas.drawPath(
      Path()
        ..moveTo(4.6, 7.4)
        ..lineTo(7.4, 4.6)
        ..moveTo(5.2, 2.6)
        ..relativeLineTo(0.9, -0.9)
        ..arcToPoint(const Offset(9.3, 4.9), radius: const Radius.circular(2.3))
        ..relativeLineTo(-0.9, 0.9)
        ..moveTo(6.8, 9.4)
        ..relativeLineTo(-0.9, 0.9)
        ..arcToPoint(const Offset(2.7, 7.1), radius: const Radius.circular(2.3))
        ..relativeLineTo(0.9, -0.9),
      stroke,
    ),
  );
}

/// A node's icon on its tile, 28 units: [_kind] drawn by [_draw].
abstract class _NodeIcon extends StatelessWidget {
  const _NodeIcon({
    super.key,
    required this.size,
    required this.color,
    this.strokeWidth = 1.6,
  });

  final double size;
  final Color color;
  final double strokeWidth;

  /// Tells the icons apart for repainting.
  String get _kind;

  void _draw(Canvas canvas, Paint stroke);

  @override
  Widget build(BuildContext context) => _LineIcon(
    kind: _kind,
    units: 28,
    size: size,
    color: color,
    strokeWidth: strokeWidth,
    draw: _draw,
  );
}

/// An effect's terminal.
class EffectIcon extends _NodeIcon {
  const EffectIcon({
    super.key,
    required super.size,
    required super.color,
    super.strokeWidth,
  });

  @override
  String get _kind => 'effect';

  @override
  void _draw(Canvas canvas, Paint stroke) => canvas
    ..drawRRect(
      RRect.fromLTRBR(3.5, 5.5, 24.5, 22.5, const Radius.circular(3.5)),
      stroke,
    )
    ..drawPath(
      Path()
        ..moveTo(9, 11)
        ..lineTo(12.2, 14)
        ..lineTo(9, 17)
        ..moveTo(14.5, 17.5)
        ..lineTo(19, 17.5),
      stroke,
    );
}

/// A condition's branch: a node on the left branching to two on the right.
class ConditionIcon extends _NodeIcon {
  const ConditionIcon({super.key, required super.size, required super.color});

  static const _corner = Radius.circular(1.8);

  @override
  String get _kind => 'condition';

  @override
  void _draw(Canvas canvas, Paint stroke) => canvas
    ..drawRRect(RRect.fromLTRBR(3, 11, 9, 17, _corner), stroke)
    ..drawRRect(RRect.fromLTRBR(19, 4, 25, 10, _corner), stroke)
    ..drawRRect(RRect.fromLTRBR(19, 18, 25, 24, _corner), stroke)
    ..drawPath(
      Path()
        ..moveTo(9, 14)
        ..relativeLineTo(4, 0)
        ..moveTo(13, 14)
        ..lineTo(13, 9)
        ..relativeArcToPoint(
          const Offset(2, -2),
          radius: const Radius.circular(2),
        )
        ..relativeLineTo(4, 0)
        ..moveTo(13, 14)
        ..relativeLineTo(0, 5)
        ..relativeArcToPoint(
          const Offset(2, 2),
          radius: const Radius.circular(2),
          clockwise: false,
        )
        ..relativeLineTo(4, 0),
      stroke,
    );
}

/// A function, `ƒ` with `×` by it as in `f(x)`: a call, with the effects
/// folded in it.
class FunctionIcon extends _NodeIcon {
  const FunctionIcon({super.key, required super.size, required super.color});

  @override
  String get _kind => 'function';

  @override
  void _draw(Canvas canvas, Paint stroke) => canvas.drawPath(
    Path()
      // The hook of the ƒ.
      ..moveTo(5.5, 22.5)
      ..relativeCubicTo(1.6, 0, 2.4, -1.1, 2.8, -3.1)
      ..lineTo(11.6, 8.6)
      ..relativeCubicTo(.5, -2.1, 1.3, -3.1, 3, -3.1)
      // Its bar.
      ..moveTo(8, 12.5)
      ..relativeLineTo(6, 0)
      // The ×.
      ..moveTo(16.5, 13.5)
      ..relativeLineTo(6, 6)
      ..moveTo(22.5, 13.5)
      ..relativeLineTo(-6, 6),
    stroke,
  );
}
