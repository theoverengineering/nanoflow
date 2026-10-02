import 'dart:math';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_ui/layout/layout.dart';
import 'package:test/test.dart';

import 'support.dart';

/// A random graph of up to 12 nodes: workers and forks, single, list and
/// empty targets, loops, several starts, nodes nothing reaches.
Graph randomGraph(int seed) {
  final random = Random(seed);
  final count = 1 + random.nextInt(12);
  final names = [for (var i = 0; i < count; i++) 'n$i'];
  String any() => names[random.nextInt(count)];
  Object target() => switch (random.nextInt(10)) {
    0 => <String>[],
    1 => {for (var i = 0; i < 3; i++) any()}.toList(),
    _ => any(),
  };
  return graphOf({
    'start': random.nextInt(4) == 0 ? {any(), any()}.toList() : names.first,
    'nodes': {
      for (final name in names)
        name: random.nextBool()
            ? {
                'command': 'run $name',
                if (random.nextInt(5) > 0) 'then': target(),
              }
            : {
                'decide': 'decide $name',
                'then': random.nextBool()
                    ? target()
                    : {
                        for (var i = 0; i < 1 + random.nextInt(5); i++)
                          'k$i': target(),
                      },
                if (random.nextBool()) 'else': target(),
              },
    },
  });
}

void main() {
  test('any graph lays out, the same way every time', () {
    for (var seed = 0; seed < 150; seed++) {
      final graph = randomGraph(seed);
      final layout = layoutGraph(graph);
      expect(layout.nodes.keys, graph.nodes.keys, reason: 'seed $seed');
      expect(
        describe(layoutGraph(graph)),
        describe(layout),
        reason: 'seed $seed',
      );
    }
  });

  test('a graph with no nodes lays out empty', () {
    final layout = layoutGraph(graphOf({'start': [], 'nodes': {}}));
    expect(layout.nodes, isEmpty);
    expect(layout.bounds.width, 0);
  });

  test('targets that name no node are left out', () {
    final layout = layoutGraph(
      graphOf({
        'start': 'a',
        'nodes': {
          'a': {'command': 'a', 'then': 'missing'},
        },
      }),
    );
    expect(layout.edges, isEmpty);
    expect(layout.exits.single.shape, ExitShape.stub);
  });
}
