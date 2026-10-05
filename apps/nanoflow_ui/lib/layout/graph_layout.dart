import 'package:nanoflow_model/nanoflow_model.dart';

import 'geometry.dart';
import 'layout_graph.dart';

/// A laid out graph. Coordinates start at (0, 0), the top left corner of
/// [bounds] — but those of a body in a frame ([FrameBox.inner]) are the
/// coordinates of the layout round it.
final class GraphLayout {
  GraphLayout({
    required this.nodes,
    required this.exits,
    required this.edges,
    required this.bounds,
    required this.options,
  });

  /// Every node by id: the start marker, the body's nodes in its order, the
  /// end markers.
  final Map<String, NodeBox> nodes;

  /// Every exit of every node, node by node in [nodes]' order, each node's
  /// exits in the order of their first edges.
  final List<ExitBox> exits;

  /// Every arrow, in the body's order.
  final List<EdgePath> edges;

  /// Everything drawn: tiles, texts, marks, arrows.
  final Rect bounds;

  /// The options the layout was made with.
  final LayoutOptions options;
}

/// Where a node is drawn.
final class NodeBox {
  NodeBox({
    required this.id,
    required this.kind,
    required this.node,
    required this.name,
    required this.fullName,
    required this.place,
    required this.inside,
    required this.layer,
    required this.tile,
    required this.nameRect,
    required this.placeRect,
    required this.marks,
    required this.status,
    required this.bar,
    this.frame,
    this.port = false,
  });

  /// The body node's id, [startMarker], or an end marker's ([endMarkerAt]).
  final String id;

  final NodeKind kind;

  /// The body's node; `null` for a marker.
  final GraphNode? node;

  /// The name under the tile, cut to [nameLength] characters with `…`;
  /// `null` for a marker.
  final String? name;

  /// The whole name, for a tooltip; `null` for a marker.
  final String? fullName;

  /// The place in the code under the name: `review.dart:49`; `null` for a
  /// marker, or when unknown.
  final String? place;

  /// What is written inside the tile instead of an icon: `start`, `end`,
  /// the effects of a call or of a copy, `{ 3 }`.
  final String? inside;

  /// The node's layer, 0 for the leftmost.
  final int layer;

  /// The tile.
  final Rect tile;

  /// The name, centred under the tile; empty without a name.
  final Rect nameRect;

  /// The place, centred under the name; empty without a place.
  final Rect placeRect;

  /// The room kept over the tile: for the tiles stacked behind a call or
  /// copies, and for badges over its top right corner.
  final Rect marks;

  /// The room kept for the state badge on the tile's bottom right corner.
  final Rect status;

  /// The input bar; `null` when no arrow comes in.
  final InputBar? bar;

  /// Whether this is the start or the end of a body in a frame: a point on
  /// the frame's side, [tile] without width. Neither it nor its exits are
  /// drawn — the start's arrows leave the frame's side, where the frame's
  /// bar is; the end's bar is drawn with the frame ([FrameBox.endBar]).
  final bool port;

  /// The body of a call or copies expanded in place, [tile] its frame;
  /// `null` for a node drawn as a tile. A frame has no name or place under
  /// it: [nameRect] and [placeRect] are empty.
  final FrameBox? frame;
}

/// The body of a node expanded in place, in the node's frame (decision 6):
/// its layout, and the link from the frame's left side to its start.
///
/// Arrows into the node point at the bar on the frame's left side, level
/// with the body's start, and those of the body go on from there; the
/// body's arrows to its end point at its bar on the frame's right side, as
/// at a tile's, and arrows out of the node leave the bar. The start and end
/// are ports on the sides. The end is always on its side, the arrows to it
/// running on as far as need be; a link runs straight from the left side to
/// a start off it — the name or place under a node after the start reaching
/// further left.
final class FrameBox {
  FrameBox({required this.inner, required this.entry});

  /// The body's layout, in the coordinates of the layout round it: its
  /// bounds lie in the frame, under the frame's title row. It has one end,
  /// right of everything else in it.
  final GraphLayout inner;

  /// From the frame's left side to the body's start, none long when it is
  /// on the side; `null` when the body has no start.
  final Segment? entry;

  /// The bar of the body's end, its width's middle on the frame's right
  /// side; `null` when the body has no end.
  InputBar? get endBar => inner.nodes[endMarker]?.bar;
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

  /// A capsule, for edges side by side: an arrow per edge.
  capsule,
}

/// Where an exit is drawn.
final class ExitBox {
  ExitBox({
    required this.node,
    required this.index,
    required this.label,
    required this.shape,
    required this.anchor,
    required this.handle,
    required this.labelRect,
    required this.reach,
  });

  /// The id of the node the exit belongs to.
  final String node;

  /// The exit's index in the node's exits.
  final int index;

  /// The label of the exit's edges; `null` for unlabelled edges.
  final String? label;

  final ExitShape shape;

  /// The middle of the dot or the capsule.
  final Point anchor;

  /// The dot or the capsule.
  final Rect handle;

  /// The opaque chip of the label; `null` when there is no label.
  final Rect? labelRect;

  /// How far right of the anchor the exit's marks end — the label, when
  /// there is one: the arrows leave straight at least that far.
  final double reach;
}

/// Where an arrow is drawn.
final class EdgePath {
  EdgePath({
    required this.from,
    required this.exitIndex,
    required this.listIndex,
    required this.edgeIndex,
    required this.to,
    required this.kind,
    required this.points,
    required this.tip,
    required this.pieces,
  });

  /// The id of the node the arrow leaves.
  final String from;

  /// The index of the exit it leaves by, in the node's exits.
  final int exitIndex;

  /// The arrow's index among the arrows of its exit.
  final int listIndex;

  /// The index of the edge it draws in the body's edges (`GraphBody.edges`),
  /// those the layout left out counted: what a session's passes name it by.
  final int edgeIndex;

  /// The id of the node the arrow enters.
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
