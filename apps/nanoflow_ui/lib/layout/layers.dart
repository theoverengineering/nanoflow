import 'layout_graph.dart';

/// Step 2: puts every node in the layer of the longest forward path to it.
///
/// Nodes with no forward arrow into them — the start marker among them — are
/// layer 0, so every forward arrow goes right. In a body in a frame
/// ([LayoutGraph.inFrame]) the start marker is alone in layer 0 — other
/// nodes nothing leads to are layer 1 — and the one end marker goes after
/// every other node, alone in the last layer. Sets [GNode.layer].
void assignLayers(LayoutGraph graph) {
  final done = <GNode>{};
  final start = graph.starts.firstOrNull;
  final first = graph.inFrame && start != null ? 1 : 0;
  int layerOf(GNode node) {
    if (done.contains(node)) return node.layer;
    var layer = node == start ? 0 : first;
    for (final edge in node.inEdges) {
      if (edge.kind != EdgeKind.forward) continue;
      final before = layerOf(edge.from) + 1;
      if (before > layer) layer = before;
    }
    node.layer = layer;
    done.add(node);
    return layer;
  }

  for (final node in graph.nodes) {
    layerOf(node);
  }
  // The one end of a body in a frame comes after everything else: alone in
  // the last layer, nothing between it and the frame's right side.
  if (graph.inFrame) {
    final end = graph.nodes.where((n) => n.kind == NodeKind.end).firstOrNull;
    if (end == null) return;
    for (final node in graph.nodes) {
      if (node != end && node.layer >= end.layer) end.layer = node.layer + 1;
    }
  }
}

/// Step 3: the layers' items, a pass point in every layer a long forward
/// arrow crosses, and the forward pieces between neighbouring layers.
///
/// Each layer is in the order of step 1's walk: a node where the walk reached
/// it, a pass point where the walk looked at its arrow.
List<List<Item>> buildLayers(LayoutGraph graph) {
  final count = graph.nodes.fold(0, (m, n) => n.layer > m ? n.layer : m) + 1;
  final layers = [for (var i = 0; i < count; i++) <Item>[]];
  final when = <Item, int>{};
  for (final node in graph.nodes) {
    node.item = Item.node(node);
    layers[node.layer].add(node.item);
    when[node.item] = node.seen;
  }
  for (final edge in graph.edges) {
    if (edge.kind != EdgeKind.forward) continue;
    var from = edge.from.item;
    for (var layer = edge.from.layer + 1; layer < edge.to.layer; layer++) {
      final pass = Item.pass(edge, layer);
      layers[layer].add(pass);
      when[pass] = edge.seen;
      _link(edge, from, pass);
      from = pass;
    }
    _link(edge, from, edge.to.item);
  }
  for (final layer in layers) {
    layer.sort((a, b) => when[a]!.compareTo(when[b]!));
    for (var i = 0; i < layer.length; i++) {
      layer[i].order = i;
    }
  }
  return layers;
}

void _link(GEdge edge, Item from, Item to) {
  final seg = Seg(edge, from, to);
  edge.segs.add(seg);
  from.outs.add(seg);
  to.ins.add(seg);
}
