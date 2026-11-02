import 'dart:math';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_ui/layout/layout.dart';
import 'package:nanoflow_ui/layout/layout_graph.dart' show LayoutGraph;
import 'package:test/test.dart';

import 'random_graphs_test.dart' show randomBody;

/// The failure route of a node (docs/superpowers/specs/
/// 2026-11-02-failure-route-design.md): its edges leave the node by an exit
/// labelled `failed` of their own.
void main() {
  /// claim → develop() → (settle, or giveBack when develop fails); develop's
  /// switch has a case `failed` too, which leads to retry.
  final night = GraphBody(
    nodes: const [
      EffectNode(id: 'claim', place: 'lib/n.dart:1', name: 'claim'),
      CallNode(id: 'develop', place: 'lib/n.dart:2', functions: ['d']),
      EffectNode(id: 'settle', place: 'lib/n.dart:3', name: 'settle'),
      EffectNode(id: 'giveBack', place: 'lib/n.dart:4', name: 'giveBack'),
      EffectNode(id: 'retry', place: 'lib/n.dart:5', name: 'retry'),
    ],
    edges: const [
      GraphEdge(from: null, to: 'claim', label: null),
      GraphEdge(from: 'claim', to: 'develop', label: null),
      GraphEdge(from: 'develop', to: 'settle', label: 'done'),
      GraphEdge(from: 'develop', to: 'retry', label: 'failed'),
      GraphEdge(from: 'develop', to: 'giveBack', label: 'failed', failed: true),
      GraphEdge(from: 'settle', to: null, label: null),
      GraphEdge(from: 'giveBack', to: null, label: null),
      GraphEdge(from: 'retry', to: 'claim', label: null),
    ],
  );

  test('a failure route leaves its node by an exit labelled failed, apart '
      'from a case of the same text', () {
    final graph = LayoutGraph.ofBody(night);
    final develop = graph.nodes.singleWhere((n) => n.id == 'develop');
    expect(
      [for (final exit in develop.exits) exit.label],
      ['done', 'failed', 'failed'],
    );
    expect(
      [for (final exit in develop.exits) exit.failed],
      [false, false, true],
    );
    expect(develop.exits.last.edges.single.to.id, 'giveBack');
    final layout = layoutBody(night);
    expect(
      [
        for (final exit in layout.exits)
          if (exit.node == 'develop') exit.label,
      ],
      ['done', 'failed', 'failed'],
    );
    expect(checkLayout(layout), isEmpty);
  });

  test('a node with a route and a failure route has an exit without a label '
      'and one labelled failed', () {
    final body = GraphBody(
      nodes: night.nodes,
      edges: const [
        GraphEdge(from: null, to: 'claim', label: null),
        GraphEdge(from: 'claim', to: 'develop', label: null),
        GraphEdge(from: 'develop', to: 'settle', label: null),
        GraphEdge(
          from: 'develop',
          to: 'giveBack',
          label: 'failed',
          failed: true,
        ),
        GraphEdge(from: 'develop', to: 'retry', label: 'failed', failed: true),
        GraphEdge(from: 'settle', to: null, label: null),
        GraphEdge(from: 'giveBack', to: null, label: null),
        GraphEdge(from: 'retry', to: null, label: null),
      ],
    );
    final layout = layoutBody(body);
    final exits = [
      for (final exit in layout.exits)
        if (exit.node == 'develop') exit,
    ];
    expect([for (final exit in exits) exit.label], [null, 'failed']);
    // The failure route's set: one capsule, an arrow per edge.
    expect(exits.last.shape, ExitShape.capsule);
    expect(checkLayout(layout), isEmpty);
  });

  test('any body with failure routes lays out keeping step 9 but for loops '
      'in capsules', () {
    for (var seed = 0; seed < 150; seed++) {
      final random = Random(seed);
      final body = randomBody(seed);
      final routed = GraphBody(
        nodes: body.nodes,
        edges: [
          ...body.edges,
          for (final node in body.nodes)
            if (node is! ConditionNode && random.nextInt(3) == 0)
              GraphEdge(
                from: node.id,
                to: random.nextInt(4) == 0
                    ? null
                    : body.nodes[random.nextInt(body.nodes.length)].id,
                label: 'failed',
                failed: true,
              ),
        ],
      );
      final layout = layoutBody(routed);
      expect(
        checkLayout(layout).where((p) => !p.contains('loop crosses')),
        isEmpty,
        reason: 'seed $seed',
      );
    }
  });
}
