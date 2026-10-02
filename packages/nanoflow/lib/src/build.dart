import 'dart:collection';
import 'dart:mirrors';

import 'package:path/path.dart' as p;

import 'dart_types.dart';
import 'graph.dart';
import 'naming.dart';
import 'vertex.dart';

/// Why a graph does not build: one line per problem.
final class GraphBuildException implements Exception {
  GraphBuildException(List<String> errors) : errors = List.unmodifiable(errors);

  final List<String> errors;

  @override
  String toString() => 'GraphBuildException: ${errors.join('; ')}';
}

/// A graph that passed the build checks: its nodes by name and its JSON.
final class BuiltGraph {
  BuiltGraph._({
    required this.nodes,
    required this.graphJson,
    required this.startTakesInput,
    required this._variables,
  });

  /// The nodes by name, in declaration order.
  final Map<String, Vertex<Object?, Object?>> nodes;

  /// The graph in the README format, except that `command` and `decide` hold
  /// the absolute place of the node's declaration, `/abs/graph.dart:12`:
  /// [describe] makes it relative to the program file.
  final Map<String, Object?> graphJson;

  /// Whether a start node declares `in`: then a run needs a launch input.
  final bool startTakesInput;

  /// The variable each node is named after, by name.
  final Map<String, NodeVariable> _variables;
}

/// Checks [graph] and gives its nodes by name and its JSON.
///
/// Throws a [GraphBuildException] with every problem found: no
/// `Graph.start`, an exit declared twice, a node that is not a top-level
/// variable or is held by two of them, two nodes of the same name, a node
/// that no arrow leads to from a `Graph.start`, a data type with no JSON
/// form or that lets the data be null, `Object` where `Object?` makes a node
/// without data.
BuiltGraph buildGraph(Graph<Object?> graph) => _Build(chainsOf(graph)).run();

/// What keeps [graph] from building, one line per problem, as `--graph`
/// prints it: empty when the graph builds.
///
/// A test that imports the graph checks it with
/// `expect(graphErrors(reviewer.graph), isEmpty)`, without running the
/// program. The graph's library is imported with a prefix, `as reviewer`: a
/// node named as a matcher, such as `isEmpty`, would clash with it.
List<String> graphErrors(Graph<Object?> graph) {
  try {
    buildGraph(graph);
  } on GraphBuildException catch (e) {
    return e.errors;
  }
  return const [];
}

typedef _Vertex = Vertex<Object?, Object?>;

/// One build of a graph: its checks in order, then its JSON.
final class _Build {
  _Build(this.chains) {
    for (final chain in chains) {
      vertices.add(chain.head);
      for (final arrow in chain.arrows) {
        arrows.add(arrow);
        vertices
          ..add(arrow.from)
          ..addAll(arrow.targets);
      }
    }
  }

  final List<Chain> chains;

  /// Every node of the graph, each once.
  final vertices = LinkedHashSet<_Vertex>.identity();

  /// Every arrow of the graph in declaration order.
  final arrows = <Arrow>[];

  final errors = <String>[];

  /// The variable each node is named after.
  final named = LinkedHashMap<_Vertex, NodeVariable>.identity();

  /// The named nodes in declaration order.
  final ordered = <_Vertex>[];

  /// The arrows of each node in declaration order.
  final exits = LinkedHashMap<_Vertex, List<Arrow>>.identity();

  final types = <String, Object?>{};
  final inputs = HashMap<_Vertex, Map<String, Object?>?>.identity();
  final outputs = HashMap<_Vertex, Map<String, Object?>?>.identity();

  BuiltGraph run() {
    if (!chains.any((c) => c.isStart)) errors.add('graph has no Graph.start');
    _name();
    _checkExits();
    _checkReachable();
    _describeData();
    if (errors.isNotEmpty) throw GraphBuildException(errors);

    // A node that begins several parts with Graph.start is one start node.
    final starts = LinkedHashSet<_Vertex>.identity()
      ..addAll([
        for (final chain in chains)
          if (chain.isStart) chain.head,
      ]);
    return BuiltGraph._(
      nodes: Map.unmodifiable({
        for (final vertex in ordered) _nameOf(vertex): vertex,
      }),
      graphJson: Map.unmodifiable({
        'start': starts.length == 1
            ? _nameOf(starts.single)
            : [for (final start in starts) _nameOf(start)],
        'types': types,
        'nodes': {
          for (final vertex in ordered) _nameOf(vertex): _nodeJson(vertex),
        },
      }),
      startTakesInput: starts.any((start) => inputs[start] != null),
      variables: {
        for (final vertex in ordered) _nameOf(vertex): named[vertex]!,
      },
    );
  }

  /// Names each node after the top-level variable that holds it.
  void _name() {
    final variables = nodeVariables();
    final heldTwice = <String>[];
    for (final vertex in vertices) {
      final held = variables[vertex] ?? const <NodeVariable>[];
      if (held.isEmpty) continue;
      named[vertex] = held.first;
      if (held.length > 1) {
        final count = held.length == 2 ? 'two' : '${held.length}';
        heldTwice.add(
          'node is held by $count variables: '
          '${held.map((v) => v.name).join(', ')}',
        );
      }
    }
    if (named.length < vertices.length) {
      errors.add('a node in the graph is not a top-level variable');
    }
    errors.addAll(heldTwice);

    ordered
      ..addAll(named.keys)
      ..sort((a, b) => NodeVariable.compare(named[a]!, named[b]!));
    final byName = <String, List<_Vertex>>{};
    for (final vertex in ordered) {
      (byName[_nameOf(vertex)] ??= []).add(vertex);
    }
    for (final MapEntry(key: name, value: holders) in byName.entries) {
      if (holders.length > 1) errors.add('node name "$name" is not unique');
    }
  }

  /// Groups the arrows by node, checking that each exit is declared once.
  void _checkExits() {
    final declared = HashMap<_Vertex, Set<String>>.identity();
    for (final arrow in arrows) {
      (exits[arrow.from] ??= []).add(arrow);
      if (!named.containsKey(arrow.from)) continue;
      final exit = switch (arrow.exit) {
        NextExit() => 'next',
        OutcomeExit(:final outcome) => 'outcome "${outcomeKey(outcome)}"',
        OtherwiseExit() => 'otherwise',
      };
      final error = '${_nameOf(arrow.from)}: $exit is declared twice';
      if (!(declared[arrow.from] ??= {}).add(exit) && !errors.contains(error)) {
        errors.add(error);
      }
    }
  }

  /// Checks that a path of arrows leads to each node from the node of some
  /// `Graph.start`, as `nanoflow check` does. A graph without a
  /// `Graph.start` gets no line here: `graph has no Graph.start` says it.
  void _checkReachable() {
    final pending = [
      for (final chain in chains)
        if (chain.isStart) chain.head,
    ];
    if (pending.isEmpty) return;
    final reached = HashSet<_Vertex>.identity();
    while (pending.isNotEmpty) {
      final vertex = pending.removeLast();
      if (!reached.add(vertex)) continue;
      for (final arrow in exits[vertex] ?? const <Arrow>[]) {
        pending.addAll(arrow.targets);
      }
    }
    for (final vertex in ordered) {
      if (!reached.contains(vertex)) {
        errors.add('${_nameOf(vertex)}: unreachable from Graph.start');
      }
    }
  }

  /// The schemas of each node's `in` and `out`, and the types they name.
  void _describeData() {
    for (final vertex in ordered) {
      inputs[vertex] = _schemaOf(
        vertex,
        'in',
        reflectType(inputTypeOf(vertex)),
        nullable: inputTakesNull(vertex),
      );
      if (vertex is! Worker<Object?, Object?>) continue;
      final output = awaited(reflectType(outputTypeOf(vertex)));
      // A function that never returns, such as one that always throws,
      // passes nothing on: Dart infers its result as Never.
      outputs[vertex] = output == currentMirrorSystem().neverType
          ? null
          : _schemaOf(vertex, 'out', output, nullable: outputTakesNull(vertex));
    }
  }

  /// The schema of [type], the type of [vertex]'s [side], `in` or `out`;
  /// [nullable] tells whether [type] is nullable. `null` for a type that
  /// carries no data, and for one that cannot be the node's: then the error
  /// is added.
  Map<String, Object?>? _schemaOf(
    _Vertex vertex,
    String side,
    TypeMirror type, {
    required bool nullable,
  }) {
    try {
      final schema = schemaOf(type, types);
      final error = nullError(type, nullable: nullable);
      if (error == null) return schema;
      errors.add('${_nameOf(vertex)}: $side: $error');
    } on UnsupportedTypeException catch (e) {
      errors.add('${_nameOf(vertex)}: $side: ${e.message}');
    }
    return null;
  }

  String _nameOf(_Vertex vertex) => named[vertex]!.name;

  /// Where [arrow] leads: a node's name, also for a set of one node, which
  /// means the same; a list of names for a set of any other size.
  Object _target(Arrow arrow) => switch (arrow.targets) {
    [final single] => _nameOf(single),
    final targets => [for (final vertex in targets) _nameOf(vertex)],
  };

  Map<String, Object?> _nodeJson(_Vertex vertex) {
    final variable = named[vertex]!;
    final place = '${variable.path}:${variable.line}';
    final input = inputs[vertex];
    final declared = exits[vertex] ?? const <Arrow>[];
    final otherwise = declared
        .where((a) => a.exit is OtherwiseExit)
        .firstOrNull;
    switch (vertex) {
      case Worker():
        final output = outputs[vertex];
        final next = declared.where((a) => a.exit is NextExit).firstOrNull;
        return {
          'command': place,
          'in': ?input,
          'out': ?output,
          if (next != null) 'then': _target(next),
        };
      case Fork():
        final cases = {
          for (final arrow in declared)
            if (arrow.exit case OutcomeExit(:final outcome)) outcome: arrow,
        };
        final Object then;
        if (outcomeTypeOf(vertex) == bool) {
          // An if: its one case is `true`; without it, `true` leads nowhere.
          then = switch (cases[true]) {
            final arrow? => _target(arrow),
            null => <String>[],
          };
        } else {
          then = {
            for (final MapEntry(:key, value: arrow) in cases.entries)
              outcomeKey(key): _target(arrow),
          };
        }
        return {
          'decide': place,
          'in': ?input,
          'then': then,
          if (otherwise != null) 'else': _target(otherwise),
        };
    }
  }
}

/// What a graph program prints for `--graph`: the program [file] and the
/// graph, with each `command` and `decide` relative to the directory of
/// [file], such as `graph.dart:12`.
Map<String, Object?> describe(BuiltGraph graph, String file) {
  final directory = p.dirname(file);
  final nodes = graph.graphJson['nodes']! as Map<String, Object?>;
  return {
    'file': file,
    'graph': {
      ...graph.graphJson,
      'nodes': {
        for (final MapEntry(:key, :value) in nodes.entries)
          key: _placedRelative(
            value! as Map<String, Object?>,
            graph._variables[key]!,
            directory,
          ),
      },
    },
  };
}

Map<String, Object?> _placedRelative(
  Map<String, Object?> node,
  NodeVariable variable,
  String directory,
) {
  final path = p.isAbsolute(variable.path)
      ? p.relative(variable.path, from: directory)
      : variable.path;
  final place = '$path:${variable.line}';
  return {
    ...node,
    if (node.containsKey('command')) 'command': place else 'decide': place,
  };
}

/// How a switch key, or the outcome a switch got, is written: an enum value
/// by its name, any other value by its `toString()`.
String outcomeKey(Object? outcome) =>
    outcome is Enum ? outcome.name : '$outcome';
