import 'dart:math' as math;

import 'geometry.dart';
import 'layout_graph.dart';
import 'ports.dart';

/// Where the name sits under a tile: its top below the tile's bottom.
const double nameTop = 8;

/// The height of the name's line.
const double nameHeight = 15;

/// Where the place sits under a tile: its top below the tile's bottom.
const double placeTop = nameTop + nameHeight + 2;

/// The height of the place's line.
const double placeHeight = 13;

/// How far each tile stacked behind copies shows over the tile, and how far
/// in from its sides it is.
const double stackStep = 7;
const double stackInset = 8;

/// How many tiles are stacked behind the tile of [kind]: two behind copies,
/// for the copies run; none behind a call, one tile with `ƒ` on it.
int tilesBehind(NodeKind kind) => switch (kind) {
  NodeKind.copies => 2,
  _ => 0,
};

/// How far a loop runs from what it goes around: the marks over the tile, or
/// the place under it.
const double loopClear = 8;

/// The badge across the top of the stack of copies: its height, and how far
/// past the tile's right side it reaches.
const double badgeHeight = 14;
const double badgeOverhang = 6;

/// How far over the tile of [kind] what is drawn over it reaches: the tiles
/// stacked behind copies and the badge across the top of their stack.
double overTile(NodeKind kind) {
  final stack = stackStep * tilesBehind(kind);
  return kind == NodeKind.copies ? stack + badgeHeight / 2 : stack;
}

/// The room the marks over a tile take: badges in its top right corner, the
/// tiles stacked behind copies; over a frame, what is drawn over it. None
/// over a port.
double marksAbove(GNode node) => node.port
    ? 0
    : math.max(12, (node.framed?.room.above ?? overTile(node.kind)) + 4);

/// The room under a tile: its name and place; a marker's state badge.
/// Nothing is under a frame — its title is in it — or a port.
double textsBelow(GNode node) => node.framed != null || node.port
    ? 0
    : node.isMarker
    ? 12
    : placeTop + placeHeight;

/// How far a loop's far side is from the middle of its tile: [index] counts
/// from the innermost loop on that side.
double loopOffset(
  GNode node,
  Ports ports,
  LayoutOptions options, {
  required bool below,
  required int index,
}) {
  final reach = loopClear + index * options.laneGap;
  return below
      ? ports.height / 2 + textsBelow(node) + reach
      : -(ports.height / 2 + marksAbove(node) + reach);
}

/// The room an item takes over and under its y.
({double up, double down}) extentOf(
  Item item,
  Map<GNode, Ports> ports,
  LayoutOptions options,
) {
  final node = item.node;
  if (node == null) return (up: 0, down: 0);
  final port = ports[node]!;
  final above = port.loopsAbove.length;
  final below = port.loopsBelow.length;
  return (
    up: above == 0
        ? port.height / 2 + marksAbove(node)
        : -loopOffset(node, port, options, below: false, index: above - 1),
    down: below == 0
        ? port.height / 2 + textsBelow(node)
        : loopOffset(node, port, options, below: true, index: below - 1),
  );
}

/// The least distance between the y of [a] and the y of [b] right under it.
double minDistance(
  Item a,
  Item b,
  Map<GNode, Ports> ports,
  LayoutOptions options,
) {
  final gap = a.isPass && b.isPass
      ? options.laneGap
      : a.isPass || b.isPass
      ? options.passGap
      : options.nodeGap;
  return extentOf(a, ports, options).down +
      gap +
      extentOf(b, ports, options).up;
}

/// Packs every layer from y = 0 down, items as close as they may be.
///
/// The order of step 4 uses it to estimate where ports are.
void stackLayers(
  List<List<Item>> layers,
  Map<GNode, Ports> ports,
  LayoutOptions options,
) {
  for (final layer in layers) {
    var y = 0.0;
    for (var i = 0; i < layer.length; i++) {
      if (i > 0) y += minDistance(layer[i - 1], layer[i], ports, options);
      layer[i].y = y;
    }
  }
}

/// Where the arrow of [seg] leaves its item.
double outY(Seg seg, Map<GNode, Ports> ports) {
  final node = seg.from.node;
  return seg.from.y + (node == null ? 0 : ports[node]!.exitAt[seg.edge]!);
}

/// Where the arrow of [seg] enters its item.
double inY(Seg seg, Map<GNode, Ports> ports) {
  final node = seg.to.node;
  return seg.to.y + (node == null ? 0 : ports[node]!.inputAt[seg.edge]!);
}

/// The smallest change of height an arrow makes with full corners: a 45°
/// slant whose two corners just meet.
double smallestJog(LayoutOptions options) =>
    2 * options.cornerRadius * math.tan(math.pi / 8) / math.sqrt2;

/// Step 6, heights: places the items of every layer, left to right.
///
/// An item moves so that the input of the arrow from the longest path into it
/// is level with that arrow's exit, and the arrow runs straight. The longest
/// path is the one through the latest node: a pass point's arrow comes from
/// further back than a node of the layer before. Items take their places by
/// priority — those on longer paths through the graph first, nodes before
/// pass points, then from the middle of the layer out — each at the free
/// place nearest to where it wants to be, keeping the layer's order, but
/// never less than [smallestJog] off it.
///
/// With [levelInputs], a node with several arrows in tries the places it
/// would take for each height that brings one of its arrows in level, the
/// longest path's among them, and stands at the one where most of its
/// arrows come in level ([_levelAt]), counted where it would stand; on a
/// tie, at the place it takes for the longest path, else the one nearest
/// it. The pass points of the long arrows that can stand level with the
/// node's inputs move there once it has its place: the arrows run straight
/// into it from their turn before the corridor instead of jogging just
/// before it. Returns whether that placed anything otherwise than without
/// [levelInputs].
///
/// A node of [shifts] stands that much lower than it would — higher when
/// negative —, at the free place nearest to it: the end of a body snapped
/// to the arrows arriving at it (`_snap` in layout.dart).
bool placeLayers(
  LayoutGraph graph,
  List<List<Item>> layers,
  Map<GNode, Ports> ports,
  LayoutOptions options, {
  bool levelInputs = false,
  Map<GNode, double> shifts = const {},
}) {
  var levelled = false;
  final (:before, :after) = _pathLengths(graph);
  final smallest = smallestJog(options);
  for (final layer in layers) {
    final wanted = <Item, double?>{
      for (final item in layer) item: _wantedY(item, ports),
    };
    int priority(Item item) {
      final node = item.node;
      if (node != null) return before[node]! + after[node]! - 1;
      final edge = item.edge!;
      return before[edge.from]! + after[edge.to]!;
    }

    final middle = (layer.length - 1) / 2;
    final byPriority = [...layer]
      ..sort((a, b) {
        final pa = priority(a);
        final pb = priority(b);
        if (pa != pb) return pb.compareTo(pa);
        if (a.isPass != b.isPass) return a.isPass ? 1 : -1;
        final da = (a.order - middle).abs();
        final db = (b.order - middle).abs();
        if (da != db) return da.compareTo(db);
        return a.order.compareTo(b.order);
      });
    final placed = List<bool>.filled(layer.length, false);
    double distance(int from, int to) {
      var sum = 0.0;
      for (var k = from; k < to; k++) {
        sum += minDistance(layer[k], layer[k + 1], ports, options);
      }
      return sum;
    }

    for (final item in byPriority) {
      final i = item.order;
      int? above;
      for (var k = i - 1; k >= 0; k--) {
        if (placed[k]) {
          above = k;
          break;
        }
      }
      int? below;
      for (var k = i + 1; k < layer.length; k++) {
        if (placed[k]) {
          below = k;
          break;
        }
      }
      final low = above == null
          ? double.negativeInfinity
          : layer[above].y + distance(above, i);
      final high = below == null
          ? double.infinity
          : layer[below].y - distance(i, below);
      double placeAt(double want) {
        var y = low > high ? low : want.clamp(low, high);
        // A place a hair off where the item wants to be would leave its
        // arrow a jog too small for full corners: it moves on to a clear
        // slant.
        final off = y - want;
        if (wanted[item] != null && off != 0 && off.abs() < smallest) {
          final further = want + off.sign * smallest;
          if (further >= low && further <= high) y = further;
        }
        return y;
      }

      var y = placeAt(
        wanted[item] ?? (above != null ? low : (below != null ? high : 0.0)),
      );
      final node = item.node;
      if (levelInputs && node != null && item.ins.length > 1) {
        // Each height that brings an arrow in level, counted where the node
        // can stand for it.
        final longest = y;
        var most = _levelAt(item, longest, layers, ports, options).count;
        for (final seg in item.ins) {
          final at = placeAt(
            outY(seg, ports) - ports[node]!.inputAt[seg.edge]!,
          );
          final count = _levelAt(item, at, layers, ports, options).count;
          if (count > most ||
              count == most && (at - longest).abs() < (y - longest).abs()) {
            y = at;
            most = count;
          }
        }
        if ((y - longest).abs() > 1e-9) levelled = true;
      }
      final shift = node == null ? null : shifts[node];
      if (shift != null) y = placeAt(y + shift);
      if (levelInputs && node != null && item.ins.length > 1) {
        final moves = _levelAt(item, y, layers, ports, options).moves;
        for (final MapEntry(key: edge, value: level) in moves.entries) {
          for (final seg in edge.segs.skip(1)) {
            if ((seg.from.y - level).abs() > 1e-9) levelled = true;
            seg.from.y = level;
          }
        }
      }
      item.y = y;
      placed[i] = true;
      // A place found only by overlapping pushes the items under it down.
      var previous = i;
      for (var k = i + 1; k < layer.length; k++) {
        if (!placed[k]) continue;
        final least = layer[previous].y + distance(previous, k);
        if (layer[k].y < least) layer[k].y = least;
        previous = k;
      }
    }
  }
  return levelled;
}

/// Straightens long arrows: moves all pass points of an arrow to one height
/// where their layers have room, so that the arrow runs straight through its
/// corridor and bends only near its ends.
///
/// Tries, in turn, the height of the arrow's exit, of its input, of its first
/// and last pass points, and its highest and lowest pass points.
///
/// With [early], an arrow going forward into a node with several inputs
/// tries its input's height before its exit's: one running at its exit's
/// height would turn just before the node, in the way of those beside it.
/// And an arrow going forward that cannot run at its input's height all the
/// way takes it right past the last pass point that has no room there: the
/// pass points after it stand at the input's height, and those before it at
/// one height if they fit — the exit's, their first or last, their lowest
/// or highest. So it turns to its input past what stands in its way, not
/// just before its node, and never turns more: the pass points after the
/// obstacle all take the height it ends at. Returns whether that moved a
/// pass point anywhere but to one height for the whole arrow.
bool straightenPasses(
  LayoutGraph graph,
  List<List<Item>> layers,
  Map<GNode, Ports> ports,
  LayoutOptions options, {
  bool early = false,
}) {
  bool fits(Item item, double y) {
    final layer = layers[item.layer];
    final i = item.order;
    if (i > 0) {
      final above = layer[i - 1];
      if (y < above.y + minDistance(above, item, ports, options)) return false;
    }
    if (i + 1 < layer.length) {
      final below = layer[i + 1];
      if (y > below.y - minDistance(item, below, ports, options)) return false;
    }
    return true;
  }

  // A straightened arrow can make room for another: a few rounds.
  var moved = false;
  for (var round = 0; round < 3; round++) {
    for (final edge in graph.edges) {
      if (_straighten(edge, ports, fits, early: early)) moved = true;
    }
  }
  return moved;
}

/// Puts [passes] at the first of [heights] where they all fit; whether that
/// moved one.
bool _putAt(
  List<Item> passes,
  List<double> heights,
  bool Function(Item, double) fits,
) {
  for (final y in heights) {
    if (passes.every((pass) => fits(pass, y))) {
      var moved = false;
      for (final pass in passes) {
        if ((pass.y - y).abs() > 1e-9) moved = true;
        pass.y = y;
      }
      return moved;
    }
  }
  return false;
}

/// [straightenPasses] for one arrow; whether that moved a pass point when
/// [early] put some at the input's height ahead of the rest.
bool _straighten(
  GEdge edge,
  Map<GNode, Ports> ports,
  bool Function(Item, double) fits, {
  required bool early,
}) {
  final passes = [for (final seg in edge.segs.skip(1)) seg.from];
  if (passes.isEmpty) return false;
  List<double> heightsOf(List<Item> items) => [
    for (final item in items) item.y,
  ];
  final heights = heightsOf(passes);
  final input = inY(edge.segs.last, ports);
  var straight = false;
  // Into a node with several inputs, an arrow takes its input's height
  // before its exit's, so as not to stand in the way of those beside it.
  final inputFirst =
      early && edge.kind == EdgeKind.forward && edge.to.inEdges.length > 1;
  for (final y in [
    if (inputFirst) input,
    outY(edge.segs.first, ports),
    if (!inputFirst) input,
    heights.first,
    heights.last,
    heights.reduce(math.min),
    heights.reduce(math.max),
  ]) {
    if (passes.every((pass) => fits(pass, y))) {
      for (final pass in passes) {
        pass.y = y;
      }
      straight = true;
      break;
    }
  }
  if (!early || edge.kind != EdgeKind.forward) return false;
  // An arrow straight at its input's height is done; one straight at its
  // exit's or a band's turns to its input just before its node, and one
  // with no one height steps wherever its pass points stand.
  if (straight && (passes.last.y - input).abs() < 1e-9) return false;
  var k = passes.length;
  while (k > 0 && fits(passes[k - 1], input)) {
    k--;
  }
  // Room all the way: the arrow stays at the height it took; none at the
  // last pass point: nothing to take early.
  if (k == passes.length || k == 0) return false;
  var moved = false;
  for (final pass in passes.skip(k)) {
    if ((pass.y - input).abs() > 1e-9) moved = true;
    pass.y = input;
  }
  final before = passes.sublist(0, k);
  final placed = heightsOf(before);
  if (_putAt(before, [
    outY(edge.segs.first, ports),
    placed.first,
    placed.last,
    placed.reduce(math.min),
    placed.reduce(math.max),
  ], fits)) {
    moved = true;
  }
  return moved;
}

/// Where [item] wants its y: its input level with the exit of the arrow from
/// the longest path. `null` when no forward arrow comes in.
double? _wantedY(Item item, Map<GNode, Ports> ports) {
  if (item.ins.isEmpty) return null;
  final latest = item.ins.map((s) => s.edge.from.layer).reduce(math.max);
  final candidates = [
    for (final seg in item.ins)
      if (seg.edge.from.layer == latest) seg,
  ];
  final node = item.node;
  if (node != null) {
    final inputs = ports[node]!.inputs;
    candidates.sort(
      (a, b) => inputs.indexOf(a.edge).compareTo(inputs.indexOf(b.edge)),
    );
  }
  final seg = candidates[(candidates.length - 1) ~/ 2];
  final input = node == null ? 0 : ports[node]!.inputAt[seg.edge]!;
  return outY(seg, ports) - input;
}

/// How many of the arrows into [item], a node, come in level with their
/// inputs when its middle is at [y], and the long arrows that would move
/// for it, with the height each would take.
///
/// An arrow comes in level when the exit it comes from in the layer before
/// is level with its input, or when it is a long arrow all of whose pass
/// points stand there or can, each as far from its neighbours as
/// [minDistance] keeps them, the pass points of the other arrows that move
/// standing where they would. A long arrow whose pass points all have room
/// level with its exit is counted as staying there, as [straightenPasses]
/// keeps it but in the layouts `_worse` in layout.dart weighs — there, into
/// a node with several inputs, it tries its input's height first —: the
/// count may fall short, never over. Counting such arrows in level too,
/// measured, moved a tenth more nested levels, traded turns for arrows
/// turning twice, and lost the pinned `work()` view. The pass points of
/// arrows to one node are a lane gap apart in the corridor, as their inputs
/// are a port gap apart on the bar: a bundle of them that the nodes beside
/// it push up or down comes in level all together, or each a jog off.
({int count, Map<GEdge, double> moves}) _levelAt(
  Item item,
  double y,
  List<List<Item>> layers,
  Map<GNode, Ports> ports,
  LayoutOptions options,
) {
  final port = ports[item.node]!;
  final targets = <GEdge, double>{};
  final moving = <GEdge>{};
  double at(Item i) {
    final edge = i.edge;
    return edge != null && moving.contains(edge) ? targets[edge]! : i.y;
  }

  bool fits(GEdge edge, double Function(Item) height) {
    for (final seg in edge.segs.skip(1)) {
      final pass = seg.from;
      final layer = layers[pass.layer];
      final i = pass.order;
      final h = height(pass);
      if (i > 0) {
        final above = layer[i - 1];
        if (h < at(above) + minDistance(above, pass, ports, options) - 1e-6) {
          return false;
        }
      }
      if (i + 1 < layer.length) {
        final below = layer[i + 1];
        if (h > at(below) - minDistance(pass, below, ports, options) + 1e-6) {
          return false;
        }
      }
    }
    return true;
  }

  var level = 0;
  for (final seg in item.ins) {
    final target = y + port.inputAt[seg.edge]!;
    if (!seg.from.isPass) {
      if ((outY(seg, ports) - target).abs() < 1e-6) level++;
      continue;
    }
    // Else it turns just before the node, wherever the node stands.
    final exit = outY(seg.edge.segs.first, ports);
    if (fits(seg.edge, (_) => exit)) {
      if ((exit - target).abs() < 1e-6) level++;
      continue;
    }
    // Its last pass point level with the input is not enough: if the
    // others cannot stand there too, straightenPasses finds no one height
    // for them, and the arrow keeps the steps they stand at.
    targets[seg.edge] = target;
  }
  moving.addAll(targets.keys);

  // An arrow that cannot move stays where it is, and may stand in the way
  // of the ones next to it: until none is stuck.
  while (true) {
    final stuck = [
      for (final edge in moving)
        if (!fits(edge, at)) edge,
    ];
    if (stuck.isEmpty) break;
    moving.removeAll(stuck);
  }
  return (
    count: level + moving.length,
    moves: {for (final edge in moving) edge: targets[edge]!},
  );
}

/// For every node, the number of nodes on the longest forward path from a
/// first node to it, and from it to a last node; both count the node.
({Map<GNode, int> before, Map<GNode, int> after}) _pathLengths(
  LayoutGraph graph,
) {
  final before = <GNode, int>{};
  final after = <GNode, int>{};
  int countBefore(GNode node) => before[node] ??=
      1 +
      node.inEdges
          .where((e) => e.kind == EdgeKind.forward)
          .map((e) => countBefore(e.from))
          .fold(0, math.max);
  int countAfter(GNode node) => after[node] ??=
      1 +
      [
        for (final exit in node.exits)
          for (final edge in exit.edges)
            if (edge.kind == EdgeKind.forward) countAfter(edge.to),
      ].fold(0, math.max);
  for (final node in graph.nodes) {
    countBefore(node);
    countAfter(node);
  }
  return (before: before, after: after);
}

/// Where the marks of one exit are, for a tile whose left side is at x = 0.
final class ExitFrame {
  ExitFrame._({
    required this.exit,
    required this.x,
    required this.y,
    required this.arrows,
    required this.label,
    required this.reach,
    required this.area,
  });

  final GExit exit;

  /// The tile's right side, where the exit sits.
  final double x;

  /// The middle of the exit.
  final double y;

  /// Where each arrow leaves, top to bottom.
  final List<double> arrows;

  /// The chip of the exit's label; `null` for unlabelled edges.
  final Rect? label;

  /// How far right of [x] the exit's marks end — its label, or where a
  /// label would start: an arrow may turn only past it.
  final double reach;

  /// What the exit's marks cover: the dot or capsule, the chips.
  final Rect area;
}

/// Where a node's tile, texts and marks are, for a tile whose left side is
/// at x = 0 and whose middle is at the item's y.
final class NodeFrame {
  NodeFrame._(
    this.tile,
    this.name,
    this.place,
    this.marks,
    this.behind,
    this.status,
    this.bar,
    this.exits,
  );

  final Rect tile;

  /// The name under the tile; empty without one.
  final Rect name;

  /// The place under the name; empty without one.
  final Rect place;

  /// Over the tile: the tiles stacked behind copies, the badges over its top
  /// right corner.
  final Rect marks;

  /// Right of a frame drawn with outlines stacked behind it, up and to the
  /// right — copies —: where they run down its right side; `null` without
  /// them.
  final Rect? behind;

  /// The state badge on the tile's bottom right corner.
  final Rect status;

  /// The input bar with the arrowheads pointing at it; `null` when nothing
  /// comes in.
  final Rect? bar;

  final Map<GExit, ExitFrame> exits;

  /// Everything an arrow must keep off, besides the tile.
  Iterable<Rect> get obstacles sync* {
    yield name;
    yield place;
    yield marks;
    if (behind case final behind?) yield behind;
    yield status;
    if (bar case final bar?) yield bar;
    for (final exit in exits.values) {
      yield exit.area;
    }
  }
}

/// The frame of [node] with its tile's middle at [y] and left side at x = 0.
///
/// The tile of an expanded node is its frame: no name or place under it,
/// no state badge, the input bar and the exits level with its body's start
/// and end, and over it and down its right side only what is drawn with
/// the frame — the outlines stacked behind copies. A port has no width and
/// no marks, and nothing of its exits is drawn: arrows leave the start
/// straight from the frame's side. The end's bar is on the frame's side as
/// a tile's is on the tile's, the arrows pointing at it from a gap and a
/// head before it; the room it keeps ends at the side, past which the
/// frame's exit is.
NodeFrame frameOf(GNode node, Ports port, double y, LayoutOptions options) {
  final o = options;
  final framed = node.framed;
  final tile = Rect.fromLTWH(
    0,
    y - port.height / 2,
    node.widthOf(o),
    port.height,
  );
  Rect centred(String? text, LabelKind kind, double top, double height) {
    final middle = tile.center.x;
    if (text == null) return Rect.fromLTWH(middle, tile.bottom, 0, 0);
    final width = o.measure(text, kind);
    return Rect.fromLTWH(middle - width / 2, top, width, height);
  }

  final name = centred(
    framed == null ? node.name : null,
    LabelKind.nodeName,
    tile.bottom + nameTop,
    nameHeight,
  );
  final place = centred(
    framed == null ? node.place : null,
    LabelKind.place,
    tile.bottom + placeTop,
    placeHeight,
  );
  final above = node.port ? 0.0 : framed?.room.above;
  final marks = switch (above) {
    null => Rect.fromLTRB(
      tilesBehind(node.kind) > 0 ? tile.left + stackInset : tile.right - 60,
      tile.top - math.max(10, overTile(node.kind)),
      tile.right + 8,
      tile.top + 8,
    ),
    0.0 => Rect.fromLTRB(tile.right, tile.top, tile.right, tile.top),
    final above => Rect.fromLTRB(
      tile.left,
      tile.top - above,
      tile.right + above,
      tile.top,
    ),
  };
  final behind = above == null || above <= 0
      ? null
      : Rect.fromLTRB(
          tile.right,
          tile.top - above,
          tile.right + above,
          tile.bottom,
        );
  final status = framed != null || node.port
      ? Rect.fromLTRB(tile.right, tile.bottom, tile.right, tile.bottom)
      : Rect.fromLTRB(
          tile.right - 10,
          tile.bottom - 10,
          tile.right + 7,
          tile.bottom + 7,
        );
  final barMiddle = y + port.inputCentre;
  final bar = port.inputs.isEmpty
      ? null
      : Rect.fromLTRB(
          tile.left - o.barWidth / 2 - o.arrowGap - o.arrowLength,
          barMiddle - port.barHalf,
          node.port ? tile.left : tile.left + o.barWidth / 2,
          barMiddle + port.barHalf,
        );
  final exits = <GExit, ExitFrame>{};
  for (final exit in port.slots) {
    final middle = y + port.slotAt[exit]!;
    final arrows = [for (final edge in exit.edges) y + port.exitAt[edge]!];
    final top = arrows.first;
    final bottom = arrows.last;
    final chipTop = top - _chipLift - o.chipHeight;
    final x = tile.right;
    final text = exit.label;
    final label = text == null
        ? null
        : Rect.fromLTWH(
            x + _chipOffset,
            chipTop,
            o.measure(text, LabelKind.exitLabel) + 2 * o.chipPadding,
            o.chipHeight,
          );
    final marksEnd = label?.right ?? x + _chipOffset;
    final reach = node.port ? 0.0 : marksEnd + _chipSpacing * 2 - x;
    final area = node.port
        ? Rect.fromLTRB(x, top, x, bottom)
        : Rect.fromLTRB(
            x - _dotRadius,
            math.min(chipTop, top - _dotRadius),
            x + reach,
            bottom + _dotRadius,
          );
    exits[exit] = ExitFrame._(
      exit: exit,
      x: x,
      y: middle,
      arrows: arrows,
      label: label,
      reach: reach,
      area: area,
    );
  }
  return NodeFrame._(tile, name, place, marks, behind, status, bar, exits);
}

/// Where a label's chip starts right of the exit, how much room an arrow
/// keeps past it before turning, and how high over the arrow its bottom is.
const double _chipOffset = 6;
const double _chipSpacing = 2;
const double _chipLift = 2.5;

/// The exit dot's radius with its outline.
const double _dotRadius = 6.5;
