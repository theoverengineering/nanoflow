import 'dart:math';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_ui/layout/layout.dart';
import 'package:test/test.dart';

import 'support.dart';

/// A random body of up to 12 nodes of every kind: edges to one node, side by
/// side to several, to the end; labelled edges out of conditions; loops,
/// several edges from the start, nodes nothing reaches.
GraphBody randomBody(int seed) {
  final random = Random(seed);
  final count = 1 + random.nextInt(12);
  final ids = [for (var i = 0; i < count; i++) 'n$i'];
  String any() => ids[random.nextInt(count)];
  List<String?> targets() => switch (random.nextInt(10)) {
    0 => [null],
    1 => {for (var i = 0; i < 3; i++) any()}.toList(),
    _ => [any()],
  };
  final nodes = <GraphNode>[];
  final edges = <GraphEdge>[
    for (final to in random.nextInt(4) == 0 ? targets() : [ids.first])
      GraphEdge(from: null, to: to, label: null),
  ];
  void edgesTo(String from, String? label) {
    for (final to in targets()) {
      edges.add(GraphEdge(from: from, to: to, label: label));
    }
  }

  for (final id in ids) {
    final place = 'lib/random.dart:${nodes.length + 1}';
    switch (random.nextInt(4)) {
      case 0:
        nodes.add(ConditionNode(id: id, place: place, label: 'decide $id'));
        for (var i = 0; i < 1 + random.nextInt(5); i++) {
          edgesTo(id, 'k$i');
        }
      case final kind:
        nodes.add(switch (kind) {
          1 => EffectNode(id: id, place: place, name: 'run $id'),
          2 => CallNode(id: id, place: place, functions: ['lib/f.dart#f$id']),
          _ => CopiesNode(
            id: id,
            place: place,
            label: 'x in $id',
            body: const GraphBody(nodes: [], edges: []),
          ),
        });
        if (random.nextInt(5) > 0) edgesTo(id, null);
    }
  }
  return GraphBody(nodes: nodes, edges: edges);
}

void main() {
  test('any body lays out, the same way every time, keeping step 9 but for '
      'loops in capsules', () {
    for (var seed = 0; seed < 150; seed++) {
      final body = randomBody(seed);
      final layout = layoutBody(body);
      final ends = body.edges.where((e) => e.to == null).length;
      expect(layout.nodes.keys, [
        startMarker,
        for (final node in body.nodes) node.id,
        for (var n = 1; n <= ends; n++) endMarkerAt(n),
      ], reason: 'seed $seed');
      expect(
        describe(layoutBody(body)),
        describe(layout),
        reason: 'seed $seed',
      );
      // A loop in a capsule with other arrows can cross them
      // (docs/graph-layout.md, step 9); every other rule holds.
      expect(
        checkLayout(layout).where((p) => !p.contains('loop crosses')),
        isEmpty,
        reason: 'seed $seed',
      );
    }
  });

  test('a body with no nodes and no edges lays out empty', () {
    final layout = layoutBody(const GraphBody(nodes: [], edges: []));
    expect(layout.nodes, isEmpty);
    expect(layout.bounds.width, 0);
  });

  test('edges between nodes the body does not have are left out', () {
    final layout = layoutBody(
      const GraphBody(
        nodes: [EffectNode(id: 'a', place: null, name: 'a')],
        edges: [
          GraphEdge(from: null, to: 'a', label: null),
          GraphEdge(from: 'a', to: 'missing', label: null),
          GraphEdge(from: 'missing', to: null, label: null),
        ],
      ),
    );
    expect(layout.nodes.keys, [startMarker, 'a']);
    expect(layout.edges.single.to, 'a');
    expect(layout.exits.single.node, startMarker);
  });

  test('an arrow knows the edge it draws by its index in the body, the '
      'edges left out counted', () {
    final layout = layoutBody(
      const GraphBody(
        nodes: [EffectNode(id: 'a', place: null, name: 'a')],
        edges: [
          GraphEdge(from: 'missing', to: 'a', label: null),
          GraphEdge(from: null, to: 'a', label: null),
          GraphEdge(from: 'a', to: null, label: null),
        ],
      ),
    );
    expect([for (final edge in layout.edges) edge.edgeIndex], [1, 2]);
  });

  test('of two nodes with one id the first is laid out', () {
    final layout = layoutBody(
      const GraphBody(
        nodes: [
          EffectNode(id: 'a', place: null, name: 'first'),
          EffectNode(id: 'a', place: null, name: 'second'),
        ],
        edges: [GraphEdge(from: null, to: 'a', label: null)],
      ),
    );
    expect(layout.nodes.keys, [startMarker, 'a']);
    expect(layout.nodes['a']!.name, 'first');
  });
}
