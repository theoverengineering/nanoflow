/// The layout of a graph for the canvas: where nodes, exits and arrows are.
///
/// Pure Dart: nothing here imports Flutter, so the layout's tests run on the
/// Dart VM. The algorithm is `docs/graph-layout.md`; the rules it serves are
/// `docs/ui-spec.md` «Граф».
library;

import 'package:nanoflow_model/nanoflow_model.dart';

import 'checks.dart';
import 'coordinates.dart';
import 'cycles.dart';
import 'geometry.dart';
import 'lanes.dart';
import 'layers.dart';
import 'layout_graph.dart';
import 'ordering.dart';
import 'ports.dart';
import 'routing.dart';

export 'checks.dart' show checkLayout, countCrossings;
export 'geometry.dart';
export 'layout_graph.dart'
    show EdgeKind, LabelKind, LayoutOptions, MeasureText, monospaceMeasure;

/// A laid out graph. Coordinates start at (0, 0), the top left corner of
/// [bounds].
final class GraphLayout {
  GraphLayout({
    required this.nodes,
    required this.exits,
    required this.edges,
    required this.bounds,
    required this.options,
  });

  /// Every node by name, in declaration order.
  final Map<String, NodeBox> nodes;

  /// Every exit of every node, node by node in declaration order, each node's
  /// exits in declaration order.
  final List<ExitBox> exits;

  /// Every arrow, in declaration order.
  final List<EdgePath> edges;

  /// Everything drawn: tiles, texts, marks, arrows.
  final Rect bounds;

  /// The options the layout was made with.
  final LayoutOptions options;
}

/// Where a node is drawn.
final class NodeBox {
  NodeBox({
    required this.name,
    required this.command,
    required this.isFork,
    required this.isStart,
    required this.layer,
    required this.tile,
    required this.nameRect,
    required this.commandRect,
    required this.startRect,
    required this.marks,
    required this.status,
    required this.bar,
  });

  final String name;

  /// What the node runs, shown under its name: its `command` or `decide`.
  final String command;

  /// A fork (a fork icon), not a worker (a terminal icon).
  final bool isFork;

  /// Whether `start` names the node.
  final bool isStart;

  /// The node's layer, 0 for the leftmost.
  final int layer;

  /// The tile.
  final Rect tile;

  /// The name, centred under the tile.
  final Rect nameRect;

  /// The command, centred under the name.
  final Rect commandRect;

  /// The `start` caption over the tile, for a `start` node.
  final Rect? startRect;

  /// The room kept for badges over the tile's top right corner: the id of a
  /// run on the node, the count of visits.
  final Rect marks;

  /// The room kept for the state badge on the tile's bottom right corner.
  final Rect status;

  /// The input bar; `null` when no arrow comes in.
  final InputBar? bar;
}

/// The bar on a tile's left side that arrows point at.
final class InputBar {
  InputBar({required this.rect, required this.inputs});

  /// The bar as drawn.
  final Rect rect;

  /// The y of each input, top to bottom.
  final List<double> inputs;
}

/// How an exit is drawn.
enum ExitShape {
  /// A dot an arrow leaves from.
  dot,

  /// A capsule, for a list target: an arrow per node.
  capsule,

  /// A short line with a cross bar, for an empty target.
  stub,
}

/// Where an exit is drawn.
final class ExitBox {
  ExitBox({
    required this.node,
    required this.index,
    required this.label,
    required this.isElse,
    required this.shape,
    required this.anchor,
    required this.handle,
    required this.stubEnd,
    required this.labelRect,
    required this.counterAt,
    required this.reach,
  });

  /// The node the exit belongs to.
  final String node;

  /// The exit's index in the node's exits, in declaration order.
  final int index;

  /// The exit's key; `null` for a worker's exit.
  final String? label;

  /// Whether this is the `else` of a fork.
  final bool isElse;

  final ExitShape shape;

  /// The middle of the dot or the capsule; where a stub starts.
  final Point anchor;

  /// The dot or the capsule; for a stub, its line.
  final Rect handle;

  /// Where a stub ends, at its cross bar; `null` for other shapes.
  final double? stubEnd;

  /// The opaque chip of the key; `null` when there is no key.
  final Rect? labelRect;

  /// The top left corner of the counter's chip: right after the key, or in
  /// its place.
  final Point counterAt;

  /// How far right of the anchor the key with the counter's room ends.
  final double reach;

  bool get isEmpty => shape == ExitShape.stub;
}

/// Where an arrow is drawn.
final class EdgePath {
  EdgePath({
    required this.from,
    required this.exitIndex,
    required this.listIndex,
    required this.to,
    required this.kind,
    required this.points,
    required this.tip,
    required this.pieces,
  });

  /// The node the arrow leaves.
  final String from;

  /// The index of the exit it leaves by, in the node's exits.
  final int exitIndex;

  /// The arrow's index in the exit's target list; 0 for a single target.
  final int listIndex;

  /// The node the arrow enters.
  final String to;

  final EdgeKind kind;

  /// The polyline: the exit, the corners, the arrowhead's base. Pieces are
  /// horizontal, vertical or at 45°.
  final List<Point> points;

  /// The arrowhead's tip, a gap before the input bar.
  final Point tip;

  /// The path to draw from [points].first: lines and rounded corners.
  final List<PathPiece> pieces;

  /// A back arrow is drawn dashed.
  bool get isDashed => kind == EdgeKind.back;
}

/// Lays out [graph]: steps 1 to 8 of `docs/graph-layout.md`.
///
/// The same graph always gets the same layout.
GraphLayout layoutGraph(
  Graph graph, {
  LayoutOptions options = const LayoutOptions(),
}) {
  final g = LayoutGraph.of(graph);
  findBackEdges(g);
  assignLayers(g);
  final layers = buildLayers(g);
  orderLayers(g, layers, options);
  final below = <GNode>{};
  var layout = _build(g, layers, options, below);
  // A loop goes under its tile when over it it would cross other arrows.
  for (final node in g.nodes) {
    final loops = [
      for (final exit in node.exits)
        for (final edge in exit.edges)
          if (edge.kind == EdgeKind.loop) edge,
    ];
    if (loops.isEmpty) continue;
    final over = _loopCrossings(layout, node.name);
    if (over == 0) continue;
    below.add(node);
    final under = _build(g, layers, options, below);
    if (_loopCrossings(under, node.name) < over) {
      layout = under;
    } else {
      below.remove(node);
    }
  }
  return _untangle(g, layers, options, below, layout);
}

/// The most rounds of [_untangle].
const int _untangleRounds = 4;

/// Arrows nested in each other's heights cross whatever the lanes' order:
/// tries swapping neighbours in every layer and keeps each swap that leaves
/// fewer crossings (step 7).
GraphLayout _untangle(
  LayoutGraph g,
  List<List<Item>> layers,
  LayoutOptions options,
  Set<GNode> below,
  GraphLayout layout,
) {
  var best = layout;
  var fewest = countCrossings(best);
  for (var round = 0; round < _untangleRounds && fewest > 0; round++) {
    var improved = false;
    for (final layer in layers) {
      for (var i = 0; i + 1 < layer.length; i++) {
        _swap(layer, i);
        final candidate = _build(g, layers, options, below);
        final count = countCrossings(candidate);
        if (count < fewest) {
          fewest = count;
          best = candidate;
          improved = true;
        } else {
          _swap(layer, i);
        }
      }
    }
    if (!improved) break;
  }
  return best;
}

/// Steps 5 to 8 for the current order of [layers]: ports, heights, lanes
/// and the layers' x, arrows.
GraphLayout _build(
  LayoutGraph g,
  List<List<Item>> layers,
  LayoutOptions options,
  Set<GNode> below,
) {
  final levels = <GEdge, int>{};
  final ports = assignPorts(g, options, below: below, backLevels: levels);
  placeLayers(g, layers, ports, options);
  straightenPasses(g, layers, ports, options);
  final frames = {
    for (final node in g.nodes)
      node: frameOf(node, ports[node]!, node.item.y, options),
  };
  var bottom = double.negativeInfinity;
  for (final layer in layers) {
    for (final item in layer) {
      final down = item.y + extentOf(item, ports, options).down;
      if (down > bottom) bottom = down;
    }
  }
  final depth = {
    for (final MapEntry(key: edge, value: level) in levels.entries)
      edge: bottom + options.backLaneOffset + (level - 1) * options.backLaneGap,
  };
  final lanes = assignLanes(layers, ports, frames, depth, options);
  return route(g, ports, frames, lanes, depth, options);
}

void _swap(List<Item> layer, int i) {
  final item = layer[i];
  layer[i] = layer[i + 1];
  layer[i + 1] = item;
  layer[i].order = i;
  layer[i + 1].order = i + 1;
}

/// How many times the loops of [node] cross other arrows.
int _loopCrossings(GraphLayout layout, String node) {
  var count = 0;
  for (final loop in layout.edges) {
    if (loop.kind != EdgeKind.loop || loop.from != node) continue;
    for (final other in layout.edges) {
      if (identical(other, loop)) continue;
      count += crossingsBetween(loop.points, other.points);
    }
  }
  return count;
}
