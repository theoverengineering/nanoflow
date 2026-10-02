import 'package:flutter/widgets.dart';

/// A 1 px dashed rounded border around [child], as CSS `1px dashed` draws it:
/// 3 px dashes, 3 px apart.
class DashedBorder extends StatelessWidget {
  const DashedBorder({
    super.key,
    required this.color,
    required this.radius,
    required this.child,
  });

  final Color color;
  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) => CustomPaint(
    foregroundPainter: _DashedBorderPainter(color, radius),
    child: child,
  );
}

class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter(this.color, this.radius);

  final Color color;
  final double radius;

  static const _dash = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    // The line runs along the middle of the border, inside the box.
    final outline = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(0.5),
          Radius.circular(radius - 0.5),
        ),
      );
    final dashes = Path();
    for (final contour in outline.computeMetrics()) {
      for (var at = 0.0; at < contour.length; at += 2 * _dash) {
        dashes.addPath(contour.extractPath(at, at + _dash), Offset.zero);
      }
    }
    canvas.drawPath(
      dashes,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) =>
      old.color != color || old.radius != radius;
}
