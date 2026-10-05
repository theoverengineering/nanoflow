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
}) => _layout(body, functions, options, expanded, inFrame: false).chosen;

/// [body] laid out as before nodes stood where most of their arrows come
/// in level — the bodies in its frames too —, and as chosen: with them
/// standing so, in its frames too, unless that crosses more, breaks a rule
/// of step 9 more often, or has more turns or more arrows turning twice
/// than before. A body in a frame that changed changes the frame — its
/// size, where its exit is —: the level round it is laid out again round
/// the new frames, in the order chosen round the old ones, and kept only
/// if it is no worse by those counts than the level as before; else the
/// level stays as before, the frames in it too.
///
/// [endBarHalf] is the least half length of the bar of the end of a body
/// in a frame ([GNode.leastBarHalf]).
({GraphLayout base, GraphLayout chosen}) _layout(
  GraphBody body,
  Map<String, GraphFunction> functions,
  LayoutOptions options,
  Map<String, ExpandedNode> expanded, {
  required bool inFrame,
  double endBarHalf = 0,
}) {
  LayoutGraph graph() {
    final g = LayoutGraph.ofBody(body, functions: functions, inFrame: inFrame);
    for (final node in g.nodes) {
      if (node.port && node.kind == NodeKind.end) {
        node.leastBarHalf = endBarHalf;
      }
    }
    return g;
  }

  final g = graph();
  final inners = <String, ({GraphLayout base, GraphLayout chosen})>{};
  for (final node in g.nodes) {
    if (node.kind != NodeKind.call && node.kind != NodeKind.copies) continue;
    final open = expanded[node.id];
    if (open == null) continue;
    inners[node.id] = _layout(
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
  }
  void frame(LayoutGraph g, GraphLayout Function(String id) inner) {
    for (final node in g.nodes) {
      if (!inners.containsKey(node.id)) continue;
      node.framed = FramedBody.of(
        node,
        inner(node.id),
        expanded[node.id]!.room,
        options,
      );
    }
  }

  frame(g, (id) => inners[id]!.base);
  final before = _laid(g, options);
  final base = before.kept;
  if (inners.values.every((inner) => identical(inner.base, inner.chosen))) {
    return (base: base, chosen: before.levelled ?? base);
  }
  // The frames that changed are laid out in the order chosen round them as
  // they were: the level keeps its order, and only what their new sizes
  // and exits move moves.
  final again = graph();
  frame(again, (id) => inners[id]!.chosen);
  final after = _laid(again, options, order: before.order);
  final was = (
    broken: checkLevel(base).length,
    crossings: countCrossings(base),
    turns: _turns(base),
  );
  for (final layout in [?after.levelled, after.kept]) {
    final (:turns, :twice) = _turns(layout);
    if (checkLevel(layout).length <= was.broken &&
        countCrossings(layout) <= was.crossings &&
        turns <= was.turns.turns &&
        twice <= was.turns.twice) {
      return (base: base, chosen: layout);
    }
  }
  levelInputFallbacks++;
  return (base: base, chosen: base);
}

/// Steps 1 to 8 for [g], its frames made: the layout as before nodes stood
/// where most of their arrows come in level, and with them standing so —
/// `null` when that places nothing otherwise or is worse ([_finish]) —,
/// and the order of the layers and the nodes whose loops go under them.
/// With [order], that of another layout of the same body, the layers keep
/// it, and the loops their sides.
({GraphLayout kept, GraphLayout? levelled, _Order order}) _laid(
  LayoutGraph g,
  LayoutOptions options, {
  _Order? order,
}) {
  findBackEdges(g);
  assignLayers(g);
  final layers = buildLayers(g);
  if (order != null) {
    final below = {
      for (final node in g.nodes)
        if (order.below.contains(node.id)) node,
    };
    for (final (i, layer) in layers.indexed) {
      final rank = {for (final (k, key) in order.layers[i].indexed) key: k};
      layer.sort((a, b) => rank[_key(a)]!.compareTo(rank[_key(b)]!));
      for (final (k, item) in layer.indexed) {
        item.order = k;
      }
    }
    final layout = _build(g, layers, options, below, turnEarly: false);
    final (:kept, :levelled) = _finish(g, layers, options, below, (
      layout: layout,
      broken: checkLevel(layout).length,
      crossings: countCrossings(layout),
    ));
    return (kept: kept, levelled: levelled, order: order);
  }
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
  final (:kept, :levelled) = _finish(
    g,
    layers,
    options,
    below,
    _untangle(g, layers, options, below, layout),
  );
  return (
    kept: kept,
    levelled: levelled,
    order: (
      layers: [
        for (final layer in layers) [for (final item in layer) _key(item)],
      ],
      below: {for (final node in below) node.id},
    ),
  );
}

/// The order of a layout's layers, by [_key], and the nodes whose loops go
/// under their tiles, by id.
typedef _Order = ({List<List<Object>> layers, Set<String> below});

/// What names [item] in every layout of its body: its node's id, or its
/// arrow's index — a string never equal to an int.
Object _key(Item item) => item.node?.id ?? item.edge!.index;

/// The best layout [_untangle] found, laid out for the order [layers] have
/// with every turn past its layer's right side and every node level with
/// the arrow from the longest path into it, laid out again with the arrows
/// out of nodes narrower than their layer turning next to them (step 7) —
/// unless that crosses more or breaks a rule of step 9 more often; on a
/// tie, the turns next to the nodes. Without a node narrower than its
/// layer nothing turns early. That layout is laid out once more with nodes
/// standing where most of their arrows come in level (step 6), if that
/// places anything otherwise, and kept unless it crosses more, breaks a
/// rule of step 9 more often, or has more turns or more arrows turning
/// twice than the layout it would replace.
///
/// The early turns should never cross more: a turn goes before turns ahead
/// of it in its gap only past turns whose order with it does not change
/// what crosses. The heights may — an arrow level with another input
/// passes its neighbours elsewhere —, and then the order keeps the heights
/// it was chosen with. The order of the nodes is chosen without either, so
/// that they do not steer it: arrows shorter by them would make [_untangle]
/// keep other swaps of as many crossings.
({GraphLayout kept, GraphLayout? levelled}) _finish(
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
  var kept = best.layout;
  if (narrower) {
    final early = _build(g, layers, options, below, turnEarly: true);
    if (worse(early)) {
      earlyTurnFallbacks++;
    } else {
      kept = early;
    }
  }
  final level = _levelled(
    g,
    layers,
    options,
    below,
    turnEarly: !identical(kept, best.layout),
  );
  if (level == null) return (kept: kept, levelled: null);
  final (:turns, :twice) = _turns(level);
  final before = _turns(kept);
  if (worse(level) || turns > before.turns || twice > before.twice) {
    levelInputFallbacks++;
    return (kept: kept, levelled: null);
  }
  return (kept: kept, levelled: level);
}

/// How many times arrows of [layout] going forward change height, and how
/// many of them change height twice or more.
({int turns, int twice}) _turns(GraphLayout layout) {
  var turns = 0;
  var twice = 0;
  for (final edge in layout.edges) {
    if (edge.kind != EdgeKind.forward) continue;
    final points = edge.points;
    var count = 0;
    var turning = false;
    for (var i = 1; i < points.length; i++) {
      final flat = (points[i].y - points[i - 1].y).abs() < 1e-6;
      if (!flat && !turning) count++;
      turning = !flat;
    }
    turns += count;
    if (count > 1) twice++;
  }
  return (turns: turns, twice: twice);
}

/// How many times a level kept the heights its order was chosen with
/// ([_finish]), or stayed as before round frames whose bodies changed
/// ([_layout]), because nodes standing where most arrows come in level
/// crossed more, broke a rule of step 9 more often, or had more turns or
/// more arrows turning twice. No level of the test graphs does, and few
/// random ones: tests check both.
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
/// and the layers' x, arrows; [turnEarly] as for [assignLanes].
GraphLayout _build(
  LayoutGraph g,
  List<List<Item>> layers,
  LayoutOptions options,
  Set<GNode> below, {
  required bool turnEarly,
}) => _buildWith(g, layers, options, below, turnEarly: turnEarly)!;

/// [_build] with nodes standing where most of their arrows come in level
/// (`placeLayers`' levelInputs); `null` when that places nothing
/// otherwise.
GraphLayout? _levelled(
  LayoutGraph g,
  List<List<Item>> layers,
  LayoutOptions options,
  Set<GNode> below, {
  required bool turnEarly,
}) => _buildWith(
  g,
  layers,
  options,
  below,
  turnEarly: turnEarly,
  levelInputs: true,
);

GraphLayout? _buildWith(
  LayoutGraph g,
  List<List<Item>> layers,
  LayoutOptions options,
  Set<GNode> below, {
  required bool turnEarly,
  bool levelInputs = false,
}) {
  final levels = <GEdge, int>{};
  final ports = assignPorts(g, options, below: below, backLevels: levels);
  final levelled = placeLayers(
    g,
    layers,
    ports,
    options,
    levelInputs: levelInputs,
  );
  if (levelInputs && !levelled) return null;
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
