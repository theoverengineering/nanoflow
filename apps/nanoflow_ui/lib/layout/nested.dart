import 'dart:math' as math;

import 'package:nanoflow_model/nanoflow_model.dart';

import 'geometry.dart';
import 'graph_layout.dart';
import 'layout_graph.dart';
import 'ports.dart';

/// The room a frame keeps round the body it holds (decision 6,
/// docs/design/code-first/function-frames.html): a row over the body for
/// its title — and, for copies, the switcher —, its sides and its bottom,
/// how wide it is at least, and how far what is drawn over it reaches.
final class FrameRoom {
  const FrameRoom({
    this.top = 32,
    this.side = 16,
    this.bottom = 16,
    this.width = 0,
    this.above = 0,
  });

  /// From the frame's top to the body: the title row.
  final double top;

  /// Between a side of the frame and the body, where the body has no port
  /// on it: no start on the left, no end on the right. A body narrower than
  /// the frame sits at its left side, or at its right when it has an end
  /// but no start.
  final double side;

  /// Between the body and the frame's bottom.
  final double bottom;

  /// The least width of the frame: its title row must fit.
  final double width;

  /// How far over the frame, and right of it, what is drawn with it
  /// reaches: the outlines stacked behind copies.
  final double above;

  @override
  bool operator ==(Object other) =>
      other is FrameRoom &&
      other.top == top &&
      other.side == side &&
      other.bottom == bottom &&
      other.width == width &&
      other.above == above;

  @override
  int get hashCode => Object.hash(top, side, bottom, width, above);
}

/// A call or copies expanded in place: [body] — the function's, or a
/// copy's — drawn in a frame instead of the node's tile, with the [room]
/// the frame keeps round it, and the nodes of [body] expanded in turn.
final class ExpandedNode {
  const ExpandedNode(
    this.body, {
    this.room = const FrameRoom(),
    this.expanded = const {},
  });

  final GraphBody body;

  final FrameRoom room;

  /// The nodes of [body] expanded in place, by id.
  final Map<String, ExpandedNode> expanded;
}

/// The body of an expanded node laid out, and the frame round it: a node of
/// the layout around as big as the frame. Arrows into the node come to the
/// frame's left side level with the body's start, and leave the bar of the
/// body's end on its right side from the bar's middle.
final class FramedBody {
  FramedBody._({
    required this.inner,
    required this.room,
    required this.width,
    required this.height,
    required this.innerAt,
    required this.entry,
    required this.exit,
  });

  /// [laid], the layout of the body of [node] — its start first and its
  /// end last, ports — in a frame with [room] round it: its start on the
  /// frame's left side, its end on the right side, and the room's sides
  /// only where the body has none of them; tall and wide enough besides for
  /// the input bar and the exits on its sides, off its corners. A frame
  /// wider than its body has the room to spare right of it — but for the
  /// arrows to the body's end, which run on to the end on the side.
  factory FramedBody.of(
    GNode node,
    GraphLayout laid,
    FrameRoom room,
    LayoutOptions options,
  ) {
    final body = laid.bounds;
    final entry = laid.nodes[startMarker]?.tile.center.y;
    final exit = laid.nodes[endMarker]?.tile.center.y;
    final r = options.tileRadius;
    final inputs = node.inEdges.isEmpty
        ? 0.0
        : barLength(node.inEdges.length, options) / 2;
    final exits =
        node.exits.fold(0.0, (sum, x) => sum + exitUnits(x)) *
        options.exitGap /
        2;
    var top = room.top;
    var bottom = room.bottom;
    var least = options.tile;
    for (final (at, half) in [(entry, inputs), (exit, exits)]) {
      if (at == null) {
        least = math.max(least, 2 * (half + r));
      } else {
        top = math.max(top, r + half - at);
        bottom = math.max(bottom, r + half - (body.height - at));
      }
    }
    final left = entry == null ? room.side : 0.0;
    final right = exit == null ? room.side : 0.0;
    final width = [
      body.width + left + right,
      room.width,
      options.tile,
    ].reduce(math.max);
    // A frame taller than its body and rooms has the room to spare under
    // the body.
    final height = math.max(least, top + body.height + bottom);
    final at = Point(
      entry == null && exit != null ? width - right - body.width : left,
      top,
    );
    // The end is on the frame's right side, where its bar is: when the
    // frame is wider than the body, or the name or place under a node
    // before the end reaches past it, the arrows to the end run on straight
    // to the side.
    final end = laid.nodes[endMarker]?.tile.left;
    final side = width - at.x;
    final inner = end != null && side - end > 1e-6 ? _endAt(laid, side) : laid;
    return FramedBody._(
      inner: inner,
      room: room,
      width: width,
      height: height,
      innerAt: at,
      entry: entry == null ? null : top + entry,
      exit: exit == null ? null : top + exit,
    );
  }

  /// The body's layout, from (0, 0).
  final GraphLayout inner;

  /// The room the frame keeps round it.
  final FrameRoom room;

  /// The frame's size.
  final double width;
  final double height;

  /// Where [inner]'s origin is in the frame.
  final Point innerAt;

  /// How far under the frame's top the arrows come in, level with the
  /// body's start; `null` when it has none: in the frame's middle.
  final double? entry;

  /// How far under the frame's top the arrows go out, level with the
  /// body's end; `null` when it has none: in the frame's middle.
  final double? exit;

  /// The offset of the arrows in from the frame's middle.
  double get inputCentre => (entry ?? height / 2) - height / 2;

  /// The offset of the exits from the frame's middle.
  double get exitCentre => (exit ?? height / 2) - height / 2;

  /// The frame of the node whose frame is [tile] on the canvas: [inner]
  /// moved into it, with the links from its sides to the body's start and
  /// end.
  FrameBox placeIn(Rect tile) {
    final at = Point(tile.left, tile.top) + innerAt;
    final moved = shiftLayout(inner, at);
    final start = moved.nodes[startMarker]?.tile;
    final end = moved.nodes[endMarker]?.tile;
    return FrameBox(
      inner: moved,
      entry: start == null
          ? null
          : Segment(
              Point(tile.left, start.center.y),
              Point(start.left, start.center.y),
            ),
      exit: end == null
          ? null
          : Segment(
              Point(end.right, end.center.y),
              Point(tile.right, end.center.y),
            ),
    );
  }
}

/// [inner], the layout of a body with an end, with the end moved right to
/// [x] and the arrows to it running on straight as far.
GraphLayout _endAt(GraphLayout inner, double x) {
  final by = x - inner.nodes[endMarker]!.tile.left;
  final b = inner.bounds;
  return GraphLayout(
    nodes: {
      for (final MapEntry(key: id, value: n) in inner.nodes.entries)
        id: id == endMarker ? _shiftNode(n, Point(by, 0)) : n,
    },
    exits: inner.exits,
    edges: [
      for (final e in inner.edges)
        e.to == endMarker ? _runOn(e, by, inner.options) : e,
    ],
    bounds: Rect.fromLTRB(b.left, b.top, math.max(b.right, x), b.bottom),
    options: inner.options,
  );
}

/// [edge] with its last, straight piece [by] longer, and its head as far
/// further on.
EdgePath _runOn(EdgePath edge, double by, LayoutOptions options) {
  final shift = Point(by, 0);
  final points = [
    ...edge.points.take(edge.points.length - 1),
    edge.points.last + shift,
  ];
  return EdgePath(
    from: edge.from,
    exitIndex: edge.exitIndex,
    listIndex: edge.listIndex,
    edgeIndex: edge.edgeIndex,
    to: edge.to,
    kind: edge.kind,
    points: points,
    tip: edge.tip + shift,
    pieces: roundCorners(points, options.cornerRadius),
  );
}

/// [n] moved by [by]: its tile, texts, marks and bar, and its frame.
NodeBox _shiftNode(NodeBox n, Point by) {
  Rect rect(Rect r) => r.shift(by);
  Segment? segment(Segment? s) =>
      s == null ? null : Segment(s.a + by, s.b + by);
  return NodeBox(
    id: n.id,
    kind: n.kind,
    node: n.node,
    name: n.name,
    fullName: n.fullName,
    place: n.place,
    inside: n.inside,
    layer: n.layer,
    tile: rect(n.tile),
    nameRect: rect(n.nameRect),
    placeRect: rect(n.placeRect),
    marks: rect(n.marks),
    status: rect(n.status),
    bar: switch (n.bar) {
      final bar? => InputBar(
        rect: rect(bar.rect),
        inputs: [for (final y in bar.inputs) y + by.y],
      ),
      null => null,
    },
    frame: switch (n.frame) {
      final frame? => FrameBox(
        inner: shiftLayout(frame.inner, by),
        entry: segment(frame.entry),
        exit: segment(frame.exit),
      ),
      null => null,
    },
    port: n.port,
  );
}

/// [layout] moved by [by]: everything it draws, the frames in it too.
GraphLayout shiftLayout(GraphLayout layout, Point by) {
  Rect rect(Rect r) => r.shift(by);
  return GraphLayout(
    nodes: {
      for (final MapEntry(key: id, value: n) in layout.nodes.entries)
        id: _shiftNode(n, by),
    },
    exits: [
      for (final x in layout.exits)
        ExitBox(
          node: x.node,
          index: x.index,
          label: x.label,
          shape: x.shape,
          anchor: x.anchor + by,
          handle: rect(x.handle),
          labelRect: x.labelRect?.shift(by),
          reach: x.reach,
        ),
    ],
    edges: [
      for (final e in layout.edges)
        EdgePath(
          from: e.from,
          exitIndex: e.exitIndex,
          listIndex: e.listIndex,
          edgeIndex: e.edgeIndex,
          to: e.to,
          kind: e.kind,
          points: [for (final p in e.points) p + by],
          tip: e.tip + by,
          pieces: [
            for (final piece in e.pieces)
              switch (piece) {
                LinePiece(:final to) => LinePiece(to + by),
                ArcPiece(:final to, :final radius, :final clockwise) =>
                  ArcPiece(to + by, radius: radius, clockwise: clockwise),
              },
          ],
        ),
    ],
    bounds: rect(layout.bounds),
    options: layout.options,
  );
}
