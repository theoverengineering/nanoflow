import 'package:flutter/widgets.dart';

import '../../layout/layout.dart' as layout;
import 'canvas_marks.dart';
import 'canvas_style.dart';
import 'layout_geometry.dart';

/// Paints the arrows of a layout and the input bars they point at
/// (docs/ui-spec.md «Граф»): rounded corners, one arrowhead size, dashed
/// back arrows, in the tones the marks give them, the lighter over the
/// darker — an arrow into a frame drawn in place runs on to the frame's
/// side without a head, the arrows of its body go on from there
/// (docs/design/code-first/function-frames.html); and in each frame drawn in
/// place, the bar of the end of its body on its right side, in the tone of
/// its exit — the arrows that end the body point at it, as at a tile's bar,
/// and the arrows out of the frame leave its middle —, and the links from
/// its sides to the start and the end of its body where they are off its
/// sides, in the tones of its bar and exit. Under the exits and the tiles:
/// a tile covers the half of its bar on its side, as in the mockups. Clicks
/// go through it.
class EdgesPainter extends CustomPainter {
  EdgesPainter(this.graph, this.marks);

  final layout.GraphLayout graph;
  final CanvasMarks marks;

  /// The width of arrows and of the links in frames.
  static const _width = 1.6;

  /// The arrowhead's half width; its length is the layout's.
  static const _headHalf = 3.9;

  /// An input bar's corners, and the outline of the canvas's colour round
  /// it.
  static const _barRadius = 2.0;
  static const _barOutline = 1.0;

  /// The dashes of back arrows.
  static const _dash = 6.0;
  static const _gap = 5.0;

  @override
  void paint(Canvas canvas, Size size) {
    for (final node in graph.nodes.values) {
      // The bar of the end of a body in a frame is the frame's exit: it is
      // drawn with the frame, in the tone of the frame's exit.
      if (node.port) continue;
      if (node.bar case final bar?) {
        _paintBar(canvas, bar.rect.toRect(), marks.bar(node.id));
      }
      if (node.frame?.endBar case final bar?) {
        _paintBar(canvas, bar.rect.toRect(), marks.exit(node.id));
      }
    }
    for (final node in graph.nodes.values) {
      final frame = node.frame;
      if (frame == null) continue;
      for (final (link, tone) in [
        (frame.entry, marks.bar(node.id)),
        (frame.exit, marks.exit(node.id)),
      ]) {
        if (link == null || link.length < 1e-6) continue;
        canvas.drawLine(
          link.a.toOffset(),
          link.b.toOffset(),
          Paint()
            ..color = CanvasColors.line(tone)
            ..strokeWidth = _width,
        );
      }
    }
    // The lighter over the darker.
    final tones = {for (final edge in graph.edges) edge: marks.edge(edge)};
    for (final tone in const [Tone.untaken, Tone.plain]) {
      for (final edge in graph.edges) {
        if (tones[edge] == tone) _paintEdge(canvas, edge, tone);
      }
    }
  }

  /// The bar [rect], outlined in the canvas's colour, as an exit dot is: it
  /// stands out of the ring round the selected effect's node, under the
  /// arrows.
  void _paintBar(Canvas canvas, Rect rect, Tone tone) => canvas
    ..drawRRect(
      RRect.fromRectAndRadius(
        rect.inflate(_barOutline),
        const Radius.circular(_barRadius + _barOutline),
      ),
      Paint()..color = CanvasColors.background,
    )
    ..drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(_barRadius)),
      Paint()..color = CanvasColors.line(tone),
    );

  void _paintEdge(Canvas canvas, layout.EdgePath edge, Tone tone) {
    var path = Path()..moveTo(edge.points.first.x, edge.points.first.y);
    for (final piece in edge.pieces) {
      switch (piece) {
        case layout.LinePiece(:final to):
          path.lineTo(to.x, to.y);
        case layout.ArcPiece(:final to, :final radius, :final clockwise):
          path.arcToPoint(
            Offset(to.x, to.y),
            radius: Radius.circular(radius),
            clockwise: clockwise,
          );
      }
    }
    // An arrow into a frame drawn in place goes on through the frame's
    // side: it runs on to the side, and the arrow of the body after it has
    // the head.
    final into = graph.nodes[edge.to];
    final through = into?.frame != null;
    if (through) path.lineTo(into!.bar!.rect.left, edge.points.last.y);
    if (edge.isDashed) path = _dashed(path);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = CanvasColors.line(tone)
        ..strokeWidth = _width,
    );
    if (through) return;
    // The line ends at the arrowhead's base; the head draws the tip.
    final base = edge.points.last.toOffset();
    final tip = edge.tip.toOffset();
    final along = tip - base;
    final normal = Offset(-along.dy, along.dx) / along.distance * _headHalf;
    canvas.drawPath(
      Path()
        ..moveTo(base.dx + normal.dx, base.dy + normal.dy)
        ..lineTo(tip.dx, tip.dy)
        ..lineTo(base.dx - normal.dx, base.dy - normal.dy)
        ..close(),
      Paint()..color = CanvasColors.line(tone),
    );
  }

  /// [path] cut into dashes that run on round its corners.
  static Path _dashed(Path path) {
    final dashes = Path();
    for (final contour in path.computeMetrics()) {
      for (var at = 0.0; at < contour.length; at += _dash + _gap) {
        dashes.addPath(contour.extractPath(at, at + _dash), Offset.zero);
      }
    }
    return dashes;
  }

  @override
  bool? hitTest(Offset position) => false;

  @override
  bool shouldRepaint(EdgesPainter old) =>
      old.graph != graph || old.marks != marks;
}
