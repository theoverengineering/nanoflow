import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../theme.dart';

/// The turning sign of something running, as the mockups draw it: a dim
/// ring with a bright quarter, 18 units across, on a disc of [background]
/// when given.
///
/// It repaints as it turns and builds nothing: a rebuild under a layout
/// builder, such as the canvas's, would lay out and paint everything again on
/// every frame.
class Spinner extends StatefulWidget {
  const Spinner({
    super.key,
    required this.size,
    required this.strokeWidth,
    this.background,
  });

  final double size;

  /// The ring's width, in units of 18 across.
  final double strokeWidth;

  final Color? background;

  @override
  State<Spinner> createState() => _SpinnerState();
}

class _SpinnerState extends State<Spinner> with SingleTickerProviderStateMixin {
  late final AnimationController _turns = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _turns.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      size: Size.square(widget.size),
      painter: _SpinnerPainter(
        _turns,
        strokeWidth: widget.strokeWidth,
        background: widget.background,
      ),
    ),
  );
}

class _SpinnerPainter extends CustomPainter {
  _SpinnerPainter(this.turns, {required this.strokeWidth, this.background})
    : super(repaint: turns);

  final Animation<double> turns;
  final double strokeWidth;
  final Color? background;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 18);
    if (background case final color?) {
      canvas.drawCircle(const Offset(9, 9), 9, Paint()..color = color);
    }
    canvas
      ..translate(9, 9)
      ..rotate(turns.value * 2 * math.pi)
      ..translate(-9, -9);
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = AppColors.runningRing;
    canvas
      ..drawCircle(const Offset(9, 9), 6.5, ring)
      ..drawArc(
        Rect.fromCircle(center: const Offset(9, 9), radius: 6.5),
        -math.pi / 2,
        math.pi / 2,
        false,
        ring
          ..color = AppColors.running
          ..strokeCap = StrokeCap.round,
      );
  }

  @override
  bool shouldRepaint(_SpinnerPainter old) =>
      old.turns != turns ||
      old.strokeWidth != strokeWidth ||
      old.background != background;
}
