import 'dart:math';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_ui/layout/layout.dart';
import 'package:nanoflow_ui/layout/layout_graph.dart'
    show eachSpacing, eachStraight;
import 'package:test/test.dart';

import 'random_graphs_test.dart' show randomBody;

/// Arrows that run their node once per item (docs/superpowers/specs/
/// 2026-10-29-each-edge-design.md): the label `each` before the head.
void main() {
  const header = 'for (var i = 0; i < picked.picks.length; i++)';

  /// generateIdeas: critique ends nothing when it picked nothing, else
  /// compresses each pick, and saves each.
  final generate = GraphBody(
    nodes: const [
      EffectNode(id: 'critique', place: 'lib/g.dart:1', name: 'critique'),
      EffectNode(id: 'nothing', place: 'lib/g.dart:2', name: 'nothing'),
      CallNode(id: 'compress', place: 'lib/g.dart:3', functions: ['c']),
      EffectNode(id: 'save', place: 'lib/g.dart:4', name: 'save'),
    ],
    edges: const [
      GraphEdge(from: null, to: 'critique', label: null),
      GraphEdge(from: 'critique', to: 'nothing', label: 'picked.picks.isEmpty'),
      GraphEdge(from: 'critique', to: 'compress', label: 'else', each: header),
      GraphEdge(from: 'nothing', to: null, label: null),
      GraphEdge(from: 'compress', to: 'save', label: null),
      GraphEdge(from: 'save', to: null, label: null),
    ],
  );

  test('an arrow that runs its node once per item has the label each over '
      'its last straight piece, ending an each spacing before its head, '
      'and the straight piece has room for it', () {
    final layout = layoutBody(generate);
    final o = layout.options;
    final copies = layout.edges.singleWhere((e) => e.to == 'compress');
    expect(copies.each, header);
    final chip = copies.eachRect!;
    final base = copies.points.last;
    expect(chip.right, closeTo(base.x - eachSpacing, 1e-6));
    expect(chip.bottom, lessThan(base.y));
    expect(chip.bottom, greaterThan(base.y - o.chipHeight));
    expect(chip.height, o.chipHeight);
    final last = copies.points[copies.points.length - 2];
    expect(base.x - last.x, greaterThanOrEqualTo(eachStraight(o)));
    expect(eachStraight(o), greaterThan(o.minInputStraight));
    for (final edge in layout.edges.where((e) => e.to != 'compress')) {
      expect(edge.each, isNull);
      expect(edge.eachRect, isNull);
    }
    expect(checkLayout(layout), isEmpty);
  });

  test('an input with the label each is an each gap under the input over '
      'it; the others are a port gap apart', () {
    // a, b and c go into join; b runs it once per item.
    final body = GraphBody(
      nodes: const [
        EffectNode(id: 'split', place: 'lib/j.dart:1', name: 'split'),
        EffectNode(id: 'a', place: 'lib/j.dart:2', name: 'a'),
        EffectNode(id: 'b', place: 'lib/j.dart:3', name: 'b'),
        EffectNode(id: 'c', place: 'lib/j.dart:4', name: 'c'),
        EffectNode(id: 'join', place: 'lib/j.dart:5', name: 'join'),
      ],
      edges: const [
        GraphEdge(from: null, to: 'split', label: null),
        GraphEdge(from: 'split', to: 'a', label: null),
        GraphEdge(from: 'split', to: 'b', label: null),
        GraphEdge(from: 'split', to: 'c', label: null),
        GraphEdge(from: 'a', to: 'join', label: null),
        GraphEdge(from: 'b', to: 'join', label: null, each: 'for x in xs'),
        GraphEdge(from: 'c', to: 'join', label: null),
        GraphEdge(from: 'join', to: null, label: null),
      ],
    );
    final layout = layoutBody(body);
    final o = layout.options;
    final inputs = layout.nodes['join']!.bar!.inputs;
    final into = {
      for (final edge in layout.edges.where((e) => e.to == 'join'))
        edge.points.last.y: edge,
    };
    for (var i = 1; i < inputs.length; i++) {
      expect(
        inputs[i] - inputs[i - 1],
        closeTo(into[inputs[i]]!.each == null ? o.portGap : o.eachGap, 1e-6),
      );
    }
    expect(into.values.where((e) => e.eachRect != null), hasLength(1));
    expect(checkLayout(layout), isEmpty);
  });

  test('any body with arrows that run their nodes once per item lays out '
      'keeping step 9 but for loops in capsules', () {
    for (var seed = 0; seed < 150; seed++) {
      final random = Random(seed);
      final body = randomBody(seed);
      final copies = GraphBody(
        nodes: body.nodes,
        edges: [
          for (final edge in body.edges)
            edge.to != null && random.nextInt(3) == 0
                ? GraphEdge(
                    from: edge.from,
                    to: edge.to,
                    label: edge.label,
                    each: 'for x in xs',
                  )
                : edge,
        ],
      );
      final layout = layoutBody(copies);
      expect(
        checkLayout(layout).where((p) => !p.contains('loop crosses')),
        isEmpty,
        reason: 'seed $seed',
      );
    }
  });
}
