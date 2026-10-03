import 'dart:math' as math;

import 'geometry.dart';
import 'graph_layout.dart';
import 'layout_graph.dart';

/// Step 9: what a layout breaks of the rules every layout must keep, one
/// line each; empty when it keeps them all.
///
/// - Arrows run only horizontally, vertically or at 45°.
/// - Parallel pieces of different arrows are at least a lane gap apart.
/// - No arrow passes through a tile or a node's name or place.
/// - An arrow leaves its exit going right, straight for at least its label
///   with the counter's room, and enters its input going right, straight for
///   at least the least input straight.
/// - The arrowhead's tip points at the bar, an arrow gap before it.
/// - A bar is in the middle of its tile's side, off the rounded corners;
///   inputs on it are at least a port gap apart.
/// - Loops cross nothing. (A loop in a capsule with other arrows
///   leaves its capsule off the edge and may cross its neighbours: the one
///   rule a layout cannot always keep.)
/// - Chips do not cover tiles, arrowheads or each other; nodes do not
///   overlap.
/// - A frame holds the body in it, which keeps these rules in turn; its
///   bar is level with the body's start and its exits with the body's end,
///   and straight links join them across the frame's room. (An arrow
///   passing through a frame passes through a tile.)
List<String> checkLayout(GraphLayout layout) {
  final o = layout.options;
  final problems = <String>[];
  final edges = layout.edges;
  String name(EdgePath e) => '${e.from}#${e.exitIndex}.${e.listIndex}->${e.to}';

  for (final edge in edges) {
    final segments = _segments(edge.points);
    for (final s in segments) {
      if (!s.isAllowedDirection) {
        problems.add(
          '${name(edge)}: piece $s is not horizontal, vertical '
          'or at 45°',
        );
      }
    }
    // Ends.
    final first = segments.first;
    final last = segments.last;
    final exit = layout.exits.firstWhere(
      (x) => x.node == edge.from && x.index == edge.exitIndex,
    );
    final firstTurn = segments.length > 1 ? _tangent(edge, 1, o) : 0.0;
    if (!first.isHorizontal || first.b.x <= first.a.x) {
      problems.add('${name(edge)}: does not leave its exit going right');
    } else if (segments.length > 1 &&
        first.length - firstTurn < exit.reach - 1e-6) {
      problems.add(
        '${name(edge)}: straight piece at the exit '
        '${_n(first.length - firstTurn)} is shorter than its label and counter '
        '${_n(exit.reach)}',
      );
    }
    final lastTurn = segments.length > 1
        ? _tangent(edge, edge.points.length - 2, o)
        : 0.0;
    final straight = segments.length > 1
        ? last.length - lastTurn
        : last.length - exit.reach;
    if (!last.isHorizontal || last.b.x <= last.a.x) {
      problems.add('${name(edge)}: does not enter its input going right');
    } else if (straight < o.minInputStraight - 1e-6) {
      problems.add(
        '${name(edge)}: straight piece at the input ${_n(straight)} is '
        'shorter than ${_n(o.minInputStraight)}',
      );
    }
    // The arrowhead.
    final target = layout.nodes[edge.to]!;
    final bar = target.bar;
    if (bar == null) {
      problems.add('${name(edge)}: ${edge.to} has no input bar');
    } else {
      final tip = edge.tip;
      if ((tip.x - (bar.rect.left - o.arrowGap)).abs() > 1e-6 ||
          (tip.x - edge.points.last.x - o.arrowLength).abs() > 1e-6) {
        problems.add(
          '${name(edge)}: arrowhead tip $tip is not an arrow gap '
          'before the bar of ${edge.to}',
        );
      }
      if (tip.y < bar.rect.top || tip.y > bar.rect.bottom) {
        problems.add(
          '${name(edge)}: arrowhead tip $tip misses the bar of '
          '${edge.to}',
        );
      }
    }
    // Through nodes.
    for (final node in layout.nodes.values) {
      for (final rect in [node.tile, node.nameRect, node.placeRect]) {
        for (final s in segments) {
          if (s.entersInterior(rect)) {
            problems.add('${name(edge)}: piece $s passes through ${node.id}');
          }
        }
      }
    }
  }

  // Parallel pieces.
  final pieces = [
    for (final edge in edges)
      for (final s in _segments(edge.points)) (edge, s),
  ];
  for (var i = 0; i < pieces.length; i++) {
    for (var j = i + 1; j < pieces.length; j++) {
      final (ea, a) = pieces[i];
      final (eb, b) = pieces[j];
      if (identical(ea, eb)) continue;
      final gap = _parallelGap(a, b);
      if (gap != null && gap < o.laneGap - 1e-6) {
        problems.add(
          '${name(ea)} and ${name(eb)}: parallel pieces $a and $b '
          'are ${_n(gap)} apart',
        );
      }
    }
  }

  // Loops cross nothing.
  for (final loop in edges.where((e) => e.kind == EdgeKind.loop)) {
    for (final other in edges) {
      if (identical(other, loop)) continue;
      if (crossingsBetween(loop.points, other.points) > 0) {
        problems.add('${name(loop)}: loop crosses ${name(other)}');
      }
    }
  }

  // Bars.
  for (final node in layout.nodes.values) {
    final bar = node.bar;
    if (bar == null) continue;
    final middle =
        node.frame?.entry?.a.y ?? (node.tile.top + node.tile.bottom) / 2;
    if (((bar.rect.top + bar.rect.bottom) / 2 - middle).abs() > 1e-6) {
      problems.add(
        node.frame?.entry == null
            ? '${node.id}: bar is not in the middle of the tile'
            : '${node.id}: bar is not level with the start in the frame',
      );
    }
    // A port's bar is on its frame's side, not on a tile.
    if (!node.port &&
        (bar.rect.top < node.tile.top + o.tileRadius - 1e-6 ||
            bar.rect.bottom > node.tile.bottom - o.tileRadius + 1e-6)) {
      problems.add('${node.id}: bar runs onto the tile\'s corners');
    }
    for (var i = 1; i < bar.inputs.length; i++) {
      if (bar.inputs[i] - bar.inputs[i - 1] < o.portGap - 1e-6) {
        problems.add('${node.id}: inputs closer than ${_n(o.portGap)}');
      }
    }
    for (final y in bar.inputs) {
      if (y < bar.rect.top || y > bar.rect.bottom) {
        problems.add('${node.id}: input at ${_n(y)} is off the bar');
      }
    }
  }

  // Chips and nodes.
  final chips = [
    for (final exit in layout.exits)
      if (exit.labelRect case final rect?) ('${exit.node}#${exit.index}', rect),
  ];
  for (final (owner, chip) in chips) {
    for (final node in layout.nodes.values) {
      if (chip.overlaps(node.tile)) {
        problems.add('$owner: label chip covers the tile of ${node.id}');
      }
    }
    for (final edge in edges) {
      final head = Rect.fromLTRB(
        edge.points.last.x,
        edge.tip.y - 4.5,
        edge.tip.x,
        edge.tip.y + 4.5,
      );
      if (chip.overlaps(head)) {
        problems.add(
          '$owner: label chip covers the arrowhead of ${name(edge)}',
        );
      }
    }
  }
  for (var i = 0; i < chips.length; i++) {
    for (var j = i + 1; j < chips.length; j++) {
      if (chips[i].$2.overlaps(chips[j].$2)) {
        problems.add('${chips[i].$1} and ${chips[j].$1}: label chips overlap');
      }
    }
  }
  for (final node in layout.nodes.values) {
    if (node.frame != null) problems.addAll(_frameProblems(layout, node));
  }

  final boxes = layout.nodes.values.toList();
  for (var i = 0; i < boxes.length; i++) {
    for (var j = i + 1; j < boxes.length; j++) {
      final a = boxes[i];
      final b = boxes[j];
      for (final ra in [a.tile, a.nameRect, a.placeRect]) {
        for (final rb in [b.tile, b.nameRect, b.placeRect]) {
          if (ra.overlaps(rb)) {
            problems.add('${a.id} and ${b.id} overlap');
          }
        }
      }
    }
  }
  return problems;
}

/// What the frame of [node] breaks: the body is not in it, a link or an
/// exit is off its place; and what the body in it breaks, after `id ›`.
List<String> _frameProblems(GraphLayout layout, NodeBox node) {
  final frame = node.frame!;
  final tile = node.tile;
  final inner = frame.inner;
  final body = inner.bounds;
  final problems = <String>[
    if (body.left < tile.left - 1e-6 ||
        body.top < tile.top - 1e-6 ||
        body.right > tile.right + 1e-6 ||
        body.bottom > tile.bottom + 1e-6)
      '${node.id}: the body is not in the frame',
  ];
  final ends = inner.nodes.values.where((n) => n.kind == NodeKind.end);
  if (ends.length > 1) problems.add('${node.id}: the body has several ends');
  bool level(Segment link, Point from, Point to) =>
      (link.a - from).length < 1e-6 && (link.b - to).length < 1e-6;
  final start = inner.nodes[startMarker]?.tile;
  final entry = frame.entry;
  if ((start == null) != (entry == null) ||
      start != null &&
          !level(
            entry!,
            Point(tile.left, start.center.y),
            Point(start.left, start.center.y),
          )) {
    problems.add('${node.id}: the link to the start is off its place');
  }
  final end = ends.firstOrNull?.tile;
  final exit = frame.exit;
  if ((end == null) != (exit == null) ||
      end != null &&
          !level(
            exit!,
            Point(end.right, end.center.y),
            Point(tile.right, end.center.y),
          )) {
    problems.add('${node.id}: the link from the end is off its place');
  }
  // Exits side by side are round the link, a single one on it.
  final outs = [
    for (final out in layout.exits)
      if (out.node == node.id) out.handle,
  ];
  if (exit != null && outs.isNotEmpty) {
    final span = outs.reduce((a, b) => a.union(b));
    if (exit.b.y < span.top - 1e-6 || exit.b.y > span.bottom + 1e-6) {
      problems.add('${node.id}: the exits are off the end\'s link');
    }
  }
  for (final other in inner.nodes.values) {
    if (other.kind == NodeKind.end || other.id == startMarker) continue;
    for (final link in [?entry, ?exit]) {
      for (final rect in [other.tile, other.nameRect, other.placeRect]) {
        if (Segment(link.a, link.b).entersInterior(rect)) {
          problems.add('${node.id}: a link passes through ${other.id}');
        }
      }
    }
  }
  for (final link in [?entry, ?exit]) {
    if (link.length < 1e-6) continue;
    for (final edge in inner.edges) {
      if (crossingsBetween([link.a, link.b], edge.points) > 0) {
        problems.add('${node.id}: a link crosses an arrow in the frame');
      }
    }
  }
  return [
    ...problems,
    for (final problem in checkLayout(inner)) '${node.id} › $problem',
  ];
}

/// How many times arrows cross each other.
int countCrossings(GraphLayout layout) {
  final lines = [for (final edge in layout.edges) edge.points];
  var count = 0;
  for (var i = 0; i < lines.length; i++) {
    for (var j = i + 1; j < lines.length; j++) {
      count += crossingsBetween(lines[i], lines[j]);
    }
  }
  return count;
}

/// How many times the polylines [a] and [b] cross.
int crossingsBetween(List<Point> a, List<Point> b) {
  var count = 0;
  final sa = _segments(a);
  final sb = _segments(b);
  for (final x in sa) {
    for (final y in sb) {
      if (x.crosses(y)) count++;
    }
  }
  return count;
}

List<Segment> _segments(List<Point> points) => [
  for (var i = 1; i < points.length; i++) Segment(points[i - 1], points[i]),
];

/// The distance between [a] and [b] when they are parallel and side by side
/// for a stretch; `null` otherwise.
double? _parallelGap(Segment a, Segment b) {
  if (a.isHorizontal && b.isHorizontal) {
    final overlap = _overlap(a.a.x, a.b.x, b.a.x, b.b.x);
    return overlap > 1e-6 ? (a.a.y - b.a.y).abs() : null;
  }
  if (a.isVertical && b.isVertical) {
    final overlap = _overlap(a.a.y, a.b.y, b.a.y, b.b.y);
    return overlap > 1e-6 ? (a.a.x - b.a.x).abs() : null;
  }
  if (a.isDiagonal && b.isDiagonal) {
    final da = a.b - a.a;
    final db = b.b - b.a;
    if ((da.x * db.y - da.y * db.x).abs() > 1e-6) return null;
    // Project onto the shared direction and its normal.
    final unit = da * (1 / da.length);
    double along(Point p) => p.x * unit.x + p.y * unit.y;
    double across(Point p) => p.x * -unit.y + p.y * unit.x;
    final overlap = _overlap(along(a.a), along(a.b), along(b.a), along(b.b));
    return overlap > 1e-6 ? (across(a.a) - across(b.a)).abs() : null;
  }
  return null;
}

double _overlap(double a1, double a2, double b1, double b2) {
  final lo = [a1 < a2 ? a1 : a2, b1 < b2 ? b1 : b2];
  final hi = [a1 < a2 ? a2 : a1, b1 < b2 ? b2 : b1];
  final start = lo[0] > lo[1] ? lo[0] : lo[1];
  final end = hi[0] < hi[1] ? hi[0] : hi[1];
  return end - start;
}

/// How much of the pieces next to corner [index] of [edge] its rounding
/// takes.
double _tangent(EdgePath edge, int index, LayoutOptions options) {
  final points = edge.points;
  final prev = points[index - 1];
  final corner = points[index];
  final next = points[index + 1];
  final d1 = corner - prev;
  final d2 = next - corner;
  final cos = (d1.x * d2.x + d1.y * d2.y) / (d1.length * d2.length);
  // tan(θ/2) = sqrt((1 - cos θ) / (1 + cos θ)).
  final factor = cos >= 1 ? 0.0 : math.sqrt((1 - cos) / (1 + cos));
  final inRoom = index == 1 ? d1.length : d1.length / 2;
  final outRoom = index == points.length - 2 ? d2.length : d2.length / 2;
  final tangent = options.cornerRadius * factor;
  final room = inRoom < outRoom ? inRoom : outRoom;
  return tangent < room ? tangent : room;
}

String _n(double value) => value.toStringAsFixed(1);
