import 'dart:convert';

import 'package:ack/ack.dart';
import 'package:nanoflow_model/nanoflow_model.dart';

import 'graph_schema.dart';

/// A graph that does not pass `check`.
final class GraphCheckException implements Exception {
  GraphCheckException(List<String> errors) : errors = List.unmodifiable(errors);

  /// The lines of [checkGraph].
  final List<String> errors;

  @override
  String toString() => 'GraphCheckException:\n${errors.join('\n')}';
}

/// The problems of [graphJson], a graph in its JSON form, one line each;
/// empty when it passes.
///
/// A line is `<place>: <problem>`. The place is the dotted path into the
/// graph — `start`, `nodes.verdict.then.accepted`, `nodes.inspect` — with
/// `[i]` for an item of a list, and `graph` for the graph itself.
///
/// The structure is checked first, by [graphSchema]; the check stops at its
/// first problem. Only a graph whose structure passes is checked for
/// meaning: that every target — in `start`, `then` and `else` — names
/// existing nodes, that no list of targets names a node twice or only one
/// node, that `start` is not empty, and that every node is reachable from
/// `start`. Those lines come in the order of their places in the graph.
List<String> checkGraph(Object? graphJson) {
  final structure = _explain(_graphSchema, graphJson, graphJson, const []);
  if (structure != null) return [structure];
  return _meaningErrors(
    Graph.fromJson(Map<String, Object?>.from(graphJson as Map)),
  );
}

/// Reads [bytes], a description of a graph as `--graph` prints it, and
/// checks its graph.
///
/// Throws a [FormatException] whose message is the reason when [bytes] are
/// not a description: one JSON object with a string `file` and a `graph`.
/// Throws a [GraphCheckException] when the graph does not pass
/// [checkGraph].
GraphDescription checkDescription(List<int> bytes) {
  final Object? json;
  try {
    json = jsonDecode(utf8.decode(bytes));
  } on FormatException {
    throw const FormatException('not JSON');
  }
  if (json is! Map<String, Object?> ||
      json['file'] is! String ||
      !json.containsKey('graph')) {
    throw const FormatException('expected {"file": <path>, "graph": <graph>}');
  }
  final errors = checkGraph(json['graph']);
  if (errors.isNotEmpty) throw GraphCheckException(errors);
  return GraphDescription.fromJson(json);
}

final _graphSchema = Ack.fromJsonSchema(graphSchema);

/// The definitions of a worker and of a fork, to find out why a node that
/// says which it is — by its `command` or `decide` — is not one.
final _workerSchema = _definition('worker');
final _forkSchema = _definition('fork');

AckSchema<Object, Object> _definition(String name) => Ack.fromJsonSchema({
  r'$defs': graphSchema[r'$defs'],
  r'$ref': '#/\$defs/$name',
});

/// The first problem [schema] finds in [value], as an error line; `null`
/// when there is none. [value] sits at [at] in [graph].
String? _explain(
  AckSchema<Object, Object> schema,
  Object? value,
  Object? graph,
  List<String> at,
) {
  final result = schema.safeParse(value);
  if (result.isOk) return null;
  final error = result.getError();
  final path = [...at, ..._segments(error.context)];
  final place = _place(graph, path);
  final (keyword, pointer) = _violated(error);
  return switch (keyword) {
    // `additionalProperties: false` fails at the key it does not allow.
    'false' =>
      '${_place(graph, path.sublist(0, path.length - 1))}: '
          'unknown key ${jsonEncode(path.last)}',
    // `required` fails at the key that is missing.
    'required' => '$place: missing',
    'minLength' => '$place: is empty',
    'type' => '$place: expected ${_expected(pointer)}',
    // Only a node has `oneOf`: it is neither a worker nor a fork.
    'oneOf' => _explainNode(_at(graph, path)! as Map, graph, path),
    _ => '$place: does not pass "$keyword" of the graph schema',
  };
}

String _explainNode(
  Map<Object?, Object?> node,
  Object? graph,
  List<String> at,
) {
  final place = _place(graph, at);
  final hasCommand = node.containsKey('command');
  final hasDecide = node.containsKey('decide');
  if (hasCommand && hasDecide) return '$place: has both command and decide';
  if (!hasCommand && !hasDecide) {
    return '$place: has neither command nor decide';
  }
  return _explain(hasCommand ? _workerSchema : _forkSchema, node, graph, at) ??
      (throw StateError('$place fails oneOf of a node but passes its kind'));
}

/// The keyword that failed and the JSON Pointer of the schema it is in,
/// from ack's message `JSON Schema "<keyword>" failed at <uri>#<pointer>.`.
///
/// ack rejects `null` before the schema runs, with a message of its own: that
/// is the root's `type` failing.
(String, String) _violated(SchemaError error) {
  final match = _violation.firstMatch(error.message);
  if (match == null) return ('type', '');
  return (match[1]!, match[2]!);
}

final _violation = RegExp(r'^JSON Schema "([^"]+)" failed at [^#]*#(.*)\.$');

/// What a schema of [graphSchema] that rejected a value's type expects,
/// by its JSON Pointer.
String _expected(String pointer) => switch (pointer) {
  r'/$defs/command' => 'a string',
  r'/$defs/schema' => 'a schema (an object or a boolean)',
  r'/$defs/target' => 'a node name or a list of node names',
  r'/$defs/forkThen' =>
    'a node name, a list of node names or a map of outcomes to targets',
  r'/$defs/name' => 'a node name',
  // The graph, `types`, `nodes` and a node.
  _ => 'an object',
};

/// The keys and indexes from the value ack validated down to [context].
List<String> _segments(SchemaContext context) {
  final segments = <String>[];
  for (var at = context; at.parent != null; at = at.parent!) {
    segments.add(at.pathSegment ?? at.name);
  }
  return segments.reversed.toList();
}

/// The value at [path] in [graph], or `null` when there is none.
Object? _at(Object? graph, List<String> path) {
  var value = graph;
  for (final segment in path) {
    value = switch (value) {
      List() => value[int.parse(segment)],
      Map() => value[segment],
      _ => null,
    };
  }
  return value;
}

/// [path] in [graph] written as a place: `nodes.verdict.then.accepted[1]`.
String _place(Object? graph, List<String> path) {
  if (path.isEmpty) return 'graph';
  final place = StringBuffer();
  for (var i = 0; i < path.length; i++) {
    if (_at(graph, path.sublist(0, i)) is List) {
      place.write('[${path[i]}]');
    } else {
      if (i > 0) place.write('.');
      place.write(path[i]);
    }
  }
  return '$place';
}

List<String> _meaningErrors(Graph graph) {
  final reachable = _reachable(graph);
  return [
    if (graph.start.isEmpty) 'start: is empty',
    ..._targetErrors('start', graph.start, graph),
    for (final node in graph.nodes.values) ...[
      if (!reachable.contains(node.name))
        'nodes.${node.name}: unreachable from start',
      for (final exit in node.exits)
        ..._targetErrors(_exitPlace(node, exit), exit.target, graph),
    ],
  ];
}

/// Where [exit] of [node] is written: its `then`, a key of its `then`, or
/// its `else`.
String _exitPlace(Node node, Exit exit) {
  final place = 'nodes.${node.name}';
  if (exit.isElse) return '$place.else';
  if (node case ForkNode(isIf: false)) return '$place.then.${exit.label}';
  return '$place.then';
}

Iterable<String> _targetErrors(String place, Target target, Graph graph) sync* {
  final names = target.names;
  if (target.isList && names.length == 1) {
    final name = jsonEncode(names.single);
    yield '$place: a list of one node; write $name without a list';
  }
  for (final name in names.toSet()) {
    if (graph[name] == null) {
      yield '$place: unknown node ${jsonEncode(name)}';
    }
    if (names.where((n) => n == name).length > 1) {
      yield '$place: ${jsonEncode(name)} is listed more than once';
    }
  }
}

/// The names of the nodes that some path of arrows leads to from `start`.
Set<String> _reachable(Graph graph) {
  final reached = <String>{};
  final pending = [...graph.start.names];
  while (pending.isNotEmpty) {
    final node = graph[pending.removeLast()];
    if (node == null || !reached.add(node.name)) continue;
    for (final exit in node.exits) {
      pending.addAll(exit.target.names);
    }
  }
  return reached;
}
