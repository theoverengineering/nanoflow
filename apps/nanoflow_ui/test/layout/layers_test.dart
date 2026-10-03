import 'package:nanoflow_ui/layout/cycles.dart';
import 'package:nanoflow_ui/layout/layers.dart';
import 'package:nanoflow_ui/layout/layout_graph.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  LayoutGraph layered(Map<String, Object?> json) {
    final graph = LayoutGraph.ofBody(bodyOf(json));
    findBackEdges(graph);
    assignLayers(graph);
    return graph;
  }

  Map<String, int> layers(LayoutGraph graph) => {
    for (final node in graph.nodes) node.id: node.layer,
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
        'e': {'command': 'e', 'then': <String>[]},
      },
    });
    expect(layers(graph), {
      startMarker: 0,
      'a': 1,
      'b': 2,
      'c': 3,
      'd': 4,
      'e': 5,
      endMarker: 6,
    });
  });

  test('a node the start and another node both lead to takes the layer '
      'after that node', () {
    final graph = layered({
      'start': ['a', 'b'],
      'nodes': {
        'a': {'command': 'a', 'then': 'b'},
        'b': {'command': 'b', 'then': 'c'},
        'c': {'command': 'c'},
      },
    });
    expect(layers(graph), {startMarker: 0, 'a': 1, 'b': 2, 'c': 3});
  });

  test('the start marker and nodes nothing forward reaches are layer 0', () {
    final graph = layered({
      'start': 'a',
      'nodes': {
        'a': {'command': 'a', 'then': 'c'},
        'lost': {'command': 'lost', 'then': 'c'},
        'c': {'command': 'c', 'then': 'a'},
      },
    });
    expect(layers(graph), {startMarker: 0, 'a': 1, 'lost': 0, 'c': 2});
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
    String name(Item item) => item.isPass ? 'pass' : item.node!.id;
    // The walk looks at a's arrow to d before it reaches b.
    expect(
      [for (final layer in items) layer.map(name).toList()],
      [
        [startMarker],
        ['a'],
        ['pass', 'b'],
        ['pass', 'c'],
        ['d'],
      ],
    );
    final far = graph.edges[1];
    expect(far.segs.map((s) => '${name(s.from)}->${name(s.to)}'), [
      'a->pass',
      'pass->pass',
      'pass->d',
    ]);
  });
}
