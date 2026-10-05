/// The layout of a graph for the canvas: where nodes, exits and arrows are.
///
/// Pure Dart: nothing here imports Flutter, so the layout's tests run on the
/// Dart VM. The algorithm is `docs/graph-layout.md`; the rules it serves are
/// `docs/ui-spec.md` «Граф».
library;

import 'package:meta/meta.dart';
import 'package:nanoflow_model/nanoflow_model.dart';

import 'checks.dart';
import 'coordinates.dart';
import 'cycles.dart';
import 'graph_layout.dart';
import 'lanes.dart';
import 'layers.dart';
import 'layout_graph.dart';
import 'nested.dart';
import 'ordering.dart';
import 'ports.dart';
import 'routing.dart';

export 'checks.dart' show checkLayout, countCrossings;
export 'coordinates.dart'
    show
        badgeHeight,
        badgeOverhang,
        overTile,
        stackInset,
        stackStep,
        tilesBehind;
export 'geometry.dart';
export 'graph_layout.dart';
export 'layout_graph.dart'
    show
        EdgeKind,
        LabelKind,
        LayoutOptions,
        MeasureText,
        NodeKind,
        copiesBadge,
        endMarker,
        endMarkerAt,
        insideText,
        monospaceMeasure,
        nameLength,
        nodeName,
        reachableEffects,
        shortName,
        startMarker;
export 'nested.dart' show ExpandedNode, FrameRoom, frameOutline, sideClearance;

/// Lays out one level of the graph, [body], from a start marker to end
/// markers (`LayoutGraph.ofBody`), its calls named after their functions in
/// [functions]: steps 1 to 8 of `docs/graph-layout.md`.
///
/// The calls and copies of [expanded], by id, are drawn in place (decision
/// 6): each is a frame round the layout of the body it is given, a node of
/// [body]'s layout as big as the frame (`NodeBox.frame`). A body in a frame
/// has one end, after everything else; the nodes it expands are frames in
/// it, and so on. Other ids of [expanded] are left out.
///
/// The same body always gets the same layout.
GraphLayout layoutBody(
  GraphBody body, {
  Map<String, GraphFunction> functions = const {},
  LayoutOptions options = const LayoutOptions(),
  Map<String, ExpandedNode> expanded = const {},
}) => _layout(body, functions, options, expanded, inFrame: false);

/// [endBarHalf] is the least half length of the bar of the end of a body
/// in a frame ([GNode.leastBarHalf]).
GraphLayout _layout(
  GraphBody body,
  Map<String, GraphFunction> functions,
  LayoutOptions options,
  Map<String, ExpandedNode> expanded, {
  required bool inFrame,
  double endBarHalf = 0,
}) {
  final g = LayoutGraph.ofBody(body, functions: functions, inFrame: inFrame);
  for (final node in g.nodes) {
    if (node.port && node.kind == NodeKind.end) node.leastBarHalf = endBarHalf;
  }
  for (final node in g.nodes) {
    if (node.kind != NodeKind.call && node.kind != NodeKind.copies) continue;
    final open = expanded[node.id];
    if (open == null) continue;
    final inner = _layout(
      open.body,
      functions,
      options,
      open.expanded,
      inFrame: true,
      // The bar of the body's end is the frame's exit: half a port gap past
      // the arrows out, as past the arrows in.
      endBarHalf: node.exits.isEmpty
          ? 0
          : arrowsReach(node, options) + options.portGap / 2,
    );
    node.framed = FramedBody.of(node, inner, open.room, options);
  }
  findBackEdges(g);
  assignLayers(g);
  final layers = buildLayers(g);
  orderLayers(g, layers, options);
  // The loops' sides and the order of the nodes are chosen with every turn
  // past its layer's right side, as if no node were narrower than its
  // layer, and each node level with the arrow from the longest path into
  // it; arrows out of narrower nodes turn next to them, and nodes stand
  // where most of their arrows come in level, only in the layout of the
  // order chosen (_finish).
  final below = <GNode>{};
  var layout = _build(g, layers, options, below, turnEarly: false);
  // A loop goes under its tile when over it it would cross other arrows.
  for (final node in g.nodes) {
    final loops = [
      for (final exit in node.exits)
        for (final edge in exit.edges)
          if (edge.kind == EdgeKind.loop) edge,
    ];
    if (loops.isEmpty) continue;
    final over = _loopCrossings(layout, node.id);
    if (over == 0) continue;
    below.add(node);
    final under = _build(g, layers, options, below, turnEarly: false);
    if (_loopCrossings(under, node.id) < over) {
      layout = under;
    } else {
      below.remove(node);
    }
  }
  return _finish(
    g,
    layers,
    options,
    below,
    _untangle(g, layers, options, below, layout),
  );
}

/// The best layout [_untangle] found, laid out for the order [layers] have
/// with every turn past its layer's right side and every node level with
/// the arrow from the longest path into it, laid out again with nodes
/// standing where most of their arrows come in level (step 6) and the
/// arrows out of nodes narrower than their layer turning next to them
/// (step 7) — unless that crosses more or breaks a rule of step 9 more
/// often. Then the turns next to the nodes alone are tried the same way;
/// failing that too, [best] stays. On a tie, the layout laid out again.
///
/// The early turns should never cross more: a turn goes before turns ahead
/// of it in its gap only past turns whose order with it does not change
/// what crosses. The heights may — an arrow level with another input
/// passes its neighbours elsewhere —, and then the order keeps the heights
/// it was chosen with. The order of the nodes is chosen without either, so
/// that they do not steer it: arrows shorter by them would make [_untangle]
/// keep other swaps of as many crossings.
GraphLayout _finish(
  LayoutGraph g,
  List<List<Item>> layers,
  LayoutOptions options,
  Set<GNode> below,
  ({GraphLayout layout, int broken, int crossings}) best,
) {
  final narrower = layers.any(
    (layer) =>
        {for (final item in layer) ?item.node?.widthOf(options)}.length > 1,
  );
  bool worse(GraphLayout layout) =>
      checkLevel(layout).length > best.broken ||
      countCrossings(layout) > best.crossings;
  final level = _build(
    g,
    layers,
    options,
    below,
    turnEarly: narrower,
    levelInputs: true,
  );
  if (!worse(level)) return level;
  levelInputFallbacks++;
  if (!narrower) return best.layout;
  final early = _build(g, layers, options, below, turnEarly: true);
  if (worse(early)) {
    earlyTurnFallbacks++;
    return best.layout;
  }
  return early;
}

/// How many times [_finish] kept every node level with the arrow from the
/// longest path into it because standing where most arrows come in level
/// crossed more or broke a rule of step 9 more often. No level of the test
/// graphs does, and only a few random ones: tests check both.
@visibleForTesting
int levelInputFallbacks = 0;

/// How many times [_finish] kept every turn past its layer's right side
/// because turning next to the nodes crossed more or broke a rule of step 9
/// more often. It should stay 0: a test checks that it does.
@visibleForTesting
int earlyTurnFallbacks = 0;

/// The most rounds of [_untangle].
const int _untangleRounds = 4;

/// Arrows nested in each other's heights cross whatever the lanes' order:
/// tries swapping neighbours in every layer and keeps each swap that leaves
/// fewer crossings (step 7). A swap that breaks a rule of step 9 more often
/// never wins. Of two layouts with as many crossings the one whose arrows
/// are shorter by more than a lane gap wins: its arrows run alongside each
/// other instead of going round (ui-spec «Граф»: «при равенстве — где больше
/// стрелок идёт параллельно»).
///
/// Returns the best layout, how many rules of step 9 it breaks itself, not
/// counting the bodies in its frames, and how many times its arrows
/// cross.
({GraphLayout layout, int broken, int crossings}) _untangle(
  LayoutGraph g,
  List<List<Item>> layers,
  LayoutOptions options,
  Set<GNode> below,
  GraphLayout layout,
) {
  // The bodies in frames break the same rules whatever the order: only the
  // level's own problems are compared.
  var best = layout;
  var broken = checkLevel(best).length;
  var fewest = countCrossings(best);
  var shortest = _length(best);
  for (var round = 0; round < _untangleRounds; round++) {
    var improved = false;
    for (final layer in layers) {
      for (var i = 0; i + 1 < layer.length; i++) {
        _swap(layer, i);
        final candidate = _build(g, layers, options, below, turnEarly: false);
        final problems = checkLevel(candidate).length;
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
  return (layout: best, broken: broken, crossings: fewest);
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
/// and the layers' x, arrows; [turnEarly] as for [assignLanes],
/// [levelInputs] as for [placeLayers].
GraphLayout _build(
  LayoutGraph g,
  List<List<Item>> layers,
  LayoutOptions options,
  Set<GNode> below, {
  required bool turnEarly,
  bool levelInputs = false,
}) {
  final levels = <GEdge, int>{};
  final ports = assignPorts(g, options, below: below, backLevels: levels);
  placeLayers(g, layers, ports, options, levelInputs: levelInputs);
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
  final lanes = assignLanes(
    layers,
    ports,
    frames,
    depth,
    options,
    turnEarly: turnEarly,
  );
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
