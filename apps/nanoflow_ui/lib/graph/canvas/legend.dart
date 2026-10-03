import 'package:flutter/material.dart';

import '../../state/texts.dart' show shortId;
import 'canvas_marks.dart';
import 'canvas_style.dart';

/// What the canvas's lines mean, in its bottom right corner
/// (docs/design/task-graph.html): the selected run's path, back arrows.
/// Only what the canvas has is named; with nothing to name it is empty.
class Legend extends StatelessWidget {
  const Legend({super.key, required this.runId, required this.backEdges});

  /// The selected run; `null` when none is. Shortened, its full id in a
  /// tooltip.
  final String? runId;

  /// The tone back arrows are shown in, as the canvas draws them; `null`
  /// when the graph has none.
  final Tone? backEdges;

  @override
  Widget build(BuildContext context) {
    final items = [
      if (runId case final run?)
        Tooltip(
          message: run,
          child: _item(
            Container(
              width: 16,
              height: 2.4,
              decoration: const BoxDecoration(
                color: CanvasColors.path,
                borderRadius: BorderRadius.all(Radius.circular(2)),
              ),
            ),
            'taken by run ${shortId(run)}',
          ),
        ),
      if (backEdges case final tone?)
        _item(
          CustomPaint(
            size: const Size(16, 2.4),
            painter: _DashPainter(CanvasColors.line(tone)),
          ),
          'back edge',
        ),
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
      decoration: BoxDecoration(
        color: CanvasColors.panel,
        border: Border.all(color: CanvasColors.panelBorder),
        borderRadius: const BorderRadius.all(Radius.circular(10)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, spacing: 16, children: items),
    );
  }

  static Widget _item(Widget sample, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    spacing: 7,
    children: [
      sample,
      Text(text, style: CanvasText.legend, textScaler: TextScaler.noScaling),
    ],
  );
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
