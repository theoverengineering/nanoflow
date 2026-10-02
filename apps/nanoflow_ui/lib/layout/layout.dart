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
import 'graph_layout.dart';
import 'lanes.dart';
import 'layers.dart';
import 'layout_graph.dart';
import 'ordering.dart';
import 'ports.dart';
import 'routing.dart';

export 'checks.dart' show checkLayout, countCrossings;
export 'geometry.dart';
export 'graph_layout.dart';
export 'layout_graph.dart'
    show
        EdgeKind,
        LabelKind,
        LayoutOptions,
        MeasureText,
        counterText,
        monospaceMeasure,
        startCaption;

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
/// fewer crossings (step 7). A swap that breaks a rule of step 9 more often
/// never wins. Of two layouts with as many crossings the one whose arrows
/// are shorter by more than a lane gap wins: its arrows run alongside each
/// other instead of going round (ui-spec «Граф»: «при равенстве — где больше
/// стрелок идёт параллельно»).
GraphLayout _untangle(
  LayoutGraph g,
  List<List<Item>> layers,
  LayoutOptions options,
  Set<GNode> below,
  GraphLayout layout,
) {
  var best = layout;
  var broken = checkLayout(best).length;
  var fewest = countCrossings(best);
  var shortest = _length(best);
  for (var round = 0; round < _untangleRounds; round++) {
    var improved = false;
    for (final layer in layers) {
      for (var i = 0; i + 1 < layer.length; i++) {
        _swap(layer, i);
        final candidate = _build(g, layers, options, below);
        final problems = checkLayout(candidate).length;
        final count = countCrossings(candidate);
        final length = _length(candidate);
        final better =
            problems < broken ||
            problems == broken &&
                (count < fewest ||
                    count == fewest && length < shortest - options.laneGap);
        if (better) {
          broken = problems;
          fewest = count;
          shortest = length;
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

/// The length of all arrows of [layout].
double _length(GraphLayout layout) {
  var sum = 0.0;
  for (final edge in layout.edges) {
    for (var i = 1; i < edge.points.length; i++) {
      sum += (edge.points[i] - edge.points[i - 1]).length;
    }
  }
  return sum;
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
