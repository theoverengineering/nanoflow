import 'package:nanoflow_ui/layout/cycles.dart';
import 'package:nanoflow_ui/layout/layers.dart';
import 'package:nanoflow_ui/layout/layout_graph.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  LayoutGraph layered(Map<String, Object?> json) {
    final graph = LayoutGraph.of(graphOf(json));
    findBackEdges(graph);
    assignLayers(graph);
    return graph;
  }

  Map<String, int> layers(LayoutGraph graph) => {
    for (final node in graph.nodes) node.name: node.layer,
  };

  test('a node\'s layer is the longest forward path to it; back arrows do '
      'not count', () {
    final graph = layered({
      'start': 'a',
      'nodes': {
        'a': {
          'decide': 'a',
          'then': {'long': 'b', 'short': 'd'},
        },
        'b': {'command': 'b', 'then': 'c'},
        'c': {'command': 'c', 'then': 'd'},
        'd': {'decide': 'd', 'then': 'e', 'else': 'a'},
        'e': {'command': 'e'},
      },
    });
    expect(layers(graph), {'a': 0, 'b': 1, 'c': 2, 'd': 3, 'e': 4});
  });

  test('a start node another start leads to takes the layer after it', () {
    final graph = layered({
      'start': ['a', 'b'],
      'nodes': {
        'a': {'command': 'a', 'then': 'b'},
        'b': {'command': 'b', 'then': 'c'},
        'c': {'command': 'c'},
      },
    });
    expect(layers(graph), {'a': 0, 'b': 1, 'c': 2});
  });

  test('start nodes and nodes nothing forward reaches are layer 0', () {
    final graph = layered({
      'start': ['a', 'b'],
      'nodes': {
        'a': {'command': 'a', 'then': 'c'},
        'b': {'command': 'b', 'then': 'c'},
        'c': {'command': 'c', 'then': 'a'},
      },
    });
    expect(layers(graph), {'a': 0, 'b': 0, 'c': 1});
  });

  test('a long arrow gets a pass point in every layer it crosses', () {
    final graph = layered({
      'start': 'a',
      'nodes': {
        'a': {
          'decide': 'a',
          'then': {'far': 'd', 'near': 'b'},
        },
        'b': {'command': 'b', 'then': 'c'},
        'c': {'command': 'c', 'then': 'd'},
        'd': {'command': 'd'},
      },
    });
    final items = buildLayers(graph);
    String name(Item item) => item.isPass ? 'pass' : item.node!.name;
    // The walk looks at a's arrow to d before it reaches b.
    expect(
      [for (final layer in items) layer.map(name).toList()],
      [
        ['a'],
        ['pass', 'b'],
        ['pass', 'c'],
        ['d'],
      ],
    );
    final far = graph.edges.first;
    expect(far.segs.map((s) => '${name(s.from)}->${name(s.to)}'), [
      'a->pass',
      'pass->pass',
      'pass->d',
    ]);
  });
}
