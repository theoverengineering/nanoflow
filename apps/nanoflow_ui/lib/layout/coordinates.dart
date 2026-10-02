import 'dart:math' as math;

import 'geometry.dart';
import 'layout_graph.dart';
import 'ports.dart';

/// Where the name sits under a tile: its top below the tile's bottom.
const double nameTop = 8;

/// The height of the name's line.
const double nameHeight = 15;

/// Where the command sits under a tile: its top below the tile's bottom.
const double commandTop = nameTop + nameHeight + 2;

/// The height of the command's line.
const double commandHeight = 13;

/// The `start` caption over a tile: its height, and its gap to the tile.
const double startHeight = 12;
const double startGap = 8;

/// How far a loop runs from what it goes around: the marks over the tile, or
/// the command under it.
const double loopClear = 8;

/// The room the marks over a tile take: badges in its top right corner, and
/// the `start` caption over a `start` node.
double marksAbove(GNode node) => node.isStart ? startHeight + startGap + 2 : 12;

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
      ? ports.height / 2 + commandTop + commandHeight + reach
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
        ? port.height / 2 + commandTop + commandHeight
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

/// Step 6, heights: places the items of every layer, left to right.
///
/// An item moves so that the input of the arrow from the longest path into it
/// is level with that arrow's exit, and the arrow runs straight. The longest
/// path is the one through the latest node: a pass point's arrow comes from
/// further back than a node of the layer before. Items take their places by
/// priority — those on longer paths through the graph first, nodes before
/// pass points, then from the middle of the layer out — each at the free
/// place nearest to where it wants to be, keeping the layer's order.
void placeLayers(
  LayoutGraph graph,
  List<List<Item>> layers,
  Map<GNode, Ports> ports,
  LayoutOptions options,
) {
  final (:before, :after) = _pathLengths(graph);
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
      final want =
          wanted[item] ?? (above != null ? low : (below != null ? high : 0.0));
      item.y = low > high ? low : want.clamp(low, high);
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
}

/// Straightens long arrows: moves all pass points of an arrow to one height
/// where their layers have room, so that the arrow runs straight through its
/// corridor and bends only near its ends.
///
/// Tries, in turn, the height of the arrow's exit, of its input, of its first
/// and last pass points, and its highest and lowest pass points.
void straightenPasses(
  LayoutGraph graph,
  List<List<Item>> layers,
  Map<GNode, Ports> ports,
  LayoutOptions options,
) {
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
  for (var round = 0; round < 3; round++) {
    for (final edge in graph.edges) {
      _straighten(edge, ports, fits);
    }
  }
}

void _straighten(
  GEdge edge,
  Map<GNode, Ports> ports,
  bool Function(Item, double) fits,
) {
  final passes = [for (final seg in edge.segs.skip(1)) seg.from];
  if (passes.isEmpty) return;
  final heights = [for (final pass in passes) pass.y];
  final candidates = [
    outY(edge.segs.first, ports),
    inY(edge.segs.last, ports),
    heights.first,
    heights.last,
    heights.reduce(math.min),
    heights.reduce(math.max),
  ];
  for (final y in candidates) {
    if (passes.every((pass) => fits(pass, y))) {
      for (final pass in passes) {
        pass.y = y;
      }
      return;
    }
  }
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
    required this.counter,
    required this.reach,
    required this.area,
  });

  final GExit exit;

  /// The tile's right side, where the exit sits.
  final double x;

  /// The middle of the exit.
  final double y;

  /// Where each arrow leaves, top to bottom; empty for a stub.
  final List<double> arrows;

  /// The chip of the exit's key; `null` for a worker's exit.
  final Rect? label;

  /// The top left corner of the counter's chip, right after the key.
  final Point counter;

  /// How far right of [x] the key and the room for a counter end: an arrow
  /// may turn only past it, a stub ends there.
  final double reach;

  /// What the exit's marks cover: the dot or capsule, the chips, the stub.
  final Rect area;

  /// The x where the stub ends, for an empty target.
  double get stubEnd => x + reach;
}

/// Where a node's tile, texts and marks are, for a tile whose left side is
/// at x = 0 and whose middle is at the item's y.
final class NodeFrame {
  NodeFrame._(
    this.tile,
    this.name,
    this.command,
    this.start,
    this.marks,
    this.status,
    this.bar,
    this.exits,
  );

  final Rect tile;
  final Rect name;
  final Rect command;

  /// The `start` caption, for a `start` node.
  final Rect? start;

  /// The badges over the tile's top right corner: a run's id, a visit count.
  final Rect marks;

  /// The state badge on the tile's bottom right corner.
  final Rect status;

  /// The input bar with the arrowheads pointing at it; `null` when nothing
  /// comes in.
  final Rect? bar;

  final Map<GExit, ExitFrame> exits;

  /// Everything an arrow must keep off, besides the tile.
  Iterable<Rect> get obstacles sync* {
    yield name;
    yield command;
    if (start case final start?) yield start;
    yield marks;
    yield status;
    if (bar case final bar?) yield bar;
    for (final exit in exits.values) {
      yield exit.area;
    }
  }
}

/// The frame of [node] with its tile's middle at [y] and left side at x = 0.
NodeFrame frameOf(GNode node, Ports port, double y, LayoutOptions options) {
  final o = options;
  final tile = Rect.fromLTWH(0, y - port.height / 2, o.tile, port.height);
  Rect centred(String text, LabelKind kind, double top, double height) {
    final width = o.measure(text, kind);
    final middle = tile.center.x;
    return Rect.fromLTWH(middle - width / 2, top, width, height);
  }

  final name = centred(
    node.name,
    LabelKind.nodeName,
    tile.bottom + nameTop,
    nameHeight,
  );
  final command = centred(
    node.node.run,
    LabelKind.command,
    tile.bottom + commandTop,
    commandHeight,
  );
  final start = node.isStart
      ? Rect.fromLTWH(
          tile.left,
          tile.top - startGap - startHeight,
          _startWidth,
          startHeight,
        )
      : null;
  final marks = Rect.fromLTRB(
    tile.right - 60,
    tile.top - 10,
    tile.right + 8,
    tile.top + 8,
  );
  final status = Rect.fromLTRB(
    tile.right - 10,
    tile.bottom - 10,
    tile.right + 7,
    tile.bottom + 7,
  );
  final bar = port.inputs.isEmpty
      ? null
      : Rect.fromLTRB(
          tile.left - o.barWidth / 2 - o.arrowGap - o.arrowLength,
          y - port.barHalf,
          tile.left + o.barWidth / 2,
          y + port.barHalf,
        );
  final counterWidth =
      o.measure(counterReserve, LabelKind.counter) + 2 * o.chipPadding;
  final exits = <GExit, ExitFrame>{};
  for (final exit in port.slots) {
    final middle = y + port.slotAt[exit]!;
    final arrows = [for (final edge in exit.edges) y + port.exitAt[edge]!];
    final top = arrows.isEmpty ? middle : arrows.first;
    final bottom = arrows.isEmpty ? middle : arrows.last;
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
    final counter = Point(
      label == null ? x + _chipOffset : label.right + _chipSpacing,
      chipTop,
    );
    final reach = counter.x + counterWidth + _chipSpacing * 2 - x;
    final area = Rect.fromLTRB(
      x - _dotRadius,
      math.min(chipTop, top - _dotRadius),
      exit.isStub ? x + reach + _stubBar : x + reach,
      exit.isStub ? middle + _stubHalf : bottom + _dotRadius,
    );
    exits[exit] = ExitFrame._(
      exit: exit,
      x: x,
      y: middle,
      arrows: arrows,
      label: label,
      counter: counter,
      reach: reach,
      area: area,
    );
  }
  return NodeFrame._(tile, name, command, start, marks, status, bar, exits);
}

/// The text a counter's room is measured for: two digits.
const String counterReserve = '99×';

/// The width of the `start` caption: 9.5 px capitals, spaced.
const double _startWidth = 40;

/// Where chips start right of the exit, how far apart they are, and how high
/// over the arrow their bottom is.
const double _chipOffset = 6;
const double _chipSpacing = 2;
const double _chipLift = 2.5;

/// The exit dot's radius with its outline, and a stub's cross bar: its half
/// length and its stroke's half width.
const double _dotRadius = 6.5;
const double _stubHalf = 6;
const double _stubBar = 1.5;
