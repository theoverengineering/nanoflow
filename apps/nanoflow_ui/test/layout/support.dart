import 'dart:convert';
import 'dart:io';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_ui/layout/layout.dart';

/// The graphs in `test/layout/graphs/`, by name without `.json`, sorted.
List<String> graphNames() {
  final names = [
    for (final file in Directory('test/layout/graphs').listSync())
      if (file is File && file.path.endsWith('.json'))
        file.uri.pathSegments.last.replaceAll('.json', ''),
  ]..sort();
  return names;
}

/// The graph `test/layout/graphs/<name>.json`.
Graph loadGraph(String name) => Graph.fromJson(
  jsonDecode(File('test/layout/graphs/$name.json').readAsStringSync())
      as Map<String, Object?>,
);

/// A graph from its JSON form.
Graph graphOf(Map<String, Object?> json) => Graph.fromJson(json);

/// The crossing counts of the reference layouts, by graph name.
Map<String, int> referenceCrossings() => (jsonDecode(
  File('test/layout/reference.json').readAsStringSync(),
) as Map<String, Object?>).map((name, count) => MapEntry(name, count! as int));

/// Every coordinate of [layout] as text, to compare layouts.
String describe(GraphLayout layout) {
  final out = StringBuffer('bounds ${layout.bounds}\n');
  for (final node in layout.nodes.values) {
    out.writeln(
      '${node.name} ${node.command} L${node.layer} ${node.tile} ${node.nameRect} '
      '${node.commandRect} ${node.startRect} ${node.bar?.rect} '
      '${node.bar?.inputs}',
    );
  }
  for (final exit in layout.exits) {
    out.writeln(
      '${exit.node}#${exit.index} ${exit.shape} ${exit.anchor} '
      '${exit.handle} ${exit.stubEnd} ${exit.labelRect} ${exit.counterAt}',
    );
  }
  for (final edge in layout.edges) {
    out.writeln(
      '${edge.from}#${edge.exitIndex}.${edge.listIndex}->${edge.to} '
      '${edge.kind} ${edge.points} ${edge.tip} ${edge.pieces}',
    );
  }
  return out.toString();
}

/// The arrow of [layout] from exit [exit] of node [from] (and the list
/// position [list]).
EdgePath edgeOf(GraphLayout layout, String from, int exit, [int list = 0]) =>
    layout.edges.firstWhere(
      (e) => e.from == from && e.exitIndex == exit && e.listIndex == list,
    );

/// The exit [index] of node [node].
ExitBox exitOf(GraphLayout layout, String node, int index) =>
    layout.exits.firstWhere((e) => e.node == node && e.index == index);

/// The vertical pieces of [edge] as (x, top, bottom).
List<(double, double, double)> verticals(EdgePath edge) => [
  for (var i = 1; i < edge.points.length; i++)
    if (edge.points[i].x == edge.points[i - 1].x &&
        edge.points[i].y != edge.points[i - 1].y)
      (
        edge.points[i].x,
        edge.points[i].y < edge.points[i - 1].y
            ? edge.points[i].y
            : edge.points[i - 1].y,
        edge.points[i].y < edge.points[i - 1].y
            ? edge.points[i - 1].y
            : edge.points[i].y,
      ),
];
