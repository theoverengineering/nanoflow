import 'json_fields.dart';

/// Where an exit of a node leads: one node, or a list of nodes.
///
/// Every node of a list gets the same data. An empty list leads nowhere: the
/// run ends there.
final class Target {
  /// A single node: `then: inspect`.
  const Target.node(String name) : _node = name, _list = null;

  /// A list of nodes: `then: [publish, notify]`, or `[]` for none.
  ///
  /// The list must not be modified afterwards.
  const Target.list(List<String> names) : _node = null, _list = names;

  /// Reads a target from its JSON form: a string or a list of strings.
  ///
  /// Throws a [FormatException] for any other shape.
  static Target fromJson(Object? json) => _parseTarget(json, 'target');

  final String? _node;
  final List<String>? _list;

  /// The names of the target's nodes: one for a node, any number for a list.
  List<String> get names => _list ?? List.unmodifiable([_node!]);

  /// Whether the target was written as a list, even a list of one.
  bool get isList => _list != null;

  /// A list with no names: the run ends.
  bool get isEmpty => names.isEmpty;

  /// A string for a node, a list of strings for a list.
  Object toJson() => _node ?? List<String>.of(_list!);

  @override
  bool operator ==(Object other) {
    if (other is! Target || other.isList != isList) return false;
    final a = names;
    final b = other.names;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(isList, Object.hashAll(names));

  @override
  String toString() => isList ? 'Target.list($names)' : 'Target.node($_node)';
}

/// One outgoing exit of a node.
final class Exit {
  const Exit({required this.label, required this.target, this.isElse = false});

  /// `null` for a worker, `true` for the `then` of an if, the key for a case of
  /// a switch, `else` for the `else` of a fork.
  final String? label;

  final Target target;

  /// Whether this is the `else` of a fork. A switch key spelled `else` is a
  /// case, not an else, so [label] alone cannot tell them apart.
  final bool isElse;

  @override
  bool operator ==(Object other) =>
      other is Exit &&
      other.label == label &&
      other.target == target &&
      other.isElse == isElse;

  @override
  int get hashCode => Object.hash(label, target, isElse);

  @override
  String toString() =>
      'Exit(label: $label, target: $target${isElse ? ', isElse' : ''})';
}

/// A node of the graph: a worker or a fork.
sealed class Node {
  const Node._({required this.name, required this.input});

  /// The key of the node in `nodes`.
  final String name;

  /// The `in` schema as JSON, or `null` when the node declares none.
  final Object? input;

  /// What the node executes: its `command` or its `decide`.
  String get run;

  /// Every outgoing exit in declaration order: for a worker its `then` if it
  /// has one; for an if the `true` exit, then `else`; for a switch the cases
  /// in map order, then `else`.
  List<Exit> get exits;
}

/// A node that runs a command and passes on what it prints.
final class WorkerNode extends Node {
  WorkerNode._({
    required super.name,
    required super.input,
    required this.command,
    required this.output,
    required this.then,
  }) : exits = List.unmodifiable([
         if (then != null) Exit(label: null, target: then),
       ]),
       super._();

  /// What the node executes.
  final String command;

  /// The `out` schema as JSON, or `null` when the node declares none.
  final Object? output;

  /// Where the run goes next. `null` ends the run.
  final Target? then;

  @override
  String get run => command;

  @override
  final List<Exit> exits;
}

/// A node that decides where the run goes: an if or a switch.
final class ForkNode extends Node {
  ForkNode._({
    required super.name,
    required super.input,
    required this.decide,
    this.ifTrue,
    Map<String, Target>? cases,
    this.otherwise,
  }) : assert((ifTrue == null) != (cases == null)),
       cases = cases == null ? null : Map.unmodifiable(cases),
       exits = List.unmodifiable([
         if (ifTrue != null) Exit(label: 'true', target: ifTrue),
         if (cases != null)
           for (final MapEntry(:key, :value) in cases.entries)
             Exit(label: key, target: value),
         if (otherwise != null)
           Exit(label: 'else', target: otherwise, isElse: true),
       ]),
       super._();

  /// What the node executes to get the outcome.
  final String decide;

  /// Whether `then` is a target rather than a map: an if, not a switch.
  bool get isIf => cases == null;

  /// The `then` of an if.
  final Target? ifTrue;

  /// The `then` of a switch, in map order.
  final Map<String, Target>? cases;

  /// The `else`: where the run goes when the outcome matches nothing.
  final Target? otherwise;

  @override
  String get run => decide;

  @override
  final List<Exit> exits;

  /// Where the run goes for [outcome], any JSON value.
  ///
  /// Matching is by exact value. An if matches only the JSON `true`; a switch
  /// matches only a string equal to a key.
  Route route(Object? outcome) {
    final hit = _matching(outcome);
    if (hit != null) return RouteTo(hit);
    // The else exit, when there is one, is always the last.
    if (otherwise != null) return RouteTo(exits.last);
    return isIf ? const RouteEnd() : RouteMissing(outcome);
  }

  Exit? _matching(Object? outcome) {
    if (isIf) return outcome == true ? exits.first : null;
    if (outcome is! String) return null;
    for (final exit in exits) {
      if (!exit.isElse && exit.label == outcome) return exit;
    }
    return null;
  }
}

/// Where a fork sends the run for an outcome.
sealed class Route {
  const Route();
}

/// To [exit]. Its target may be an empty list: the run ends there.
final class RouteTo extends Route {
  const RouteTo(this.exit);

  final Exit exit;

  Target get target => exit.target;
}

/// An if with no `else` and an outcome that is not `true`: the run ends.
final class RouteEnd extends Route {
  const RouteEnd();
}

/// A switch with no `else` and an outcome that matches no key: an error.
final class RouteMissing extends Route {
  const RouteMissing(this.outcome);

  final Object? outcome;
}

/// The graph: where the run starts, its types and its nodes.
final class Graph {
  Graph._({
    required this.start,
    required this.types,
    required this.nodes,
    required this.json,
  });

  /// Reads a graph from its JSON form, the one the YAML file has.
  ///
  /// Checks the shape only: that each field has the right kind of value, and
  /// that a node is a worker or a fork and nothing else. Whether targets name
  /// existing nodes, and whether `in`, `out` and the types are schemas at all
  /// (objects or booleans), is for `nanoflow check`; whether the schemas are
  /// valid and fit together is for the graph program.
  ///
  /// Throws a [FormatException] whose message starts with the place of the
  /// problem, such as `nodes.verdict.then`.
  static Graph fromJson(Map<String, Object?> json) {
    if (!json.containsKey('start')) {
      throw const FormatException('start: missing');
    }
    final start = _parseTarget(json['start'], 'start');
    final types = json.containsKey('types')
        ? _parseObject(json['types'], 'types')
        : const <String, Object?>{};
    if (!json.containsKey('nodes')) {
      throw const FormatException('nodes: missing');
    }
    final nodes = <String, Node>{
      for (final MapEntry(:key, :value) in _parseObject(
        json['nodes'],
        'nodes',
      ).entries)
        key: _parseNode(key, value),
    };
    return Graph._(
      start: start,
      types: types,
      nodes: Map.unmodifiable(nodes),
      json: json,
    );
  }

  /// Where the run starts.
  final Target start;

  /// The named types as raw JSON. Empty when the graph declares none.
  final Map<String, Object?> types;

  /// The nodes in declaration order.
  final Map<String, Node> nodes;

  /// The raw JSON the graph was parsed from.
  final Map<String, Object?> json;

  /// The JSON the graph was parsed from.
  Map<String, Object?> toJson() => json;

  /// The node called [name], or `null`.
  Node? operator [](String name) => nodes[name];
}

/// What a graph program prints for `--graph`: the file it runs and the graph.
final class GraphDescription {
  GraphDescription._(this.file, this.graph);

  /// Reads a description from its JSON form.
  ///
  /// Throws a [FormatException] whose message starts with the place of the
  /// problem; problems inside the graph are placed under `graph.`.
  static GraphDescription fromJson(Object? json) {
    final fields = _parseObject(json, 'description');
    final file = readString(fields, 'file');
    final graph = readObject(fields, 'graph');
    return GraphDescription._(
      file,
      inside('graph', () => Graph.fromJson(graph)),
    );
  }

  /// The path of the graph file that was run: YAML or source code.
  final String file;

  final Graph graph;

  Map<String, Object?> toJson() => {'file': file, 'graph': graph.toJson()};
}

Map<String, Object?> _parseObject(Object? json, String place) =>
    asObject(json) ?? (throw FormatException('$place: expected an object'));

String _parseString(Object? json, String place) {
  if (json is String) return json;
  throw FormatException('$place: expected a string');
}

Target _parseTarget(
  Object? json,
  String place, {
  String expected = 'a node name or a list of node names',
}) {
  if (json is String) return Target.node(json);
  if (json is List<Object?>) {
    final names = <String>[];
    for (var i = 0; i < json.length; i++) {
      final name = json[i];
      if (name is! String) {
        throw FormatException('$place[$i]: expected a node name');
      }
      names.add(name);
    }
    return Target.list(List.unmodifiable(names));
  }
  throw FormatException('$place: expected $expected');
}

Node _parseNode(String name, Object? json) {
  final place = 'nodes.$name';
  final fields = _parseObject(json, place);
  final hasCommand = fields.containsKey('command');
  final hasDecide = fields.containsKey('decide');
  if (hasCommand && hasDecide) {
    throw FormatException('$place: has both command and decide');
  }
  if (!hasCommand && !hasDecide) {
    throw FormatException('$place: has neither command nor decide');
  }
  return hasCommand
      ? _parseWorker(name, fields, place)
      : _parseFork(name, fields, place);
}

WorkerNode _parseWorker(
  String name,
  Map<String, Object?> fields,
  String place,
) {
  final command = _parseString(fields['command'], '$place.command');
  if (fields.containsKey('else')) {
    throw FormatException('$place.else: a worker has no else');
  }
  return WorkerNode._(
    name: name,
    input: fields['in'],
    command: command,
    output: fields['out'],
    then: fields.containsKey('then')
        ? _parseTarget(fields['then'], '$place.then')
        : null,
  );
}

ForkNode _parseFork(String name, Map<String, Object?> fields, String place) {
  final decide = _parseString(fields['decide'], '$place.decide');
  if (!fields.containsKey('then')) {
    throw FormatException('$place.then: missing');
  }
  final then = fields['then'];
  final thenCases = asObject(then);
  final Target? ifTrue;
  final Map<String, Target>? cases;
  if (thenCases != null) {
    ifTrue = null;
    cases = {
      for (final MapEntry(:key, :value) in thenCases.entries)
        key: _parseTarget(value, '$place.then.$key'),
    };
  } else {
    ifTrue = _parseTarget(
      then,
      '$place.then',
      expected:
          'a node name, a list of node names or a map of outcomes to targets',
    );
    cases = null;
  }
  return ForkNode._(
    name: name,
    input: fields['in'],
    decide: decide,
    ifTrue: ifTrue,
    cases: cases,
    otherwise: fields.containsKey('else')
        ? _parseTarget(fields['else'], '$place.else')
        : null,
  );
}
