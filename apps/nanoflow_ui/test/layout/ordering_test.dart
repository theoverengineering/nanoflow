import 'package:nanoflow_ui/layout/coordinates.dart';
import 'package:nanoflow_ui/layout/cycles.dart';
import 'package:nanoflow_ui/layout/layers.dart';
import 'package:nanoflow_ui/layout/layout.dart';
import 'package:nanoflow_ui/layout/layout_graph.dart';
import 'package:nanoflow_ui/layout/ordering.dart';
import 'package:nanoflow_ui/layout/ports.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  // The walk reaches v (from t) before w, but x, above y, leads to w.
  final crossed = graphOf({
    'start': ['t', 's'],
    'nodes': {
      't': {'command': 't', 'then': 'v'},
      's': {
        'decide': 's',
        'then': {'one': 'x', 'two': 'y'},
      },
      'x': {'command': 'x', 'then': 'w'},
      'y': {'command': 'y', 'then': 'v'},
      'v': {'command': 'v'},
      'w': {'command': 'w'},
    },
  });

  test('the walk\'s order alone would cross', () {
    final graph = LayoutGraph.of(crossed);
    findBackEdges(graph);
    assignLayers(graph);
    final layers = buildLayers(graph);
    expect(layers[2].map((i) => i.node!.name), ['v', 'w']);
    expect(layers[1].map((i) => i.node?.name), [null, 'x', 'y']);
  });

  test('sweeps by medians reorder the layers so that nothing crosses', () {
    const options = LayoutOptions();
    final graph = LayoutGraph.of(crossed);
    findBackEdges(graph);
    assignLayers(graph);
    final layers = buildLayers(graph);
    int crossings() {
      final ports = assignPorts(graph, options, below: {}, backLevels: {});
      stackLayers(layers, ports, options);
      return countLayerCrossings(graph, layers, ports, 1e6);
    }

    expect(crossings(), greaterThan(0));
    orderLayers(graph, layers, options);
    expect(crossings(), 0);
    String name(Item item) => item.node?.name ?? 'pass';
    expect(layers[1].map(name), ['x', 'y', 'pass']);
    expect(layers[2].map(name), ['w', 'v']);
  });

  test('the whole layout keeps the reordered layers free of crossings', () {
    final layout = layoutGraph(crossed);
    expect(countCrossings(layout), 0);
    expect(checkLayout(layout), isEmpty);
  });

  test('nodes with back arrows sink: long arrows pass over them', () {
    // In the task mockup the arrows from admit to reviewer and human-review
    // pass over coder and the rest, whose back arrows run underneath.
    final layout = layoutGraph(loadGraph('task'));
    final over = edgeOf(layout, 'admit', 2).points[2].y;
    for (final name in ['coder', 'coder-status', 'checks', 'checks-result']) {
      expect(over, lessThan(layout.nodes[name]!.tile.top));
    }
    expect(countCrossings(layout), 0);
  });
}
