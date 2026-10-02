import 'package:nanoflow_model/nanoflow_model.dart';

/// What a piece of text on the canvas is, for measuring its width.
enum LabelKind {
  /// The key of a fork's exit: `true`, `else`, `accepted`.
  exitLabel,

  /// How many times runs went along an arrow: `2×`.
  counter,

  /// A node's name under its tile.
  nodeName,

  /// A node's command under its name.
  command,

  /// The `start` caption over a `start` node's tile.
  startCaption,
}

/// Measures the width of [text] drawn as [kind], in logical pixels.
typedef MeasureText = double Function(String text, LabelKind kind);

/// Text widths of the mockup fonts, one width per character.
///
/// Exit labels and counters are Geist Mono 10 px (6 px a character, as the
/// mockup's label chips are), commands Geist Mono 10.5 px. Names are a
/// proportional 12.5 px semibold face; 7.2 px is a generous average so that
/// names are not narrower than drawn. The `start` caption is 9.5 px
/// semibold capitals spaced 0.08 em. The canvas passes a real measurer.
double monospaceMeasure(String text, LabelKind kind) =>
    text.runes.length *
    switch (kind) {
      LabelKind.exitLabel || LabelKind.counter => 6.0,
      LabelKind.command => 6.3,
      LabelKind.nodeName => 7.2,
      LabelKind.startCaption => 7.0,
    };

/// The text of the `start` caption.
const String startCaption = 'START';

/// The text of an arrow's counter for [count] passes: `2×`.
///
/// The layout keeps room for three digits whether or not there is a
/// counter; from a thousand passes on the counter reads `1k+×`.
String counterText(int count) => count < 1000 ? '$count×' : '1k+×';

/// Sizes and gaps of the layout. The defaults are taken from the mockups
/// (`docs/design/graph.html`, `task-graph.html`) and `docs/ui-spec.md`.
final class LayoutOptions {
  const LayoutOptions({
    this.tile = 80,
    this.tileRadius = 12,
    this.cornerRadius = 10,
    this.laneGap = 10,
    this.portGap = 10,
    this.capsuleGap = 14,
    this.exitGap = 25,
    this.minInputStraight = 20,
    this.arrowLength = 10,
    this.arrowGap = 7.5,
    this.barWidth = 5,
    this.minBar = 20,
    this.chipHeight = 12,
    this.chipPadding = 3,
    this.nodeGap = 24,
    this.passGap = 16,
    this.backLaneOffset = 20,
    this.backLaneGap = 12,
    this.measure = monospaceMeasure,
  });

  /// The side of a tile; tiles with many exits or inputs grow taller.
  final double tile;

  /// The radius of a tile's corners. The input bar stays off them.
  final double tileRadius;

  /// The radius of an arrow's rounded corners.
  final double cornerRadius;

  /// The least distance between parallel pieces of different arrows, and
  /// between lanes where arrows turn.
  final double laneGap;

  /// The distance between inputs on a bar.
  final double portGap;

  /// The distance between the arrows leaving one capsule.
  final double capsuleGap;

  /// The distance between exits on a tile's right side.
  final double exitGap;

  /// The least length of an arrow's last straight piece.
  final double minInputStraight;

  /// The arrowhead's length: the line ends at its base.
  final double arrowLength;

  /// The gap between an arrowhead's tip and the input bar.
  final double arrowGap;

  /// The input bar's thickness, centred on the tile's left side.
  final double barWidth;

  /// The least length of an input bar.
  final double minBar;

  /// The height of the opaque chip behind an exit label or counter.
  final double chipHeight;

  /// The space between a chip's edge and its text.
  final double chipPadding;

  /// The least vertical gap between two nodes of a layer (their labels and
  /// marks included).
  final double nodeGap;

  /// The least vertical gap between a node and an arrow passing it.
  final double passGap;

  /// How far below the lowest node the first lane of back arrows runs.
  final double backLaneOffset;

  /// The distance between lanes of back arrows.
  final double backLaneGap;

  /// Measures text widths.
  final MeasureText measure;
}

/// How an arrow runs.
enum EdgeKind {
  /// To a node of a later layer, left to right.
  forward,

  /// To a node of an earlier layer: dashed, around the graph's bottom.
  back,

  /// From a node to itself, around its tile.
  loop,
}

/// A node of the graph being laid out.
final class GNode {
  GNode._(this.index, this.node, {required this.isStart});

  /// The position of the node in the graph's declaration order.
  final int index;

  final Node node;

  /// Whether `start` names the node.
  final bool isStart;

  String get name => node.name;

  bool get isFork => node is ForkNode;

  /// The node's exits in declaration order.
  final List<GExit> exits = [];

  /// Arrows into the node.
  final List<GEdge> inEdges = [];

  /// The layer: the length of the longest forward path from `start`.
  int layer = 0;

  /// When the walk of step 1 reached the node.
  int seen = 0;

  /// The node's place in the layout's internal lists of items.
  late final Item item;

  @override
  String toString() => name;
}

/// One exit of a node: a dot, a capsule or a stub.
final class GExit {
  GExit._(this.node, this.index, this.exit);

  final GNode node;

  /// The exit's index in [Node.exits].
  final int index;

  final Exit exit;

  /// The exit's key, `null` for a worker.
  String? get label => exit.label;

  bool get isElse => exit.isElse;

  /// One arrow per target node, in list order.
  final List<GEdge> edges = [];

  /// An empty target: a stub instead of an arrow.
  bool get isStub => edges.isEmpty;

  /// A list target: one capsule, an arrow per node.
  bool get isCapsule => edges.length > 1;

  @override
  String toString() => '${node.name}.${label ?? 'then'}';
}

/// One arrow: from an exit (and a place in its list) to a node.
final class GEdge {
  GEdge._(this.exit, this.listIndex, this.to, this.index);

  final GExit exit;

  /// The arrow's index in the exit's target list; 0 for a single target.
  final int listIndex;

  final GNode to;

  /// The arrow's position among all arrows in declaration order.
  final int index;

  GNode get from => exit.node;

  EdgeKind kind = EdgeKind.forward;

  /// When the walk of step 1 looked at the arrow.
  int seen = 0;

  /// The forward pieces between neighbouring layers, left to right.
  final List<Seg> segs = [];

  @override
  String toString() => '$exit[$listIndex]->${to.name}';
}

/// The graph as the layout sees it: nodes, exits and arrows.
final class LayoutGraph {
  LayoutGraph._(this.nodes, this.starts, this.edges);

  /// Builds the layout's view of [graph].
  ///
  /// Targets that name no node are left out, as if the target were empty.
  factory LayoutGraph.of(Graph graph) {
    final startNames = graph.start.names.toSet();
    final nodes = <GNode>[];
    final byName = <String, GNode>{};
    for (final node in graph.nodes.values) {
      final gnode = GNode._(
        nodes.length,
        node,
        isStart: startNames.contains(node.name),
      );
      nodes.add(gnode);
      byName[node.name] = gnode;
    }
    final edges = <GEdge>[];
    for (final gnode in nodes) {
      final exits = gnode.node.exits;
      for (var i = 0; i < exits.length; i++) {
        final gexit = GExit._(gnode, i, exits[i]);
        gnode.exits.add(gexit);
        final names = exits[i].target.names;
        for (var j = 0; j < names.length; j++) {
          final to = byName[names[j]];
          if (to == null) continue;
          final edge = GEdge._(gexit, j, to, edges.length);
          gexit.edges.add(edge);
          to.inEdges.add(edge);
          edges.add(edge);
        }
      }
    }
    final starts = [for (final name in graph.start.names) ?byName[name]];
    return LayoutGraph._(nodes, starts, edges);
  }

  /// The nodes in declaration order.
  final List<GNode> nodes;

  /// The nodes `start` names, in its order.
  final List<GNode> starts;

  /// Every arrow, in declaration order.
  final List<GEdge> edges;
}

/// Something that takes a place in a layer: a node, or a pass point of a long
/// arrow through the layer.
final class Item {
  Item.node(GNode this.node) : edge = null, layer = node.layer;

  Item.pass(GEdge this.edge, this.layer) : node = null;

  final GNode? node;

  /// The arrow a pass point belongs to.
  final GEdge? edge;

  final int layer;

  bool get isPass => node == null;

  /// The item's position in its layer, top to bottom.
  int order = 0;

  /// The y of the tile's middle, or of the arrow through a pass point.
  double y = 0;

  /// Forward pieces into the item, from the layer before.
  final List<Seg> ins = [];

  /// Forward pieces out of the item, into the layer after.
  final List<Seg> outs = [];

  @override
  String toString() => node?.name ?? 'pass($edge@$layer)';
}

/// A forward piece of an arrow between items of neighbouring layers.
final class Seg {
  Seg(this.edge, this.from, this.to);

  final GEdge edge;
  final Item from;
  final Item to;

  @override
  String toString() => '$from->$to';
}
