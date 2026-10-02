import 'layout_graph.dart';

/// Step 1: finds loops and back arrows, and returns the nodes in the order
/// the walk reached them.
///
/// The walk goes depth first from the `start` nodes in their order, through
/// each node's exits in declaration order (and each list in its order). An
/// arrow into a node that is on the walk's stack is a back arrow; an arrow
/// into its own node is a loop; every other arrow is forward. Nodes no walk
/// from `start` reaches are walked from afterwards, in declaration order, so
/// that every node is placed.
///
/// Sets [GEdge.kind], and [GNode.seen] and [GEdge.seen] on one clock.
List<GNode> findBackEdges(LayoutGraph graph) {
  final onStack = <GNode>{};
  final reached = <GNode>{};
  final order = <GNode>[];
  var clock = 0;

  void walk(GNode node) {
    node.seen = clock++;
    reached.add(node);
    onStack.add(node);
    order.add(node);
    for (final exit in node.exits) {
      for (final edge in exit.edges) {
        edge.seen = clock++;
        if (edge.to == node) {
          edge.kind = EdgeKind.loop;
        } else if (onStack.contains(edge.to)) {
          edge.kind = EdgeKind.back;
        } else {
          edge.kind = EdgeKind.forward;
          if (!reached.contains(edge.to)) walk(edge.to);
        }
      }
    }
    onStack.remove(node);
  }

  for (final node in graph.starts) {
    if (!reached.contains(node)) walk(node);
  }
  for (final node in graph.nodes) {
    if (!reached.contains(node)) walk(node);
  }
  return order;
}
