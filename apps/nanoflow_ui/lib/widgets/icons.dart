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

/// A check: `passes`, `Copied`, a step that finished. 10 units.
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

/// A step's terminal, or a condition's diamond when [fork]. 28 units.
class NodeIcon extends StatelessWidget {
  const NodeIcon({
    super.key,
    required this.fork,
    required this.size,
    required this.color,
    this.strokeWidth = 1.6,
  });

  final bool fork;
  final double size;
  final Color color;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) => _LineIcon(
    kind: fork ? 'condition' : 'step',
    units: 28,
    size: size,
    color: color,
    strokeWidth: strokeWidth,
    draw: fork ? _fork : _terminal,
  );

  static void _fork(Canvas canvas, Paint stroke) => canvas.drawPath(
    Path()
      ..moveTo(14, 4.5)
      ..lineTo(23.5, 14)
      ..lineTo(14, 23.5)
      ..lineTo(4.5, 14)
      ..close(),
    stroke,
  );

  static void _terminal(Canvas canvas, Paint stroke) => canvas
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
