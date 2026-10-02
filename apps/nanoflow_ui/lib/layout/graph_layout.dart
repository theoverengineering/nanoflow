import 'geometry.dart';
import 'layout_graph.dart';

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
