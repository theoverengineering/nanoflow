import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_ui/layout/lanes.dart' show clearance;
import 'package:nanoflow_ui/layout/layout.dart';

/// The graph files in `test/layout/graphs/`, by name without
/// `.graph.json`, sorted.
List<String> graphNames() {
  final names = [
    for (final file in Directory('test/layout/graphs').listSync())
      if (file is File && file.path.endsWith('.graph.json'))
        file.uri.pathSegments.last.replaceAll('.graph.json', ''),
  ]..sort();
  return names;
}

/// The graph file `test/layout/graphs/<name>.graph.json`.
GraphFile loadGraphFile(String name) => GraphFile.fromJson(
  jsonDecode(File('test/layout/graphs/$name.graph.json').readAsStringSync())
      as Map<String, Object?>,
);

/// The function of [file] whose id ends with `#<function>`.
GraphFunction functionOf(GraphFile file, String function) =>
    file.functions.values.firstWhere((f) => f.id.endsWith('#$function'));

/// The body of the function [function] of the graph file [name]; by
/// default the function named as the file, as in the graphs converted from
/// the README format.
GraphBody loadBody(String name, [String? function]) =>
    functionOf(loadGraphFile(name), function ?? name).body;

/// The layout of the function [function] of the graph file [name], its
/// calls named from the file.
GraphLayout layoutOf(String name, [String? function]) {
  final file = loadGraphFile(name);
  return layoutBody(
    functionOf(file, function ?? name).body,
    functions: file.functions,
  );
}

/// Every body of [file] with a name: each function's, and inside it each
/// copies node's, as `function` and `function/node`.
Map<String, GraphBody> bodiesOf(GraphFile file) {
  final bodies = <String, GraphBody>{};
  void add(String name, GraphBody body) {
    bodies[name] = body;
    for (final node in body.nodes) {
      if (node is CopiesNode) add('$name/${node.id}', node.body);
    }
  }

  for (final function in file.functions.values) {
    add(function.id, function.body);
  }
  return bodies;
}

/// A body whose call `c` goes on to [ways] branches of `Future.wait`, each
/// to the end: describe draws `await f(); await Future.wait([a(), b()]);`
/// so, and the call's way out is a capsule of [ways] arrows.
GraphBody callThenWait(int ways) => GraphBody(
  nodes: [
    const CallNode(
      id: 'c',
      place: 'lib/flow.dart:10',
      functions: ['lib/flow.dart#f'],
    ),
    for (var i = 0; i < ways; i++)
      EffectNode(id: 'w$i', place: 'lib/flow.dart:${i + 11}', name: 'w$i'),
  ],
  edges: [
    const GraphEdge(from: null, to: 'c', label: null),
    for (var i = 0; i < ways; i++) GraphEdge(from: 'c', to: 'w$i', label: null),
    for (var i = 0; i < ways; i++)
      GraphEdge(from: 'w$i', to: null, label: null),
  ],
);

/// A body written the short way: `start` names the nodes the entry leads
/// to; each node is an effect (`command`) or a condition (`decide`) whose id,
/// name and label are its key; `then` is a node, a list of nodes the flow
/// goes to side by side, or `[]` for the end of the body; a condition's
/// `then` is a map from labels to targets, or a target for `true`, and its
/// `else` a target for `else`. A node without `then` has no edges out.
GraphBody bodyOf(Map<String, Object?> json) {
  List<String?> targets(Object? target) => switch (target) {
    null => const [],
    final String name => [name],
    final List<Object?> names when names.isEmpty => [null],
    final List<Object?> names => [for (final n in names) n! as String],
    _ => throw ArgumentError.value(target, 'target'),
  };
  final nodes = <GraphNode>[];
  final edges = <GraphEdge>[];
  for (final to in targets(json['start'])) {
    edges.add(GraphEdge(from: null, to: to, label: null));
  }
  final all = json['nodes']! as Map<String, Object?>;
  for (final MapEntry(key: name, value: raw) in all.entries) {
    final node = raw! as Map<String, Object?>;
    final place = 'lib/flow.dart:${nodes.length + 10}';
    void edgesTo(Object? target, String? label) {
      for (final to in targets(target)) {
        edges.add(GraphEdge(from: name, to: to, label: label));
      }
    }

    if (node.containsKey('command')) {
      nodes.add(EffectNode(id: name, place: place, name: name));
      edgesTo(node['then'], null);
    } else {
      nodes.add(ConditionNode(id: name, place: place, label: name));
      switch (node['then']) {
        case final Map<String, Object?> cases:
          for (final MapEntry(key: label, value: target) in cases.entries) {
            edgesTo(target, label);
          }
        case final target:
          edgesTo(target, 'true');
      }
      edgesTo(node['else'], 'else');
    }
  }
  return GraphBody(nodes: nodes, edges: edges);
}

/// The crossing counts of the reference layouts, by graph name.
Map<String, int> referenceCrossings() => (jsonDecode(
  File('test/layout/reference.json').readAsStringSync(),
) as Map<String, Object?>).map((name, count) => MapEntry(name, count! as int));

/// Every coordinate of [layout] as text, to compare layouts; of the
/// layouts in its frames too, indented.
String describe(GraphLayout layout, [String indent = '']) {
  final out = StringBuffer('${indent}bounds ${layout.bounds}\n');
  for (final node in layout.nodes.values) {
    out.writeln(
      '$indent${node.id} ${node.kind} ${node.name} ${node.place} '
      '${node.inside} L${node.layer} ${node.tile} ${node.nameRect} '
      '${node.placeRect} ${node.bar?.rect} ${node.bar?.inputs}',
    );
    if (node.frame case final frame?) {
      out
        ..writeln('$indent  frame ${frame.entry}')
        ..write(describe(frame.inner, '$indent    '));
    }
  }
  for (final exit in layout.exits) {
    out.writeln(
      '$indent${exit.node}#${exit.index} ${exit.label} ${exit.shape} '
      '${exit.anchor} '
      '${exit.handle} ${exit.labelRect} ${exit.reach}',
    );
  }
  for (final edge in layout.edges) {
    out.writeln(
      '$indent${edge.from}#${edge.exitIndex}.${edge.listIndex}->${edge.to} '
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

/// The least x of a turn down from exit [exit] of the node [node] of
/// [layout]: a clearance past the exit's label, or where one would start,
/// and past the name and place under the tile, which the turn passes; and
/// a corner.
double turnDownBeside(GraphLayout layout, String node, int exit) {
  final box = layout.nodes[node]!;
  final marks = [
    box.tile.right + exitOf(layout, node, exit).reach,
    box.nameRect.right,
    box.placeRect.right,
  ].reduce(math.max);
  return marks + clearance + layout.options.cornerRadius;
}

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
