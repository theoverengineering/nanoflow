import 'dart:math';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_ui/layout/layout.dart';
import 'package:test/test.dart';

import 'support.dart';

/// A random body of up to 12 effects and forks of `true` and `false`, whose
/// ways go forward, back, to their own fork or to the end; a fork lists
/// either first, as describe does: `if` lists `true` first, `a || b`, or an
/// `if` that returns from a `try` with `finally`, `false`.
GraphBody randomForks(int seed) {
  final random = Random(seed);
  final count = 2 + random.nextInt(11);
  final ids = [for (var i = 0; i < count; i++) 'n$i'];
  String? target() =>
      random.nextInt(10) == 0 ? null : ids[random.nextInt(count)];
  final nodes = <GraphNode>[];
  final edges = [GraphEdge(from: null, to: ids.first, label: null)];
  for (final id in ids) {
    final place = 'lib/random.dart:${nodes.length + 1}';
    if (random.nextInt(3) == 0) {
      nodes.add(ConditionNode(id: id, place: place, label: 'decide $id'));
      final labels = random.nextBool() ? ['true', 'false'] : ['false', 'true'];
      for (final label in labels) {
        edges.add(GraphEdge(from: id, to: target(), label: label));
      }
    } else {
      nodes.add(EffectNode(id: id, place: place, name: 'run $id'));
      if (random.nextInt(6) > 0) {
        edges.add(GraphEdge(from: id, to: target(), label: null));
      }
    }
  }
  return GraphBody(nodes: nodes, edges: edges);
}

void main() {
  test('every fork of true and false in the test graphs stands with true '
      'above false', () {
    var forks = 0;
    for (final name in graphNames()) {
      final file = loadGraphFile(name);
      for (final MapEntry(key: id, value: body) in bodiesOf(file).entries) {
        final layout = layoutBody(body, functions: file.functions);
        forks += layout.nodes.keys.where((node) {
          final labels = {
            for (final exit in layout.exits)
              if (exit.node == node) exit.label,
          };
          return labels.length == 2 && labels.containsAll(['true', 'false']);
        }).length;
        expect(falseAbove(layout), isEmpty, reason: '$name $id');
      }
    }
    expect(forks, 268);
  });

  test('a random body with forks lays out the same way every time, every '
      'fork with true above false, keeping step 9', () {
    for (var seed = 0; seed < 300; seed++) {
      final layout = layoutBody(randomForks(seed));
      expect(falseAbove(layout), isEmpty, reason: 'seed $seed');
      expect(
        describe(layoutBody(randomForks(seed))),
        describe(layout),
        reason: 'seed $seed',
      );
      expect(checkLayout(layout), isEmpty, reason: 'seed $seed');
    }
  });

  test('a fork whose true goes back, a node going on under its false: the '
      'back arrow leaves above its false and runs over the graph, crossing '
      'nothing', () {
    final layout = layoutBody(
      bodyOf({
        'start': 'a',
        'nodes': {
          'a': {'command': 'a', 'then': 'c'},
          'c': {
            'decide': 'c',
            'then': {'false': 'd', 'true': 'a'},
          },
          'd': {'command': 'd', 'then': 'e'},
          'e': {'command': 'e', 'then': <String>[]},
        },
      }),
    );
    expect(checkLayout(layout), isEmpty);
    expect(falseAbove(layout), isEmpty);
    expect(countCrossings(layout), 0);
    final back = layout.edges.singleWhere((e) => e.from == 'c' && e.to == 'a');
    expect(back.kind, EdgeKind.back);
    final top = layout.nodes.values.map((n) => n.marks.top).reduce(min);
    expect(back.points.map((p) => p.y).reduce(min), lessThan(top));
  });

  test('a fork whose false comes back to it: the loop goes under its tile, '
      'true over it', () {
    GraphLayout lay(String looping) => layoutBody(
      bodyOf({
        'start': 'c',
        'nodes': {
          'c': {
            'decide': 'c',
            'then': {
              looping: 'c',
              if (looping == 'true') 'false': 'd' else 'true': 'd',
            },
          },
          'd': {'command': 'd', 'then': <String>[]},
        },
      }),
    );
    for (final looping in ['true', 'false']) {
      final layout = lay(looping);
      expect(checkLayout(layout), isEmpty, reason: looping);
      expect(falseAbove(layout), isEmpty, reason: looping);
      final tile = layout.nodes['c']!.tile;
      final loop = layout.edges.singleWhere((e) => e.kind == EdgeKind.loop);
      final ys = loop.points.map((p) => p.y);
      if (looping == 'true') {
        expect(ys.reduce(min), lessThan(tile.top));
      } else {
        expect(ys.reduce(max), greaterThan(tile.bottom));
      }
    }
  });

  test('!ok in publish: its true goes up to rollback, though the end its '
      'false goes to would stand nearer over rollback than under it', () {
    final layout = layoutOf('release', 'publish');
    expect(falseAbove(layout), isEmpty);
    expect(checkLayout(layout), isEmpty);
    expect(countCrossings(layout), 0);
  });
}
