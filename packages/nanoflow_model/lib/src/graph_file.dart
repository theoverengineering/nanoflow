// The graph file of a package, `nanoflow.graph.json`: the graph of every
// function with steps, read from the package's code. Written by the describe
// tool, read by the workflow library and the UI.

import 'package:collection/collection.dart';

import 'json_fields.dart';

const DeepCollectionEquality _deep = DeepCollectionEquality();

/// The name of the graph file, in the project directory.
const String graphFileName = 'nanoflow.graph.json';

/// The only format of the graph file there is.
const int graphFileFormat = 1;

/// The graph file of a package.
final class GraphFile {
  const GraphFile({
    required this.format,
    required this.package,
    required this.fingerprint,
    required this.sources,
    required this.builds,
    required this.workflows,
    required this.functions,
    required this.warnings,
  });

  /// Reads a graph file from its JSON form.
  ///
  /// Throws a [FormatException] whose message starts with the JSON path of the
  /// field that is missing or of the wrong kind
  /// (`functions.lib/a.dart#f.body.nodes[2].kind: …`), or with `format` when
  /// the format is not [graphFileFormat].
  factory GraphFile.fromJson(Map<String, Object?> json) {
    final format = readInt(json, 'format');
    if (format != graphFileFormat) {
      throw FormatException(
        'format: expected $graphFileFormat, the file is $format',
      );
    }
    return GraphFile(
      format: format,
      package: readString(json, 'package'),
      fingerprint: readString(json, 'fingerprint'),
      sources: readStringMap(json, 'sources'),
      builds: readStringMap(json, 'builds'),
      workflows: readStrings(json, 'workflows'),
      functions: readObjectMap(json, 'functions', GraphFunction.fromJson),
      warnings: readObjects(json, 'warnings', GraphWarning.fromJson),
    );
  }

  /// The version of the file's format: [graphFileFormat].
  final int format;

  /// The name of the package.
  final String package;

  /// `sha256:` and the hex fingerprint of [sources] (`fingerprintOf`).
  final String fingerprint;

  /// The hash of every source file by its path from the package root.
  final Map<String, String> sources;

  /// The hash of every stamped binary by its file name.
  final Map<String, String> builds;

  /// The ids of the functions passed first to `Flow.start`, `Flow.run` or
  /// `Flow.resume`.
  final List<String> workflows;

  /// The functions with steps by their ids: `path#name`, and `path#Class.name`
  /// for a method.
  final Map<String, GraphFunction> functions;

  /// What the describe tool could not draw.
  final List<GraphWarning> warnings;

  /// The workflow whose id ends with `#name` or `.name`, or `null`.
  GraphFunction? workflowNamed(String name) {
    for (final id in workflows) {
      if (id.endsWith('#$name') || id.endsWith('.$name')) {
        final function = functions[id];
        if (function != null) return function;
      }
    }
    return null;
  }

  Map<String, Object?> toJson() => {
    'format': format,
    'package': package,
    'fingerprint': fingerprint,
    'sources': {...sources},
    'builds': {...builds},
    'workflows': [...workflows],
    'functions': {
      for (final MapEntry(:key, :value) in functions.entries)
        key: value.toJson(),
    },
    'warnings': [for (final warning in warnings) warning.toJson()],
  };

  @override
  bool operator ==(Object other) =>
      other is GraphFile &&
      other.format == format &&
      other.package == package &&
      other.fingerprint == fingerprint &&
      _deep.equals(other.sources, sources) &&
      _deep.equals(other.builds, builds) &&
      _deep.equals(other.workflows, workflows) &&
      _deep.equals(other.functions, functions) &&
      _deep.equals(other.warnings, warnings);

  @override
  int get hashCode => Object.hash(
    format,
    package,
    fingerprint,
    _deep.hash(sources),
    _deep.hash(builds),
    _deep.hash(workflows),
    _deep.hash(functions),
    _deep.hash(warnings),
  );

  @override
  String toString() =>
      'GraphFile(format: $format, package: $package, '
      'fingerprint: $fingerprint, sources: $sources, builds: $builds, '
      'workflows: $workflows, functions: $functions, warnings: $warnings)';
}

/// A function with steps and the graph of its body.
final class GraphFunction {
  const GraphFunction({
    required this.id,
    required this.name,
    required this.place,
    required this.body,
  });

  /// Reads the function [id] from its JSON form. The id is the key the
  /// function has in the file, so it is not in [json].
  factory GraphFunction.fromJson(String id, Map<String, Object?> json) =>
      GraphFunction(
        id: id,
        name: readString(json, 'name'),
        place: readStringOrNull(json, 'place'),
        body: readNested(json, 'body', GraphBody.fromJson),
      );

  /// `path#name`, and `path#Class.name` for a method.
  final String id;

  /// The name of the function, without its class.
  final String name;

  /// `path:line` of the declaration, from the package root; `null` when
  /// unknown.
  final String? place;

  final GraphBody body;

  /// The JSON form, without the [id]: that is the key of the function in the
  /// file.
  Map<String, Object?> toJson() => {
    'name': name,
    'place': place,
    'body': body.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is GraphFunction &&
      other.id == id &&
      other.name == name &&
      other.place == place &&
      other.body == body;

  @override
  int get hashCode => Object.hash(id, name, place, body);

  @override
  String toString() =>
      'GraphFunction(id: $id, name: $name, place: $place, body: $body)';
}

/// The graph of one level: nodes and the edges between them.
final class GraphBody {
  const GraphBody({required this.nodes, required this.edges});

  /// Reads a body from its JSON form.
  factory GraphBody.fromJson(Map<String, Object?> json) => GraphBody(
    nodes: readObjects(json, 'nodes', GraphNode.fromJson),
    edges: readObjects(json, 'edges', GraphEdge.fromJson),
  );

  final List<GraphNode> nodes;

  /// An edge with `from: null` leaves the entry of the body, one with
  /// `to: null` leaves the body.
  final List<GraphEdge> edges;

  /// The node with [id], or `null`.
  GraphNode? node(String id) => nodes.firstWhereOrNull((n) => n.id == id);

  Map<String, Object?> toJson() => {
    'nodes': [for (final node in nodes) node.toJson()],
    'edges': [for (final edge in edges) edge.toJson()],
  };

  @override
  bool operator ==(Object other) =>
      other is GraphBody &&
      _deep.equals(other.nodes, nodes) &&
      _deep.equals(other.edges, edges);

  @override
  int get hashCode => Object.hash(_deep.hash(nodes), _deep.hash(edges));

  @override
  String toString() => 'GraphBody(nodes: $nodes, edges: $edges)';
}

/// A node of a [GraphBody]: a step, a condition, a call or copies of a body.
sealed class GraphNode {
  const GraphNode({required this.id, required this.place});

  /// Reads a node from its JSON form, whatever its `kind`.
  factory GraphNode.fromJson(Map<String, Object?> json) {
    final id = readString(json, 'id');
    final kind = readString(json, 'kind');
    return switch (kind) {
      'step' => StepNode(
        id: id,
        place: readStringOrNull(json, 'place'),
        name: readString(json, 'name'),
      ),
      'fork' => ConditionNode(
        id: id,
        place: readStringOrNull(json, 'place'),
        label: readString(json, 'label'),
      ),
      'call' => CallNode(
        id: id,
        place: readStringOrNull(json, 'place'),
        functions: readStrings(json, 'functions'),
      ),
      'copies' => CopiesNode(
        id: id,
        place: readStringOrNull(json, 'place'),
        label: readString(json, 'label'),
        body: readNested(json, 'body', GraphBody.fromJson),
      ),
      _ => throw FormatException(
        'kind: unknown kind "$kind", expected step, fork, call or copies',
      ),
    };
  }

  /// Unique among the nodes of one body.
  final String id;

  /// `path:line` from the package root; `null` when unknown.
  final String? place;

  Map<String, Object?> toJson();
}

/// A call of `f.step`.
final class StepNode extends GraphNode {
  const StepNode({required super.id, required super.place, required this.name});

  /// The literal name of the step, or the source of the expression that gives
  /// it.
  final String name;

  @override
  Map<String, Object?> toJson() => {
    'id': id,
    'kind': 'step',
    'name': name,
    'place': place,
  };

  @override
  bool operator ==(Object other) =>
      other is StepNode &&
      other.id == id &&
      other.place == place &&
      other.name == name;

  @override
  int get hashCode => Object.hash(StepNode, id, place, name);

  @override
  String toString() => 'StepNode(id: $id, place: $place, name: $name)';
}

/// A condition the flow goes one of several ways on; kind `fork`.
final class ConditionNode extends GraphNode {
  const ConditionNode({
    required super.id,
    required super.place,
    required this.label,
  });

  /// The source of the condition.
  final String label;

  @override
  Map<String, Object?> toJson() => {
    'id': id,
    'kind': 'fork',
    'label': label,
    'place': place,
  };

  @override
  bool operator ==(Object other) =>
      other is ConditionNode &&
      other.id == id &&
      other.place == place &&
      other.label == label;

  @override
  int get hashCode => Object.hash(ConditionNode, id, place, label);

  @override
  String toString() => 'ConditionNode(id: $id, place: $place, label: $label)';
}

/// A call of a function that has steps.
final class CallNode extends GraphNode {
  const CallNode({
    required super.id,
    required super.place,
    required this.functions,
  });

  /// The ids of the functions that can be called: several when the call goes
  /// to an interface.
  final List<String> functions;

  @override
  Map<String, Object?> toJson() => {
    'id': id,
    'kind': 'call',
    'functions': [...functions],
    'place': place,
  };

  @override
  bool operator ==(Object other) =>
      other is CallNode &&
      other.id == id &&
      other.place == place &&
      _deep.equals(other.functions, functions);

  @override
  int get hashCode => Object.hash(CallNode, id, place, _deep.hash(functions));

  @override
  String toString() =>
      'CallNode(id: $id, place: $place, functions: $functions)';
}

/// A body that `Future.wait` runs in as many copies as a list has items.
final class CopiesNode extends GraphNode {
  const CopiesNode({
    required super.id,
    required super.place,
    required this.label,
    required this.body,
  });

  /// `<variable> in <expression>`.
  final String label;

  /// The graph of one copy.
  final GraphBody body;

  @override
  Map<String, Object?> toJson() => {
    'id': id,
    'kind': 'copies',
    'label': label,
    'place': place,
    'body': body.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is CopiesNode &&
      other.id == id &&
      other.place == place &&
      other.label == label &&
      other.body == body;

  @override
  int get hashCode => Object.hash(CopiesNode, id, place, label, body);

  @override
  String toString() =>
      'CopiesNode(id: $id, place: $place, label: $label, body: $body)';
}

/// An edge between two nodes of a body.
final class GraphEdge {
  const GraphEdge({required this.from, required this.to, required this.label});

  /// Reads an edge from its JSON form.
  factory GraphEdge.fromJson(Map<String, Object?> json) => GraphEdge(
    from: readStringOrNull(json, 'from'),
    to: readStringOrNull(json, 'to'),
    label: readStringOrNull(json, 'label'),
  );

  /// The id of the node the edge leaves; `null` for the entry of the body.
  final String? from;

  /// The id of the node the edge enters; `null` for the exit of the body.
  final String? to;

  /// What makes the flow take the edge out of a condition (`true`, `false`,
  /// `each`, `done`, the source of a `switch` case, `default`); `null` for any
  /// other edge.
  final String? label;

  Map<String, Object?> toJson() => {'from': from, 'to': to, 'label': label};

  @override
  bool operator ==(Object other) =>
      other is GraphEdge &&
      other.from == from &&
      other.to == to &&
      other.label == label;

  @override
  int get hashCode => Object.hash(from, to, label);

  @override
  String toString() => 'GraphEdge(from: $from, to: $to, label: $label)';
}

/// Something in the code the describe tool could not draw.
final class GraphWarning {
  const GraphWarning({required this.place, required this.message});

  /// Reads a warning from its JSON form.
  factory GraphWarning.fromJson(Map<String, Object?> json) => GraphWarning(
    place: readStringOrNull(json, 'place'),
    message: readString(json, 'message'),
  );

  /// `path:line` from the package root; `null` when unknown.
  final String? place;

  final String message;

  Map<String, Object?> toJson() => {'place': place, 'message': message};

  @override
  bool operator ==(Object other) =>
      other is GraphWarning && other.place == place && other.message == message;

  @override
  int get hashCode => Object.hash(place, message);

  @override
  String toString() => 'GraphWarning(place: $place, message: $message)';
}
