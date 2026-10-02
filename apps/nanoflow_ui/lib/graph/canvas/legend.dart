import 'package:flutter/widgets.dart';

import 'canvas_style.dart';

/// What the canvas's lines mean, in its bottom right corner
/// (docs/design/task-graph.html): the selected run's path, back arrows,
/// outcomes that end the run. Only what the canvas has is named; with
/// nothing to name it is empty.
class Legend extends StatelessWidget {
  const Legend({
    super.key,
    required this.runId,
    required this.backEdges,
    required this.emptyTargets,
  });

  /// The selected run, shortened; `null` when none is.
  final String? runId;

  /// Whether the graph has back arrows.
  final bool backEdges;

  /// Whether the graph has outcomes with no target.
  final bool emptyTargets;

  @override
  Widget build(BuildContext context) {
    final items = [
      if (runId case final run?)
        _item(
          Container(
            width: 16,
            height: 2.4,
            decoration: const BoxDecoration(
              color: CanvasColors.path,
              borderRadius: BorderRadius.all(Radius.circular(2)),
            ),
          ),
          'taken by run $run',
        ),
      if (backEdges)
        _item(
          CustomPaint(
            size: const Size(16, 2.4),
            // Without a run, arrows are all one gray, back ones too.
            painter: _DashPainter(
              runId == null ? CanvasColors.taken : CanvasColors.path,
            ),
          ),
          'back edge',
        ),
      if (emptyTargets)
        _item(
          CustomPaint(size: const Size(18, 12), painter: _StubPainter()),
          'outcome with no target — run ends',
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

/// A stub with its cross bar.
class _StubPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..drawLine(
        const Offset(0, 6),
        const Offset(12, 6),
        Paint()
          ..color = CanvasColors.stubBar
          ..strokeWidth = 1.6,
      )
      ..drawLine(
        const Offset(12, 1.5),
        const Offset(12, 10.5),
        Paint()
          ..color = CanvasColors.stubBar
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round,
      );
  }

  @override
  bool shouldRepaint(_StubPainter old) => false;
}
