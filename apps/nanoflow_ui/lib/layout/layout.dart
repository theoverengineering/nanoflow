/// The layout of a graph for the canvas: where nodes, exits and arrows are.
///
/// Pure Dart: nothing here imports Flutter, so the layout's tests run on the
/// Dart VM. The algorithm is `docs/graph-layout.md`; the rules it serves are
/// `docs/ui-spec.md` «Граф».
library;

import 'dart:math' as math;

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
export 'geometry.dart';
export 'graph_layout.dart';
export 'layout_graph.dart'
    show
        EdgeKind,
        LabelKind,
        LayoutOptions,
        MeasureText,
        NodeKind,
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
/// The calls of [expanded], by id, are drawn in place (decision 6): each is
/// a frame round the layout of the body it is given, a node of [body]'s
/// layout as big as the frame (`NodeBox.frame`). A body in a frame has one
/// end, after everything else; the nodes it expands are frames in it, and
/// so on. Other ids of [expanded] are left out.
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
/// standing so, in its frames too, unless that is worse than before
/// ([_worse]). A body in a frame that changed changes the frame — its
/// size, where its exit is —: the level round it is laid out again round
/// the new frames, in the order chosen round the old ones, and kept only
/// if it is no worse than the level as before; else the level stays as
/// before, the frames in it too.
///
/// How a level comes to its heights, after the order of its nodes:
/// 1. [_finish] lays it out with every node level with the arrow from the
///    longest path, and with early turns where a layer is wider than a node.
/// 2. It lays it out again with nodes where most arrows come in level,
///    counted by `placeLayers` before the arrows are straightened and
///    routed, and with arrows taking their input's height early
///    (`straightenPasses`); kept if not [_worse].
/// 3. [_snap] moves a body's end to the arrows arriving at it, read from
///    the routed layout ([_snapShifts]); kept if not [_worse], up to twice.
/// 4. Here, a level whose frames changed is weighed against the level as
///    before, round the frames as they were.
/// A level so takes at most one build for its order's best, one for its
/// early turns, one for its heights and two for its end — besides its
/// loops' and back arrows' tries, [_untangle] and the forks' moves of
/// [_untangleSides] —, and five more round changed frames.
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
    if (node.kind != NodeKind.call) continue;
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
    return (base: base, chosen: before.improved ?? base);
  }
  // The frames that changed are laid out in the order chosen round them as
  // they were: the level keeps its order, and only what their new sizes
  // and exits move moves.
  final again = graph();
  frame(again, (id) => inners[id]!.chosen);
  final after = _laid(again, options, order: before.order);
  final was = _counts(base);
  for (final layout in [?after.improved, after.kept]) {
    if (!_worse(_counts(layout), was)) return (base: base, chosen: layout);
  }
  levelInputFallbacks++;
  return (base: base, chosen: base);
}

/// What [_worse] weighs of a layout: its own problems and crossings, its
/// arrows' turns, those of the bodies in its frames too, and its height.
typedef _Counts = ({
  int broken,
  int crossings,
  ({int turns, int twice, int thrice}) own,
  ({int turns, int twice}) deep,
  double height,
  double tile,
});

/// [_Counts] of [layout].
_Counts _counts(GraphLayout layout) => (
  broken: checkLevel(layout).length,
  crossings: countCrossings(layout),
  own: _turns(layout),
  deep: _deepTurns(layout),
  height: layout.bounds.height,
  tile: layout.options.tile,
);

/// Whether a layout with nodes standing where most of their arrows come in
/// level, counted [now], is worse than the layout it would replace, counted
/// [was]: it crosses more, breaks a rule of step 9 more often, has more
/// turns, more arrows turning twice or more arrows turning three times or
/// more — a staircase —, or is taller by more than what it saves pays for
/// ([_paidFor]).
bool _worse(_Counts now, _Counts was) =>
    now.broken > was.broken ||
    now.crossings > was.crossings ||
    now.own.turns > was.own.turns ||
    now.own.twice > was.own.twice ||
    now.own.thrice > was.own.thrice ||
    !_paidFor(now, was);

/// Whether a layout counted [now] is no taller than the one counted [was]
/// by more than half a tile for each turn it saves, an arrow it saves
/// turning twice counted as two more: over the level and the bodies in its
/// frames, since a level round a frame whose body changed grows for what
/// that body saves. A node far down to stand level with an exit saves a
/// turn or two for a level much taller; docs/graph-layout.md §6 has the
/// cases that set half a tile.
bool _paidFor(_Counts now, _Counts was) {
  final grows = now.height - was.height;
  if (grows <= 1e-6) return true;
  final saved =
      was.deep.turns - now.deep.turns + 2 * (was.deep.twice - now.deep.twice);
  return grows <= now.tile / 2 * saved + 1e-6;
}

/// [_turns] of [layout] and of the bodies in its frames.
({int turns, int twice}) _deepTurns(GraphLayout layout) {
  var (:turns, :twice, thrice: _) = _turns(layout);
  for (final node in layout.nodes.values) {
    final inner = node.frame?.inner;
    if (inner == null) continue;
    final deep = _deepTurns(inner);
    turns += deep.turns;
    twice += deep.twice;
  }
  return (turns: turns, twice: twice);
}

/// Steps 1 to 8 for [g], its frames made: the layout as before nodes stood
/// where most of their arrows come in level, and with them standing so —
/// `null` when that places nothing otherwise or is worse ([_finish]) —,
/// and the order of the layers, the nodes whose loops go under them and the
/// back arrows over the graph. With [order], that of another layout of the
/// same body, the layers keep it, and the loops and back arrows their
/// sides.
({GraphLayout kept, GraphLayout? improved, _Order order}) _laid(
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
    for (final edge in g.edges) {
      edge.over = order.over.contains(edge.index);
    }
    for (final (i, layer) in layers.indexed) {
      final rank = {for (final (k, key) in order.layers[i].indexed) key: k};
      layer.sort((a, b) => rank[_key(a)]!.compareTo(rank[_key(b)]!));
      for (final (k, item) in layer.indexed) {
        item.order = k;
      }
    }
    final layout = _build(g, layers, options, below, turnEarly: false);
    final (:kept, :improved) = _finish(g, layers, options, below, (
      layout: layout,
      broken: checkLevel(layout).length,
      crossings: countCrossings(layout),
    ));
    return (kept: kept, improved: improved, order: order);
  }
  // Every back arrow runs under the graph until its side is chosen.
  for (final edge in g.edges) {
    edge.over = false;
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
  // A back arrow runs over the graph where that crosses less.
  layout = _overSides(g, layers, options, below, layout).layout;
  final (:kept, :improved) = _finish(
    g,
    layers,
    options,
    below,
    _untangleSides(g, layers, options, below, layout),
  );
  return (
    kept: kept,
    improved: improved,
    order: (
      layers: [
        for (final layer in layers) [for (final item in layer) _key(item)],
      ],
      below: {for (final node in below) node.id},
      over: {
        for (final edge in g.edges)
          if (edge.over) edge.index,
      },
    ),
  );
}

/// Takes back arrows under the graph over it one by one, in the body's
/// order, where that crosses less in [layout], the layout of [layers] as
/// they are, breaking no rule of step 9 more often. Returns the layout with
/// the sides taken.
({GraphLayout layout, int broken, int crossings}) _overSides(
  LayoutGraph g,
  List<List<Item>> layers,
  LayoutOptions options,
  Set<GNode> below,
  GraphLayout layout,
) {
  var crossings = countCrossings(layout);
  var broken = checkLevel(layout).length;
  for (final edge in g.edges) {
    if (edge.kind != EdgeKind.back || edge.over) continue;
    edge.over = true;
    final over = _build(g, layers, options, below, turnEarly: false);
    final count = countCrossings(over);
    final problems = checkLevel(over).length;
    if (count < crossings && problems <= broken) {
      layout = over;
      crossings = count;
      broken = problems;
    } else {
      edge.over = false;
    }
  }
  return (layout: layout, broken: broken, crossings: crossings);
}

/// [_untangle] of [layout], whose back arrows have their sides; then, for
/// each fork whose way of `true` goes down past its way of `false`, the
/// node `true` goes to moved up over the node `false` goes to and more
/// back arrows taken over the graph ([_overSides]) — kept if that breaks
/// fewer rules of step 9, or as many and crosses less.
///
/// The medians pick the order as if every back arrow ran under the graph:
/// the node `true` goes to sinks for its way back — `if (…) continue` in a
/// loop —, and its way down crosses `false`. Up over it, its way back pays
/// off over the graph.
({GraphLayout layout, int broken, int crossings}) _untangleSides(
  LayoutGraph g,
  List<List<Item>> layers,
  LayoutOptions options,
  Set<GNode> below,
  GraphLayout layout,
) {
  var best = _untangle(g, layers, options, below, layout);
  for (final node in g.nodes) {
    final (:yes, :no) = node.fork ?? (yes: null, no: null);
    if (yes == null || no == null) continue;
    final down = middleArrow(yes);
    final on = middleArrow(no);
    if (down.kind != EdgeKind.forward || on.kind != EdgeKind.forward) continue;
    final paths = best.layout.edges;
    if (crossingsBetween(paths[down.index].points, paths[on.index].points) ==
        0) {
      continue;
    }
    final upper = on.segs.first.to;
    final lower = down.segs.first.to;
    if (upper.layer != lower.layer || lower.order < upper.order) continue;
    final layer = layers[lower.layer];
    final order = [...layer];
    final sides = {for (final edge in g.edges) edge: edge.over};
    void place(List<Item> items) {
      layer
        ..clear()
        ..addAll(items);
      for (final (k, item) in layer.indexed) {
        item.order = k;
      }
    }

    place(
      [...order]
        ..remove(lower)
        ..insert(upper.order, lower),
    );
    final moved = _overSides(
      g,
      layers,
      options,
      below,
      _build(g, layers, options, below, turnEarly: false),
    );
    if (moved.broken < best.broken ||
        moved.broken == best.broken && moved.crossings < best.crossings) {
      best = moved;
    } else {
      place(order);
      for (final MapEntry(key: edge, value: over) in sides.entries) {
        edge.over = over;
      }
    }
  }
  return best;
}

/// The order of a layout's layers, by [_key], the nodes whose loops go
/// under their tiles, by id, and the back arrows that run over the graph,
/// by index.
typedef _Order = ({
  List<List<Object>> layers,
  Set<String> below,
  Set<int> over,
});

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
/// places anything otherwise, and kept unless it is worse than the layout
/// it would replace ([_worse]).
///
/// The early turns should never cross more: a turn goes before turns ahead
/// of it in its gap only past turns whose order with it does not change
/// what crosses. The heights may — an arrow level with another input
/// passes its neighbours elsewhere —, and then the order keeps the heights
/// it was chosen with. The order of the nodes is chosen without either, so
/// that they do not steer it: arrows shorter by them would make [_untangle]
/// keep other swaps of as many crossings.
({GraphLayout kept, GraphLayout? improved}) _finish(
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
  if (!levelInputsEnabled) return (kept: kept, improved: null);
  final level = _levelled(
    g,
    layers,
    options,
    below,
    turnEarly: !identical(kept, best.layout),
  );
  var chosen = kept;
  if (level != null) {
    if (_worse(_counts(level), _counts(kept))) {
      levelInputFallbacks++;
    } else {
      chosen = level;
    }
  }
  final snapped = _snap(
    g,
    layers,
    options,
    below,
    chosen,
    turnEarly: !identical(kept, best.layout),
    levelInputs: !identical(chosen, kept),
  );
  return (kept: kept, improved: identical(snapped, kept) ? null : snapped);
}

/// The most rounds of [_snap]: an end moved, the arrows into it may run
/// along other heights.
const int _snapRounds = 2;

/// [layout] with the end of the body snapped to the arrows arriving at it
/// ([_snapShifts]), laid out again as [layout] was otherwise — unless that
/// is worse than [layout] ([_worse]); again for what then arrives, up to
/// [_snapRounds] times.
///
/// The end's height is chosen where its arrows are placed in the layers
/// before it, before they are straightened and routed: an arrow that has
/// to climb past a node in the middle of the body, and so does not count
/// as level there, runs along a band over the last nodes after all, the
/// arrows next to it a lane gap apart, as the inputs are on the bar. Read
/// from where they run, the end can stand level with all of them.
GraphLayout _snap(
  LayoutGraph g,
  List<List<Item>> layers,
  LayoutOptions options,
  Set<GNode> below,
  GraphLayout layout, {
  required bool turnEarly,
  required bool levelInputs,
}) {
  var current = layout;
  var counts = _counts(layout);
  var shifts = <GNode, double>{};
  for (var round = 0; round < _snapRounds; round++) {
    final more = _snapShifts(g, current);
    if (more.isEmpty) break;
    final all = {...shifts};
    for (final MapEntry(key: node, value: shift) in more.entries) {
      all[node] = (all[node] ?? 0) + shift;
    }
    final snapped = _buildWith(
      g,
      layers,
      options,
      below,
      turnEarly: turnEarly,
      levelInputs: levelInputs,
      shifts: all,
    )!;
    final now = _counts(snapped);
    if (_worse(now, counts)) {
      endSnapFallbacks++;
      break;
    }
    current = snapped;
    counts = now;
    shifts = all;
  }
  return current;
}

/// How far each end of [g] with several arrows in should move to take the
/// most of them in level, by [layout]: each arrow whose last turn is in the
/// gap just before the end would come in level if the end stood its last
/// run's height off; the others are level already. The height most arrows
/// would come in level at wins, on a tie the smallest move; none when that
/// is no move.
Map<GNode, double> _snapShifts(LayoutGraph g, GraphLayout layout) {
  final shifts = <GNode, double>{};
  for (final node in g.nodes) {
    if (node.kind != NodeKind.end || node.inEdges.length < 2) continue;
    final end = layout.nodes[node.id]!;
    final gap = layout.nodes.values
        .where((other) => other.layer < end.layer)
        .map((other) => other.tile.right)
        .fold(double.negativeInfinity, math.max);
    final counts = <int, int>{};
    for (final edge in layout.edges) {
      if (edge.to != node.id || edge.kind != EdgeKind.forward) continue;
      final points = edge.points;
      final input = points.last.y;
      // The last turn: back past the straight piece into the input, then
      // over every piece that changes height.
      var i = points.length - 1;
      while (i > 0 && (points[i].y - points[i - 1].y).abs() < 1e-6) {
        i--;
      }
      while (i > 0 && (points[i].y - points[i - 1].y).abs() >= 1e-6) {
        i--;
      }
      final turnsInGap = i < points.length - 1 && points[i].x >= gap - 1e-6;
      final run = turnsInGap ? points[i].y : input;
      final key = ((run - input) * 1000).round();
      counts[key] = (counts[key] ?? 0) + 1;
    }
    int? best;
    for (final MapEntry(key: key, value: count) in counts.entries) {
      if (best == null ||
          count > counts[best]! ||
          count == counts[best]! && key.abs() < best.abs()) {
        best = key;
      }
    }
    if (best != null && best != 0) shifts[node] = best / 1000;
  }
  return shifts;
}

/// How many times [_snap] kept a body's end where it was because snapping
/// it to its arrows was worse ([_worse]).
@visibleForTesting
int endSnapFallbacks = 0;

/// How many times arrows of [layout] going forward change height, how many
/// of them change height twice or more, and how many three times or more.
({int turns, int twice, int thrice}) _turns(GraphLayout layout) {
  var turns = 0;
  var twice = 0;
  var thrice = 0;
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
    if (count > 2) thrice++;
  }
  return (turns: turns, twice: twice, thrice: thrice);
}

/// Whether nodes stand where most of their arrows come in level (step 6);
/// tests turn it off to lay a body out as before.
@visibleForTesting
bool levelInputsEnabled = true;

/// How many times a level kept the heights its order was chosen with
/// ([_finish]), or stayed as before round frames whose bodies changed
/// ([_layout]), because nodes standing where most arrows come in level
/// made it worse ([_worse]). No level of the test graphs does, and few
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
  onlyIfLevelled: true,
);

/// [_build] with [levelInputs] and [shifts] as for `placeLayers`, and
/// with those arrows taking their input's height early
/// (`straightenPasses`); `null` when [onlyIfLevelled] and neither places
/// anything otherwise. Only the layouts [_worse] weighs take the heights
/// early: the order and the loops' sides are chosen without them.
GraphLayout? _buildWith(
  LayoutGraph g,
  List<List<Item>> layers,
  LayoutOptions options,
  Set<GNode> below, {
  required bool turnEarly,
  bool levelInputs = false,
  bool onlyIfLevelled = false,
  Map<GNode, double> shifts = const {},
}) {
  final levels = <GEdge, int>{};
  final ports = assignPorts(g, options, below: below, backLevels: levels);
  final levelled = placeLayers(
    g,
    layers,
    ports,
    options,
    levelInputs: levelInputs,
    shifts: shifts,
  );
  final early = levelInputs || shifts.isNotEmpty;
  final straightened = straightenPasses(
    g,
    layers,
    ports,
    options,
    early: early,
  );
  if (onlyIfLevelled && !levelled && !straightened) return null;
  final frames = {
    for (final node in g.nodes)
      node: frameOf(node, ports[node]!, node.item.y, options),
  };
  final depth = _backLanes(g, layers, ports, levels, options);
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

/// The y of every back arrow's lane, under the graph or over it
/// ([GEdge.over]): a lane offset off what the arrow passes, and a lane gap
/// off the lane of every arrow on its side nested in it — whose turns share
/// a gap with its own and whose level of [levels] is lower.
///
/// An arrow passes the items of the layers from its input's to its exit's,
/// and in the gaps it turns in, before its input's layer and after its
/// exit's, the ends of whatever else turns there — forward arrows, loops,
/// back arrows on the other side —: its lane past them would cross them
/// there. Lanes on its side keep off it by nesting. So the way back of a
/// loop after a tall frame runs under the loop, not under the frame.
Map<GEdge, double> _backLanes(
  LayoutGraph g,
  List<List<Item>> layers,
  Map<GNode, Ports> ports,
  Map<GEdge, int> levels,
  LayoutOptions options,
) {
  final tops = <double>[];
  final bottoms = <double>[];
  for (final layer in layers) {
    var top = double.infinity;
    var bottom = double.negativeInfinity;
    for (final item in layer) {
      final (:up, :down) = extentOf(item, ports, options);
      top = math.min(top, item.y - up);
      bottom = math.max(bottom, item.y + down);
    }
    tops.add(top);
    bottoms.add(bottom);
  }
  // The lowest and highest ends of what turns in each gap — gap i lies
  // between layers i and i + 1 —, for lanes under the graph and over it.
  final lowest = <int, double>{};
  final highest = <int, double>{};
  void turns(int gap, double y, {GEdge? back}) {
    if (back == null || back.over) {
      lowest[gap] = math.max(lowest[gap] ?? y, y);
    }
    if (back == null || !back.over) {
      highest[gap] = math.min(highest[gap] ?? y, y);
    }
  }

  for (final (i, layer) in layers.indexed) {
    for (final item in layer) {
      for (final seg in item.outs) {
        turns(i, outY(seg, ports));
        turns(i, inY(seg, ports));
      }
    }
  }
  for (final node in g.nodes) {
    final port = ports[node]!;
    final y = node.item.y;
    for (final exit in node.exits) {
      for (final edge in exit.edges) {
        if (edge.kind == EdgeKind.back) {
          turns(node.layer, y + port.exitAt[edge]!, back: edge);
        }
      }
    }
    for (final edge in node.inEdges) {
      if (edge.kind == EdgeKind.back) {
        turns(node.layer - 1, y + port.inputAt[edge]!, back: edge);
      }
    }
    for (final (below, loops) in [
      (false, port.loopsAbove),
      (true, port.loopsBelow),
    ]) {
      for (final (index, loop) in loops.indexed) {
        final far =
            y + loopOffset(node, port, options, below: below, index: index);
        for (final (gap, at) in [
          (node.layer, port.exitAt[loop]!),
          (node.layer - 1, port.inputAt[loop]!),
        ]) {
          turns(gap, y + at);
          turns(gap, far);
        }
      }
    }
  }

  final lanes = <GEdge, double>{};
  for (final edge
      in levels.keys.toList()
        ..sort((a, b) => levels[a]!.compareTo(levels[b]!))) {
    final left = edge.to.layer;
    final right = edge.from.layer;
    final gaps = [left - 1, right];
    double lane;
    if (edge.over) {
      var top = tops.sublist(left, right + 1).reduce(math.min);
      for (final gap in gaps) {
        top = math.min(top, highest[gap] ?? top);
      }
      lane = top - options.backLaneOffset;
    } else {
      var bottom = bottoms.sublist(left, right + 1).reduce(math.max);
      for (final gap in gaps) {
        bottom = math.max(bottom, lowest[gap] ?? bottom);
      }
      lane = bottom + options.backLaneOffset;
    }
    for (final MapEntry(key: other, value: y) in lanes.entries) {
      final nested =
          other.over == edge.over &&
          other.to.layer - 1 <= edge.from.layer &&
          edge.to.layer - 1 <= other.from.layer;
      if (!nested) continue;
      lane = edge.over
          ? math.min(lane, y - options.backLaneGap)
          : math.max(lane, y + options.backLaneGap);
    }
    lanes[edge] = lane;
  }
  return lanes;
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
