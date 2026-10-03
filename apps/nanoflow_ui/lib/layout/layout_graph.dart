import 'dart:math' as math;

import 'package:nanoflow_model/nanoflow_model.dart';

import 'nested.dart';

/// What a piece of text on the canvas is, for measuring its width.
enum LabelKind {
  /// The label of an exit: `true`, `each`, `Channel.stable`.
  exitLabel,

  /// How many times the flow went along an arrow: `2×`.
  counter,

  /// A node's name under its tile.
  nodeName,

  /// A node's place in the code under its name.
  place,
}

/// Measures the width of [text] drawn as [kind], in logical pixels.
typedef MeasureText = double Function(String text, LabelKind kind);

/// Text widths of the mockup fonts, one width per character.
///
/// Exit labels and counters are Geist Mono 10 px (6 px a character, as the
/// mockup's label chips are), places Geist Mono 10.5 px. Names are a
/// proportional 12.5 px semibold face; 7.2 px is a generous average so that
/// names are not narrower than drawn. The canvas passes a real measurer.
double monospaceMeasure(String text, LabelKind kind) =>
    text.runes.length *
    switch (kind) {
      LabelKind.exitLabel || LabelKind.counter => 6.0,
      LabelKind.place => 6.3,
      LabelKind.nodeName => 7.2,
    };

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
    this.marker = 50,
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

  /// The least height of the start and end markers, which are as wide as a
  /// tile.
  final double marker;

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

/// What a node of the canvas is: a marker of where the body starts or
/// ends, or a node of the body (spec §6.1).
enum NodeKind {
  /// Where the body starts: the edges `from: null` leave it.
  start,

  /// Where the body ends: the edges `to: null` enter it.
  end,

  /// A call of `f.step`.
  step,

  /// A condition the flow goes one of several ways on.
  condition,

  /// A call of a function with steps: a stack of tiles.
  call,

  /// A body run in copies side by side: a stack of tiles.
  copies,
}

/// The id of the start marker among the nodes of a layout.
const String startMarker = '(start)';

/// The id of the first end marker among the nodes of a layout.
const String endMarker = '(end)';

/// The id of the [n]th end marker among the nodes of a layout, from 1:
/// [endMarker], `(end)2`, `(end)3`.
String endMarkerAt(int n) => n == 1 ? endMarker : '$endMarker$n';

/// The name under the tile of [node]: a step's name, a condition's or
/// copies' label, a call's function with `()`.
String nodeName(GraphNode node, Map<String, GraphFunction> functions) =>
    switch (node) {
      StepNode(:final name) => name,
      ConditionNode(:final label) || CopiesNode(:final label) => label,
      CallNode(functions: final ids) => '${_functionName(ids, functions)}()',
    };

/// The name of the function a call with [ids] goes to: its name in
/// [functions], else the end of its id; the first's, since implementations
/// of a method share its name.
String _functionName(List<String> ids, Map<String, GraphFunction> functions) {
  if (ids.isEmpty) return '';
  final function = functions[ids.first];
  if (function != null) return function.name;
  final name = ids.first.substring(ids.first.indexOf('#') + 1);
  return name.substring(name.lastIndexOf('.') + 1);
}

/// What is written inside the tile of [node], when not an icon: how many
/// steps can run in it ([reachableSteps]). `{ 3 }` on a call, the steps of
/// its function; `{ 1–2 }` for implementations of a method with different
/// counts; `{ ? }` when the file has none of its functions. `{ 3 }` on
/// copies, the steps of one copy; `{ ? }` when they have none but call a
/// function the file does not have. `{ }` when there are none.
String? insideText(GraphNode node, Map<String, GraphFunction> functions) {
  final List<int> counts;
  switch (node) {
    case StepNode() || ConditionNode():
      return null;
    case CopiesNode(:final body):
      counts = [reachableSteps(body, functions)];
      if (counts.single == 0 && _callsUnknown(body, functions)) return '{ ? }';
    case CallNode(functions: final ids):
      counts = [
        for (final id in ids)
          if (functions[id] case final function?)
            reachableSteps(function.body, functions, {id}),
      ]..sort();
      if (counts.isEmpty) return '{ ? }';
  }
  if (counts.last == 0) return '{ }';
  return counts.first == counts.last
      ? '{ ${counts.first} }'
      : '{ ${counts.first}–${counts.last} }';
}

/// Whether [body], or the body of copies in it, calls a function that
/// [functions] does not have: what runs there is not known.
bool _callsUnknown(GraphBody body, Map<String, GraphFunction> functions) =>
    body.nodes.any(
      (node) => switch (node) {
        CallNode(functions: final ids) => !ids.any(functions.containsKey),
        CopiesNode(body: final copy) => _callsUnknown(copy, functions),
        StepNode() || ConditionNode() => false,
      },
    );

/// How many steps can run in [body]: its own, those of the bodies of its
/// copies, and those of the functions it calls that [functions] has — of
/// the one with the most, for a call of several. A function in [counting],
/// being counted already, counts nothing again: a recursive call adds no
/// steps.
int reachableSteps(
  GraphBody body,
  Map<String, GraphFunction> functions, [
  Set<String> counting = const {},
]) {
  var count = 0;
  for (final node in body.nodes) {
    count += switch (node) {
      StepNode() => 1,
      ConditionNode() => 0,
      CopiesNode(body: final copy) => reachableSteps(copy, functions, counting),
      CallNode(functions: final ids) => [
        for (final id in ids)
          if (functions[id] case final function? when !counting.contains(id))
            reachableSteps(function.body, functions, {...counting, id}),
      ].fold(0, math.max),
    };
  }
  return count;
}

/// The most characters of a name under a tile: a longer one is cut, `…`
/// at its end.
const int nameLength = 30;

/// [name] as written under a tile: cut to [nameLength] characters with `…`.
String shortName(String name) => name.runes.length <= nameLength
    ? name
    : '${String.fromCharCodes(name.runes.take(nameLength - 1))}…';

/// What the badge over the stack of copies says until a session tells how
/// many copies there are.
const String copiesBadge = '×n';

/// [place] as written under a tile: the file's name and the line,
/// `review.dart:49`.
String? shortPlace(String? place) =>
    place?.substring(place.lastIndexOf('/') + 1);

/// A node of the graph being laid out.
final class GNode {
  GNode._(
    this.index,
    this.id,
    this.kind, {
    this.node,
    this.name,
    this.fullName,
    this.place,
    this.inside,
  });

  /// The position of the node in the layout's order: the start marker, the
  /// body's nodes, the end markers.
  final int index;

  /// The body node's id, [startMarker], or an end marker's ([endMarkerAt]).
  final String id;

  final NodeKind kind;

  /// The body's node; `null` for a marker.
  final GraphNode? node;

  /// The name under the tile, cut to [nameLength] characters ([shortName]);
  /// `null` for a marker.
  final String? name;

  /// The whole name; `null` for a marker.
  final String? fullName;

  /// The place under the name; `null` for a marker, or when unknown.
  final String? place;

  /// What is written inside the tile instead of an icon.
  final String? inside;

  /// Whether this is the start marker or an end marker.
  bool get isMarker => kind == NodeKind.start || kind == NodeKind.end;

  /// The body of a call or copies expanded in place: the node is its frame.
  FramedBody? framed;

  /// The width of the node's tile, or of its frame.
  double widthOf(LayoutOptions options) => framed?.width ?? options.tile;

  /// The node's exits, in the order their first edges have in the body.
  final List<GExit> exits = [];

  /// Arrows into the node.
  final List<GEdge> inEdges = [];

  /// The layer: the length of the longest forward path from the start.
  int layer = 0;

  /// When the walk of step 1 reached the node.
  int seen = 0;

  /// The node's place in the layout's internal lists of items.
  late final Item item;

  @override
  String toString() => id;
}

/// One exit of a node: a dot, or a capsule for edges side by side.
final class GExit {
  GExit._(this.node, this.index, this.label);

  final GNode node;

  /// The exit's index in [GNode.exits].
  final int index;

  /// The label of its edges; `null` for unlabelled edges.
  final String? label;

  /// One arrow per edge with this label, in the body's order.
  final List<GEdge> edges = [];

  /// Several edges with one label: one capsule, an arrow per edge.
  bool get isCapsule => edges.length > 1;

  @override
  String toString() => '${node.id}.${label ?? 'then'}';
}

/// One arrow: from an exit (and a place in its list) to a node.
final class GEdge {
  GEdge._(this.exit, this.listIndex, this.to, this.index);

  final GExit exit;

  /// The arrow's index among the arrows of its exit.
  final int listIndex;

  final GNode to;

  /// The arrow's position among all arrows in the layout's order.
  final int index;

  GNode get from => exit.node;

  EdgeKind kind = EdgeKind.forward;

  /// When the walk of step 1 looked at the arrow.
  int seen = 0;

  /// The forward pieces between neighbouring layers, left to right.
  final List<Seg> segs = [];

  @override
  String toString() => '$exit[$listIndex]->${to.id}';
}

/// The graph as the layout sees it: nodes, exits and arrows.
final class LayoutGraph {
  LayoutGraph._(this.nodes, this.starts, this.edges, {required this.inFrame});

  /// Builds the layout's view of one level of the graph, [body]: a start
  /// marker the edges `from: null` leave, when there are any; the body's
  /// nodes; an end marker for each edge `to: null`, in the edges' order, so
  /// that each way out of the body ends next to where it leaves. A node's
  /// edges with one label make one exit, in the order of their first
  /// edges. Calls are named after their functions in [functions].
  ///
  /// Edges between nodes the body does not have are left out.
  ///
  /// A body [inFrame] has one end marker, [endMarker], that every edge
  /// `to: null` goes to; step 2 puts it after everything else, and the
  /// start marker before everything else, so that the links from the
  /// frame's sides to them cross nothing.
  factory LayoutGraph.ofBody(
    GraphBody body, {
    Map<String, GraphFunction> functions = const {},
    bool inFrame = false,
  }) {
    final nodes = <GNode>[];
    final byId = <String?, GNode>{};
    GNode add(String id, NodeKind kind, [GraphNode? node]) {
      final name = node == null ? null : nodeName(node, functions);
      final gnode = GNode._(
        nodes.length,
        id,
        kind,
        node: node,
        name: name == null ? null : shortName(name),
        fullName: name,
        place: shortPlace(node?.place),
        inside: switch (kind) {
          NodeKind.start => 'start',
          NodeKind.end => 'end',
          _ => insideText(node!, functions),
        },
      );
      nodes.add(gnode);
      return gnode;
    }

    if (body.edges.any((e) => e.from == null)) {
      byId[null] = add(startMarker, NodeKind.start);
    }
    final known = <String>{};
    for (final node in body.nodes) {
      if (!known.add(node.id)) continue;
      byId[node.id] = add(node.id, switch (node) {
        StepNode() => NodeKind.step,
        ConditionNode() => NodeKind.condition,
        CallNode() => NodeKind.call,
        CopiesNode() => NodeKind.copies,
      }, node);
    }
    final edges = <GEdge>[];
    var ends = 0;
    GNode? end;
    for (final edge in body.edges) {
      final from = byId[edge.from];
      if (from == null) continue;
      final to = edge.to != null
          ? byId[edge.to]
          : inFrame
          ? (end ??= add(endMarker, NodeKind.end))
          : add(endMarkerAt(++ends), NodeKind.end);
      if (to == null) continue;
      var exit = from.exits.where((x) => x.label == edge.label).firstOrNull;
      if (exit == null) {
        exit = GExit._(from, from.exits.length, edge.label);
        from.exits.add(exit);
      }
      final arrow = GEdge._(exit, exit.edges.length, to, edges.length);
      exit.edges.add(arrow);
      to.inEdges.add(arrow);
      edges.add(arrow);
    }
    final start = byId[null];
    return LayoutGraph._(nodes, [?start], edges, inFrame: inFrame);
  }

  /// The nodes in the layout's order: the start marker, the body's nodes,
  /// the end markers.
  final List<GNode> nodes;

  /// The nodes the walk starts from: the start marker, when there is one.
  final List<GNode> starts;

  /// Every arrow, in the body's order.
  final List<GEdge> edges;

  /// Whether the body is in a frame: one end marker, after everything else;
  /// the start marker before everything else.
  final bool inFrame;
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
  String toString() => node?.id ?? 'pass($edge@$layer)';
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
