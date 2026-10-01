import 'package:collection/collection.dart';

import 'json_fields.dart';

const DeepCollectionEquality _deep = DeepCollectionEquality();

/// One launch of a graph.
///
/// The start time is not a field: it is the `run-started` time of the
/// session's runs.
final class Session {
  const Session({required this.id, required this.graph});

  /// Reads a session from its JSON form.
  ///
  /// Throws a [FormatException] whose message starts with the field that is
  /// missing or of the wrong kind.
  factory Session.fromJson(Map<String, Object?> json) =>
      Session(id: readString(json, 'id'), graph: readObject(json, 'graph'));

  final String id;

  /// The graph as it was when the session was created, as raw JSON.
  final Map<String, Object?> graph;

  Map<String, Object?> toJson() => {'id': id, 'graph': graph};

  @override
  bool operator ==(Object other) =>
      other is Session && other.id == id && _deep.equals(other.graph, graph);

  @override
  int get hashCode => Object.hash(id, _deep.hash(graph));

  @override
  String toString() => 'Session(id: $id, graph: $graph)';
}

/// One path through the graph.
final class Run {
  const Run({
    required this.id,
    required this.sessionId,
    required this.parentId,
  });

  /// Reads a run from its JSON form.
  ///
  /// Throws a [FormatException] whose message starts with the field that is
  /// missing or of the wrong kind.
  factory Run.fromJson(Map<String, Object?> json) => Run(
    id: readString(json, 'id'),
    sessionId: readString(json, 'sessionId'),
    parentId: readStringOrNull(json, 'parentId'),
  );

  final String id;

  /// The session the run belongs to.
  final String sessionId;

  /// The run whose fork created this one, from the same session. `null` for a
  /// run the launch started.
  final String? parentId;

  Map<String, Object?> toJson() => {
    'id': id,
    'sessionId': sessionId,
    'parentId': parentId,
  };

  @override
  bool operator ==(Object other) =>
      other is Run &&
      other.id == id &&
      other.sessionId == sessionId &&
      other.parentId == parentId;

  @override
  int get hashCode => Object.hash(id, sessionId, parentId);

  @override
  String toString() =>
      'Run(id: $id, sessionId: $sessionId, parentId: $parentId)';
}

/// One entry into a node.
final class Step {
  const Step({
    required this.id,
    required this.runId,
    required this.inputId,
    required this.outputId,
    required this.log,
  });

  /// Reads a step from its JSON form.
  ///
  /// Throws a [FormatException] whose message starts with the field that is
  /// missing or of the wrong kind.
  factory Step.fromJson(Map<String, Object?> json) => Step(
    id: readString(json, 'id'),
    runId: readString(json, 'runId'),
    inputId: readStringOrNull(json, 'inputId'),
    outputId: readStringOrNull(json, 'outputId'),
    log: readStringOrNull(json, 'log'),
  );

  final String id;

  /// The run the step belongs to.
  final String runId;

  /// The document the command takes as input. `null` when the node has no
  /// `in`.
  final String? inputId;

  /// The document the command produced. `null` until the command has finished
  /// with exit code 0, and for a worker without `out`.
  final String? outputId;

  /// The name of the command's log file, relative to the step's directory.
  /// `null` when there is none.
  final String? log;

  /// This step with [outputId] set: the only change a step ever goes through.
  Step withOutput(String outputId) => Step(
    id: id,
    runId: runId,
    inputId: inputId,
    outputId: outputId,
    log: log,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'runId': runId,
    'inputId': inputId,
    'outputId': outputId,
    'log': log,
  };

  @override
  bool operator ==(Object other) =>
      other is Step &&
      other.id == id &&
      other.runId == runId &&
      other.inputId == inputId &&
      other.outputId == outputId &&
      other.log == log;

  @override
  int get hashCode => Object.hash(id, runId, inputId, outputId, log);

  @override
  String toString() =>
      'Step(id: $id, runId: $runId, inputId: $inputId, outputId: $outputId, '
      'log: $log)';
}

/// Data passed between steps: the input of a launch or the output of a step.
final class Document {
  const Document({
    required this.id,
    required this.sessionId,
    required this.value,
  });

  /// Reads a document from its JSON form.
  ///
  /// The `value` key must be there, but its value may be any JSON, `null`
  /// included. Throws a [FormatException] whose message starts with the field
  /// that is missing or of the wrong kind.
  factory Document.fromJson(Map<String, Object?> json) => Document(
    id: readString(json, 'id'),
    sessionId: readString(json, 'sessionId'),
    value: readValue(json, 'value'),
  );

  final String id;

  /// The session the document belongs to.
  final String sessionId;

  /// Any JSON value.
  final Object? value;

  Map<String, Object?> toJson() => {
    'id': id,
    'sessionId': sessionId,
    'value': value,
  };

  @override
  bool operator ==(Object other) =>
      other is Document &&
      other.id == id &&
      other.sessionId == sessionId &&
      _deep.equals(other.value, value);

  @override
  int get hashCode => Object.hash(id, sessionId, _deep.hash(value));

  @override
  String toString() =>
      'Document(id: $id, sessionId: $sessionId, value: $value)';
}
