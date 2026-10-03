import 'package:flutter/widgets.dart';

import '../../layout/layout.dart' as layout;
import 'canvas_marks.dart';
import 'canvas_style.dart';
import 'layout_geometry.dart';

/// Paints the arrows of a layout and the input bars they point at
/// (docs/ui-spec.md «Граф»): rounded corners, one arrowhead size, dashed
/// back arrows, in the tones the marks give them, the lighter over the
/// darker; and in each frame drawn in place, the links from its sides to
/// the start and the end of its body, in the tones of its bar and exit.
/// Under the exits and the tiles: a tile covers the half of its bar on its
/// side, as in the mockups. Clicks go through it.
class EdgesPainter extends CustomPainter {
  EdgesPainter(this.graph, this.marks);

  final layout.GraphLayout graph;
  final CanvasMarks marks;

  /// Line widths: the selected run's path is bolder.
  static const _width = 1.6;
  static const _pathWidth = 2.2;

  /// The arrowhead's half width; its length is the layout's.
  static const _headHalf = 3.9;

  /// The dashes of back arrows.
  static const _dash = 6.0;
  static const _gap = 5.0;

  @override
  void paint(Canvas canvas, Size size) {
    final into = <String, List<layout.EdgePath>>{};
    for (final edge in graph.edges) {
      (into[edge.to] ??= []).add(edge);
    }
    for (final node in graph.nodes.values) {
      final bar = node.bar;
      if (bar == null) continue;
      final tone = marks.bar(node.id, into[node.id] ?? const []);
      canvas.drawRRect(
        RRect.fromRectAndRadius(bar.rect.toRect(), const Radius.circular(2)),
        Paint()..color = CanvasColors.line(tone),
      );
    }
    for (final node in graph.nodes.values) {
      final frame = node.frame;
      if (frame == null) continue;
      for (final (link, tone) in [
        (frame.entry, marks.bar(node.id, into[node.id] ?? const [])),
        (frame.exit, marks.exit(node.id, 0)),
      ]) {
        if (link == null) continue;
        canvas.drawLine(
          link.a.toOffset(),
          link.b.toOffset(),
          Paint()
            ..color = CanvasColors.line(tone)
            ..strokeWidth = _width,
        );
      }
    }
    // The selected run's path goes over the rest.
    final tones = {for (final edge in graph.edges) edge: marks.edge(edge)};
    for (final tone in Tone.values) {
      for (final edge in graph.edges) {
        if (tones[edge] == tone) _paintEdge(canvas, edge, tone);
      }
    }
  }

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
    if (edge.isDashed) path = _dashed(path);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = CanvasColors.line(tone)
        ..strokeWidth = tone == Tone.path ? _pathWidth : _width,
    );
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
