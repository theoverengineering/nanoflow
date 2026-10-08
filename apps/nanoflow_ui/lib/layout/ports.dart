import 'dart:math' as math;

import 'layout_graph.dart';

/// Where a node's exits and inputs sit, as offsets from the middle of its
/// tile, and how tall the tile is.
final class Ports {
  Ports._(this.node, this.height);

  final GNode node;

  /// The tile's height.
  final double height;

  /// The exits, top to bottom.
  final List<GExit> slots = [];

  /// The middle of each exit: a dot or a capsule.
  final Map<GExit, double> slotAt = {};

  /// Where each arrow leaves the tile; arrows of a capsule are a capsule gap
  /// apart, in list order.
  final Map<GEdge, double> exitAt = {};

  /// The arrows into the node, top to bottom along the input bar.
  final List<GEdge> inputs = [];

  /// Where each arrow enters the bar.
  final Map<GEdge, double> inputAt = {};

  /// Loops over the tile, innermost first.
  final List<GEdge> loopsAbove = [];

  /// Loops under the tile, innermost first.
  final List<GEdge> loopsBelow = [];

  /// Half the input bar's length; 0 when nothing comes in.
  double barHalf = 0;

  /// Where the middle of the input bar is, and of the exits: the middle of
  /// the tile; on a frame, level with the body's start and end.
  double get inputCentre => node.framed?.inputCentre ?? 0;
  double get exitCentre => node.framed?.exitCentre ?? 0;
}

/// Step 5: the order of every node's exits and inputs, for the current order
/// of the layers.
///
/// Exits, top to bottom: loops over the tile (nested), back arrows over the
/// graph ([GEdge.over]), forward arrows (a ladder: by where they go in the
/// next layer), back arrows under the graph, loops under the tile (nested).
/// Back arrows nest on either side: the higher the exit, the lower its
/// lane. A capsule takes its place by its middle arrow.
///
/// A fork's `true` stands above its `false` whatever kind their arrows are
/// ([GNode.fork]): a loop of `true` goes over the tile, of `false` under it,
/// whatever [below] says.
///
/// Inputs, top to bottom: loops over the tile (nested), back arrows over
/// the graph, forward arrows (a ladder: by where they come from in the layer
/// before), back arrows under the graph, loops under the tile (nested). Back
/// arrows nest on either side: the lower the lane, the higher the input.
///
/// [below] are the nodes whose loops go under the tile. Returns the ports of
/// every node, and sets the lane levels of back arrows in [backLevels], on
/// each side of the graph: 1 is the lane nearest the graph, a wider arrow
/// runs further off it.
Map<GNode, Ports> assignPorts(
  LayoutGraph graph,
  LayoutOptions options, {
  required Set<GNode> below,
  required Map<GEdge, int> backLevels,
}) {
  final ports = <GNode, Ports>{};
  for (final node in graph.nodes) {
    final port = Ports._(node, tileHeight(node, options));
    ports[node] = port;
    _orderExits(port, options, below: below.contains(node));
  }
  backLevels
    ..clear()
    ..addAll(_backLevels(graph, ports));
  for (final node in graph.nodes) {
    _orderInputs(ports[node]!, ports, backLevels, options);
  }
  return ports;
}

/// The height of [node]'s tile: room for its exits an exit gap apart, and
/// for its input bar on the straight part of the left side; at least a
/// tile's side, a marker's height for a marker.
///
/// A capsule counts as an exit plus half an exit for every arrow over one.
///
/// A frame is as tall as it is made (`FramedBody`); a port only as tall as
/// its exits and bar, which are drawn on its frame's side.
double tileHeight(GNode node, LayoutOptions options) {
  if (node.framed case final framed?) return framed.height;
  final units = node.exits.fold(0.0, (sum, exit) => sum + exitUnits(exit));
  if (node.port) {
    return math.max(
      units * options.exitGap,
      node.inEdges.isEmpty ? 0 : 2 * _barHalf(node, options),
    );
  }
  final exits = units == 0 ? 0.0 : (units + 1) * options.exitGap;
  final inputs = node.inEdges.isEmpty
      ? 0.0
      : barLength(node.inEdges.length, options) + 2 * options.tileRadius;
  final least = node.isMarker ? options.marker : options.tile;
  return math.max(least, math.max(exits, inputs));
}

/// The room [exit] takes on its tile, in exit gaps.
double exitUnits(GExit exit) =>
    exit.isCapsule ? 1 + 0.5 * (exit.edges.length - 1) : 1;

/// The length of an input bar with [count] inputs a port gap apart: half a
/// gap beyond the outer inputs, never shorter than the least bar.
double barLength(int count, LayoutOptions options) =>
    math.max(options.minBar, count * options.portGap);

/// Half the length of the input bar of [node], which arrows come in to: the
/// end of a body in a frame reaches past the frame's arrows out too.
double _barHalf(GNode node, LayoutOptions options) =>
    math.max(barLength(node.inEdges.length, options) / 2, node.leastBarHalf);

/// How far from the middle of [node]'s exits its outermost arrow is, in
/// whatever order the exits stand: with one exit, half its capsule.
double arrowsReach(GNode node, LayoutOptions options) {
  final units = node.exits.fold(0.0, (sum, exit) => sum + exitUnits(exit));
  return node.exits.fold(
    0.0,
    (most, exit) => math.max(
      most,
      (units - exitUnits(exit)) * options.exitGap / 2 +
          (exit.edges.length - 1) * options.capsuleGap / 2,
    ),
  );
}

/// The arrow of [exit] whose place orders the exit: the middle one of a list.
GEdge middleArrow(GExit exit) => exit.edges[(exit.edges.length - 1) ~/ 2];

void _orderExits(Ports port, LayoutOptions options, {required bool below}) {
  if (port.node.fork case (:final yes, :final no)) {
    // A fork's true stands above its false, whatever kind its arrows are:
    // a loop of true goes over the tile, a loop of false under it.
    for (final (exit, loops) in [
      (yes, port.loopsAbove),
      (no, port.loopsBelow),
    ]) {
      loops.addAll(exit.edges.where((edge) => edge.kind == EdgeKind.loop));
    }
    port.slots.addAll([yes, no]);
    _placeExits(port, options);
    return;
  }
  final loops = <GExit>[];
  final forward = <GExit>[];
  final over = <GExit>[];
  final back = <GExit>[];
  for (final exit in port.node.exits) {
    final arrow = middleArrow(exit);
    switch (arrow.kind) {
      case EdgeKind.loop:
        loops.add(exit);
      case EdgeKind.forward:
        forward.add(exit);
      case EdgeKind.back:
        (arrow.over ? over : back).add(exit);
    }
  }
  forward.sort((a, b) {
    final x = middleArrow(a).segs.first.to.order;
    final y = middleArrow(b).segs.first.to.order;
    return x != y ? x.compareTo(y) : a.index.compareTo(b.index);
  });
  // Back arrows nest on either side: under the graph the higher exit goes
  // further back, round the others; over it, the lower one does.
  int backOrder(GExit a, GExit b, {required bool over}) {
    final x = middleArrow(a).to;
    final y = middleArrow(b).to;
    if (x.layer != y.layer) {
      return over ? y.layer.compareTo(x.layer) : x.layer.compareTo(y.layer);
    }
    if (x.item.order != y.item.order) {
      return x.item.order.compareTo(y.item.order);
    }
    return a.index.compareTo(b.index);
  }

  back.sort((a, b) => backOrder(a, b, over: false));
  over.sort((a, b) => backOrder(a, b, over: true));
  // Loops nest: the first declared is the innermost, nearest the tile's top
  // over it and nearest the bottom under it.
  final loopEdges = [
    for (final exit in port.node.exits)
      for (final edge in exit.edges)
        if (edge.kind == EdgeKind.loop) edge,
  ];
  (below ? port.loopsBelow : port.loopsAbove).addAll(loopEdges);
  port.slots.addAll([
    if (!below) ...loops,
    ...over,
    ...forward,
    ...back,
    if (below) ...loops.reversed,
  ]);
  _placeExits(port, options);
}

/// Puts the exits of [port] in [Ports.slots]' order, an exit gap apart
/// round the middle of its exits, and their arrows a capsule gap apart.
void _placeExits(Ports port, LayoutOptions options) {
  final units = port.slots.fold(0.0, (sum, exit) => sum + exitUnits(exit));
  var cursor = port.exitCentre - units * options.exitGap / 2;
  for (final exit in port.slots) {
    final span = exitUnits(exit) * options.exitGap;
    final middle = cursor + span / 2;
    port.slotAt[exit] = middle;
    final count = exit.edges.length;
    for (var i = 0; i < count; i++) {
      port.exitAt[exit.edges[i]] =
          middle + (i - (count - 1) / 2) * options.capsuleGap;
    }
    cursor += span;
  }
}

Map<GEdge, int> _backLevels(LayoutGraph graph, Map<GNode, Ports> ports) => {
  for (final over in [false, true])
    ..._sideLevels(
      [
        for (final edge in graph.edges)
          if (edge.kind == EdgeKind.back && edge.over == over) edge,
      ],
      ports,
      over: over,
    ),
};

/// The lane levels of [backs], back arrows on one side of the graph: under
/// it, or [over] it.
Map<GEdge, int> _sideLevels(
  List<GEdge> backs,
  Map<GNode, Ports> ports, {
  required bool over,
}) {
  // Narrow arrows take the lanes nearest the graph. Of two equally wide
  // arrows, the one leaving nearer the lanes' side — lower under the graph,
  // higher over it — takes the nearer lane, so that their turns nest.
  int span(GEdge e) => e.from.layer - e.to.layer;
  int nearer(num a, num b) => over ? a.compareTo(b) : b.compareTo(a);
  backs.sort((a, b) {
    if (span(a) != span(b)) return span(a).compareTo(span(b));
    if (a.from.layer != b.from.layer) {
      return b.from.layer.compareTo(a.from.layer);
    }
    if (a.from != b.from) return nearer(a.from.item.order, b.from.item.order);
    return nearer(ports[a.from]!.exitAt[a]!, ports[b.from]!.exitAt[b]!);
  });
  final levels = <GEdge, int>{};
  for (final edge in backs) {
    // Lanes are shared by arrows whose turns are in different gaps: gap g
    // lies between layers g and g + 1.
    var level = 1;
    for (final MapEntry(key: other, value: otherLevel) in levels.entries) {
      final overlaps =
          other.to.layer - 1 <= edge.from.layer &&
          edge.to.layer - 1 <= other.from.layer;
      if (overlaps && otherLevel >= level) level = otherLevel + 1;
    }
    levels[edge] = level;
  }
  return levels;
}

void _orderInputs(
  Ports port,
  Map<GNode, Ports> ports,
  Map<GEdge, int> backLevels,
  LayoutOptions options,
) {
  final forward = <GEdge>[];
  final over = <GEdge>[];
  final back = <GEdge>[];
  for (final edge in port.node.inEdges) {
    switch (edge.kind) {
      case EdgeKind.forward:
        forward.add(edge);
      case EdgeKind.back:
        (edge.over ? over : back).add(edge);
      case EdgeKind.loop:
        break;
    }
  }
  double sourceY(GEdge edge) {
    final from = edge.segs.last.from;
    final node = from.node;
    return node == null ? 0 : ports[node]!.exitAt[edge]!;
  }

  forward.sort((a, b) {
    final x = a.segs.last.from.order;
    final y = b.segs.last.from.order;
    if (x != y) return x.compareTo(y);
    final sx = sourceY(a);
    final sy = sourceY(b);
    return sx != sy ? sx.compareTo(sy) : a.index.compareTo(b.index);
  });
  // On either side the lower lane comes in higher: under the graph the
  // outer arrow, over it the inner one.
  int lowerLaneFirst(GEdge a, GEdge b, {required bool over}) {
    final x = backLevels[a]!;
    final y = backLevels[b]!;
    if (x == y) return a.index.compareTo(b.index);
    return over ? x.compareTo(y) : y.compareTo(x);
  }

  back.sort((a, b) => lowerLaneFirst(a, b, over: false));
  over.sort((a, b) => lowerLaneFirst(a, b, over: true));
  port.inputs.addAll([
    ...port.loopsAbove,
    ...over,
    ...forward,
    ...back,
    ...port.loopsBelow.reversed,
  ]);
  final count = port.inputs.length;
  for (var i = 0; i < count; i++) {
    port.inputAt[port.inputs[i]] =
        port.inputCentre + (i - (count - 1) / 2) * options.portGap;
  }
  port.barHalf = count == 0 ? 0 : _barHalf(port.node, options);
}
