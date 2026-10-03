import 'dart:math' as math;

import 'coordinates.dart';
import 'geometry.dart';
import 'graph_layout.dart';
import 'lanes.dart';
import 'layout_graph.dart';
import 'ports.dart';

/// Step 8: builds every arrow from its ports and lanes, and the layout with
/// everything moved so that it starts at (0, 0).
///
/// An arrow is a polyline: straight out of its exit, through its turns, a
/// straight piece into its input that ends at the arrowhead's base. Corners
/// are rounded with the options' corner radius.
GraphLayout route(
  LayoutGraph graph,
  Map<GNode, Ports> ports,
  Map<GNode, NodeFrame> frames,
  Lanes lanes,
  Map<GEdge, double> depth,
  LayoutOptions options,
) {
  final o = options;
  double leftOf(GNode node) => lanes.left[node.layer];
  double exitY(GEdge edge) =>
      edge.from.item.y + ports[edge.from]!.exitAt[edge]!;
  double inputY(GEdge edge) => edge.to.item.y + ports[edge.to]!.inputAt[edge]!;
  double base(GNode node) =>
      leftOf(node) - o.barWidth / 2 - o.arrowGap - o.arrowLength;

  final paths = <GEdge, List<Point>>{};
  for (final edge in graph.edges) {
    final start = Point(leftOf(edge.from) + o.tile, exitY(edge));
    final end = Point(base(edge.to), inputY(edge));
    final points = <Point>[start];
    switch (edge.kind) {
      case EdgeKind.forward:
        for (final seg in edge.segs) {
          final turn = lanes.forward[seg];
          if (turn == null) continue;
          final from = outY(seg, ports);
          final to = inY(seg, ports);
          points
            ..add(Point(turn.x, from))
            ..add(Point(turn.end, to));
        }
      case EdgeKind.back:
        final out = lanes.backOut[edge]!.x;
        final into = lanes.backIn[edge]!.x;
        final lane = depth[edge]!;
        points.addAll([
          Point(out, start.y),
          Point(out, lane),
          Point(into, lane),
          Point(into, end.y),
        ]);
      case EdgeKind.loop:
        final out = lanes.loopOut[edge]!;
        final into = lanes.loopIn[edge]!;
        final far = out.ends[1].$1;
        points.addAll([
          Point(out.x, start.y),
          Point(out.x, far),
          Point(into.x, far),
          Point(into.x, end.y),
        ]);
    }
    points.add(end);
    paths[edge] = _simplify(points);
  }

  // Everything drawn, to move the layout to (0, 0).
  var bounds = const Rect.fromLTRB(
    double.infinity,
    double.infinity,
    double.negativeInfinity,
    double.negativeInfinity,
  );
  void cover(Rect rect) => bounds = bounds.union(rect);
  for (final node in graph.nodes) {
    final frame = frames[node]!;
    final shift = Point(leftOf(node), 0);
    cover(frame.tile.shift(shift));
    for (final rect in frame.obstacles) {
      cover(rect.shift(shift));
    }
  }
  for (final points in paths.values) {
    for (final p in points) {
      cover(Rect.fromLTRB(p.x, p.y, p.x, p.y));
    }
  }
  if (graph.nodes.isEmpty) bounds = const Rect.fromLTWH(0, 0, 0, 0);
  final origin = Point(-bounds.left, -bounds.top);
  Point at(Point p) => p + origin;

  final nodes = <String, NodeBox>{};
  final exits = <ExitBox>[];
  for (final node in graph.nodes) {
    final frame = frames[node]!;
    final shift = Point(leftOf(node), 0) + origin;
    final port = ports[node]!;
    final bar = frame.bar;
    nodes[node.id] = NodeBox(
      id: node.id,
      kind: node.kind,
      node: node.node,
      name: node.name,
      fullName: node.fullName,
      place: node.place,
      inside: node.inside,
      layer: node.layer,
      tile: frame.tile.shift(shift),
      nameRect: frame.name.shift(shift),
      placeRect: frame.place.shift(shift),
      marks: frame.marks.shift(shift),
      status: frame.status.shift(shift),
      bar: bar == null
          ? null
          : InputBar(
              rect: Rect.fromLTRB(
                frame.tile.left - o.barWidth / 2,
                bar.top,
                frame.tile.left + o.barWidth / 2,
                bar.bottom,
              ).shift(shift),
              inputs: [
                for (final edge in port.inputs)
                  node.item.y + port.inputAt[edge]! + shift.y,
              ],
            ),
    );
    for (final exit in node.exits) {
      final e = frame.exits[exit]!;
      final anchor = Point(e.x, e.y) + shift;
      exits.add(
        ExitBox(
          node: node.id,
          index: exit.index,
          label: exit.label,
          shape: exit.isCapsule ? ExitShape.capsule : ExitShape.dot,
          anchor: anchor,
          handle: Rect.fromLTRB(
            anchor.x - _dot,
            e.arrows.first + shift.y - _dot,
            anchor.x + _dot,
            e.arrows.last + shift.y + _dot,
          ),
          labelRect: e.label?.shift(shift),
          counterAt: e.counter + shift,
          reach: e.reach,
        ),
      );
    }
  }

  final edges = <EdgePath>[];
  for (final edge in graph.edges) {
    final points = [for (final p in paths[edge]!) at(p)];
    edges.add(
      EdgePath(
        from: edge.from.id,
        exitIndex: edge.exit.index,
        listIndex: edge.listIndex,
        to: edge.to.id,
        kind: edge.kind,
        points: points,
        tip: points.last + Point(o.arrowLength, 0),
        pieces: roundCorners(points, o.cornerRadius),
      ),
    );
  }

  return GraphLayout(
    nodes: nodes,
    exits: exits,
    edges: edges,
    bounds: Rect.fromLTWH(
      0,
      0,
      math.max(0, bounds.width),
      math.max(0, bounds.height),
    ),
    options: options,
  );
}

/// The radius of an exit's dot.
const double _dot = 5.5;

/// [points] without repeated points and without points in the middle of a
/// straight run.
List<Point> _simplify(List<Point> points) {
  final result = <Point>[];
  for (final p in points) {
    if (result.isNotEmpty && (result.last - p).length < 1e-6) continue;
    if (result.length >= 2) {
      final a = result[result.length - 2];
      final b = result.last;
      final cross = (b.x - a.x) * (p.y - b.y) - (b.y - a.y) * (p.x - b.x);
      final dot = (b.x - a.x) * (p.x - b.x) + (b.y - a.y) * (p.y - b.y);
      if (cross.abs() < 1e-6 && dot > 0) {
        result[result.length - 1] = p;
        continue;
      }
    }
    result.add(p);
  }
  return result;
}
