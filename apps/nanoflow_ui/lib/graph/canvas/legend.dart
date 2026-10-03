import 'package:flutter/material.dart';

import 'canvas_marks.dart';
import 'canvas_style.dart';

/// What the canvas's lines mean, in its bottom right corner
/// (docs/design/task-graph.html): back arrows. Only what the canvas has is
/// named; with nothing to name it is empty.
class Legend extends StatelessWidget {
  const Legend({super.key, required this.backEdges});

  /// The tone back arrows are shown in, as the canvas draws them; `null`
  /// when the graph has none.
  final Tone? backEdges;

  @override
  Widget build(BuildContext context) {
    final tone = backEdges;
    if (tone == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
      decoration: BoxDecoration(
        color: CanvasColors.panel,
        border: Border.all(color: CanvasColors.panelBorder),
        borderRadius: const BorderRadius.all(Radius.circular(10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 7,
        children: [
          CustomPaint(
            size: const Size(16, 2.4),
            painter: _DashPainter(CanvasColors.line(tone)),
          ),
          Text(
            'back edge',
            style: CanvasText.legend,
            textScaler: TextScaler.noScaling,
          ),
        ],
      ),
    );
  }
}

/// Three dashes of a back arrow.
class _DashPainter extends CustomPainter {
  _DashPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (var x = 0.0; x < size.width; x += 6) {
      canvas.drawRect(Rect.fromLTWH(x, 0, 4, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.color != color;
}
