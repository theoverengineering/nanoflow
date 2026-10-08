import 'layout_graph.dart';

/// Step 1: finds loops and back arrows, and returns the nodes in the order
/// the walk reached them.
///
/// An arrow into its own node is a loop. An arrow that lies on a cycle — its
/// nodes are in one strongly connected component — and goes into a node the
/// body lists before its own is a back arrow; every other arrow is forward.
/// So a node stands where the code has it: `stage = X; continue` back to a
/// case earlier in the code is a back arrow, however the walk would reach X
/// first. Within a cycle every forward arrow then goes on in the body's
/// order, so the forward arrows make no cycle.
///
/// The walk, for the order of nodes within a layer, goes depth first from the
/// start marker along forward arrows, through each node's exits in order (and
/// each capsule's arrows in order) — a fork's `true` before its `false`
/// ([GNode.fork]), whichever the body lists first, so that the layers start
/// with the way of `true` above. Nodes the walk from the start does not reach
/// are walked from afterwards, in the layout's order, so that every node is
/// placed.
///
/// Sets [GEdge.kind], and [GNode.seen] and [GEdge.seen] on one clock.
List<GNode> findBackEdges(LayoutGraph graph) {
  // Which arrows are back: a walk that takes each node's arrows by where
  // their nodes stand in the body, so that a cycle is entered at the node
  // the code has first.
  final onStack = <GNode>{};
  final classified = <GNode>{};
  void classify(GNode node) {
    classified.add(node);
    onStack.add(node);
    final arrows = [for (final exit in node.exits) ...exit.edges]
      ..sort((a, b) => a.to.index.compareTo(b.to.index));
    for (final edge in arrows) {
      if (edge.to == node) {
        edge.kind = EdgeKind.loop;
      } else if (onStack.contains(edge.to)) {
        edge.kind = EdgeKind.back;
      } else {
        edge.kind = EdgeKind.forward;
        if (!classified.contains(edge.to)) classify(edge.to);
      }
    }
    onStack.remove(node);
  }

  for (final node in graph.starts) {
    if (!classified.contains(node)) classify(node);
  }
  for (final node in graph.nodes) {
    if (!classified.contains(node)) classify(node);
  }

  final reached = <GNode>{};
  final order = <GNode>[];
  var clock = 0;

  void walk(GNode node) {
    node.seen = clock++;
    reached.add(node);
    order.add(node);
    final exits = switch (node.fork) {
      (:final yes, :final no) => [yes, no],
      null => node.exits,
    };
    for (final exit in exits) {
      for (final edge in exit.edges) {
        edge.seen = clock++;
        if (edge.kind == EdgeKind.forward && !reached.contains(edge.to)) {
          walk(edge.to);
        }
      }
    }
  }

  for (final node in graph.starts) {
    if (!reached.contains(node)) walk(node);
  }
  for (final node in graph.nodes) {
    if (!reached.contains(node)) walk(node);
  }
  return order;
}
