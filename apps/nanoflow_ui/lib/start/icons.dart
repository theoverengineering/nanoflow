import 'package:flutter/widgets.dart';

/// The start screen's graph icon: three nodes, and the arrows between them
/// unless [linked] is false (the file is gone). The SVG of start.html, 18
/// units drawn at [size].
class GraphIcon extends StatelessWidget {
  const GraphIcon({
    super.key,
    required this.color,
    this.linked = true,
    this.size = 20,
  });

  final Color color;
  final bool linked;
  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _GraphIconPainter(color, linked),
  );
}

class _GraphIconPainter extends CustomPainter {
  _GraphIconPainter(this.color, this.linked);

  final Color color;
  final bool linked;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 18);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    for (final (x, y) in [(1.8, 6.6), (11.4, 2.2), (11.4, 11.0)]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, 4.8, 4.8),
          const Radius.circular(1.2),
        ),
        stroke,
      );
    }
    if (!linked) return;
    final arrows = Path()
      ..moveTo(6.6, 9)
      ..lineTo(8.4, 9)
      ..cubicTo(9.3, 9, 9.7, 8.5, 9.7, 7.7)
      ..lineTo(9.7, 5.9)
      ..cubicTo(9.7, 5.1, 10.1, 4.6, 11.0, 4.6)
      ..lineTo(11.4, 4.6)
      ..moveTo(8.4, 9)
      ..cubicTo(9.3, 9, 9.7, 9.5, 9.7, 10.3)
      ..lineTo(9.7, 12.1)
      ..cubicTo(9.7, 12.9, 10.1, 13.4, 11.0, 13.4)
      ..lineTo(11.4, 13.4);
    canvas.drawPath(arrows, stroke);
  }

  @override
  bool shouldRepaint(_GraphIconPainter old) =>
      old.color != color || old.linked != linked;
}

/// The folder on the `Open graph` button: the SVG of start.html, 16 units
/// drawn at [size].
class FolderIcon extends StatelessWidget {
  const FolderIcon({super.key, required this.color, this.size = 14});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _FolderIconPainter(color));
}

class _FolderIconPainter extends CustomPainter {
  _FolderIconPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 16);
    const corner = Radius.circular(0.9);
    final folder = Path()
      ..moveTo(1.6, 12.6)
      ..lineTo(1.6, 3.4)
      ..arcToPoint(const Offset(2.5, 2.5), radius: corner)
      ..lineTo(5.7, 2.5)
      ..lineTo(7.2, 4.3)
      ..lineTo(13.5, 4.3)
      ..arcToPoint(const Offset(14.4, 5.2), radius: corner)
      ..lineTo(14.4, 12.6)
      ..arcToPoint(const Offset(13.5, 13.5), radius: corner)
      ..lineTo(2.5, 13.5)
      ..arcToPoint(const Offset(1.6, 12.6), radius: corner)
      ..close();
    canvas.drawPath(
      folder,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_FolderIconPainter old) => old.color != color;
}
