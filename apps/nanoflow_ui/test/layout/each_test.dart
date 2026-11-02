import 'dart:math';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_ui/layout/layout.dart';
import 'package:nanoflow_ui/layout/layout_graph.dart'
    show tagChipWidth, tagSpacing, tagStraight;
import 'package:test/test.dart';

import 'random_graphs_test.dart' show randomBody;

/// Arrows that run their node once per item (docs/superpowers/specs/
/// 2026-10-29-each-edge-design.md) or whose call has a limit (2026-11-02-
/// call-limit-design.md): the tag `each`, `≤N` or both before the head.
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
    expect(copies.tag, 'each');
    final chip = copies.tagRect!;
    final base = copies.points.last;
    expect(chip.right, closeTo(base.x - tagSpacing, 1e-6));
    expect(chip.bottom, lessThan(base.y));
    expect(chip.bottom, greaterThan(base.y - o.chipHeight));
    expect(chip.height, o.chipHeight);
    final last = copies.points[copies.points.length - 2];
    expect(base.x - last.x, greaterThanOrEqualTo(tagStraight('each', o)));
    expect(tagStraight('each', o), greaterThan(o.minInputStraight));
    for (final edge in layout.edges.where((e) => e.to != 'compress')) {
      expect(edge.each, isNull);
      expect(edge.tag, isNull);
      expect(edge.tagRect, isNull);
    }
    expect(checkLayout(layout), isEmpty);
  });

  test('an arrow says each, ≤N for the limit of its call — ≤… for a limit '
      'computed —, or both', () {
    expect(arrowTag(), isNull);
    expect(arrowTag(each: header), 'each');
    expect(arrowTag(limit: '2'), '≤2');
    expect(arrowTag(each: header, limit: '2'), 'each ≤2');
    expect(arrowTag(each: header, limit: 'night.parallel'), 'each ≤…');
    expect(arrowTag(limit: 'n + 1'), '≤…');
  });

  test('the tag of an arrow whose call has a limit is as wide as its text, '
      'ends a tag spacing before its head, and its straight piece has room '
      'for it', () {
    final limited = GraphBody(
      nodes: generate.nodes,
      edges: [
        for (final edge in generate.edges)
          switch (edge.to) {
            'compress' => GraphEdge(
              from: edge.from,
              to: edge.to,
              label: edge.label,
              each: header,
              limit: 'picked.parallel',
            ),
            'save' => GraphEdge(
              from: edge.from,
              to: edge.to,
              label: edge.label,
              limit: '2',
            ),
            _ => edge,
          },
      ],
    );
    final layout = layoutBody(limited);
    final o = layout.options;
    for (final (to, tag) in [('compress', 'each ≤…'), ('save', '≤2')]) {
      final edge = layout.edges.singleWhere((e) => e.to == to);
      expect(edge.tag, tag);
      final chip = edge.tagRect!;
      final base = edge.points.last;
      expect(chip.width, closeTo(tagChipWidth(tag, o), 1e-6));
      expect(chip.right, closeTo(base.x - tagSpacing, 1e-6));
      final last = edge.points[edge.points.length - 2];
      expect(base.x - last.x, greaterThanOrEqualTo(tagStraight(tag, o)));
    }
    expect(layout.edges.singleWhere((e) => e.to == 'save').limit, '2');
    expect(tagStraight('each ≤…', o), greaterThan(tagStraight('each', o)));
    expect(checkLayout(layout), isEmpty);
  });

  for (final (what, tagged) in [
    ('each', const GraphEdge(from: 'b', to: 'join', label: null, each: 'x')),
    ('≤2', const GraphEdge(from: 'b', to: 'join', label: null, limit: '2')),
  ]) {
    test('an input with the tag $what is a tag gap under the input over it; '
        'the others are a port gap apart', () {
      // a, b and c go into join; b runs it once per item, or with a limit.
      final body = GraphBody(
        nodes: const [
          EffectNode(id: 'split', place: 'lib/j.dart:1', name: 'split'),
          EffectNode(id: 'a', place: 'lib/j.dart:2', name: 'a'),
          EffectNode(id: 'b', place: 'lib/j.dart:3', name: 'b'),
          EffectNode(id: 'c', place: 'lib/j.dart:4', name: 'c'),
          EffectNode(id: 'join', place: 'lib/j.dart:5', name: 'join'),
        ],
        edges: [
          const GraphEdge(from: null, to: 'split', label: null),
          const GraphEdge(from: 'split', to: 'a', label: null),
          const GraphEdge(from: 'split', to: 'b', label: null),
          const GraphEdge(from: 'split', to: 'c', label: null),
          const GraphEdge(from: 'a', to: 'join', label: null),
          tagged,
          const GraphEdge(from: 'c', to: 'join', label: null),
          const GraphEdge(from: 'join', to: null, label: null),
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
          closeTo(into[inputs[i]]!.tag == null ? o.portGap : o.tagGap, 1e-6),
        );
      }
      expect(into.values.where((e) => e.tagRect != null), hasLength(1));
      expect(checkLayout(layout), isEmpty);
    });
  }

  test('any body with arrows that run their nodes once per item or whose '
      'calls have limits lays out keeping step 9 but for loops in '
      'capsules', () {
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
                    each: random.nextBool() ? 'for x in xs' : null,
                    limit: switch (random.nextInt(3)) {
                      0 => '2',
                      1 => 'night.parallel',
                      _ => null,
                    },
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
