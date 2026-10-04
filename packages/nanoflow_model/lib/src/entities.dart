import 'package:collection/collection.dart';

import 'json_fields.dart';

const DeepCollectionEquality _deep = DeepCollectionEquality();

/// One call of a workflow function, with its own journal.
///
/// The start time is not a field: it is the time of the journal's
/// `session-started`.
final class Session {
  const Session({
    required this.id,
    required this.workflow,
    required this.graph,
    required this.inputId,
  });

  /// Reads a session from its JSON form.
  ///
  /// Throws a [FormatException] whose message starts with the field that is
  /// missing or of the wrong kind.
  factory Session.fromJson(Map<String, Object?> json) => Session(
    id: readString(json, 'id'),
    workflow: readString(json, 'workflow'),
    graph: readObjectOrNull(json, 'graph'),
    inputId: readStringOrNull(json, 'inputId'),
  );

  final String id;

  /// The name of the workflow function.
  final String workflow;

  /// The graph file as it was when the session was created, as raw JSON;
  /// `null` when there was none.
  final Map<String, Object?>? graph;

  /// The document with the workflow's input; `null` when there is none.
  final String? inputId;

  Map<String, Object?> toJson() => {
    'id': id,
    'workflow': workflow,
    'graph': graph,
    'inputId': inputId,
  };

  @override
  bool operator ==(Object other) =>
      other is Session &&
      other.id == id &&
      other.workflow == workflow &&
      _deep.equals(other.graph, graph) &&
      other.inputId == inputId;

  @override
  int get hashCode => Object.hash(id, workflow, _deep.hash(graph), inputId);

  @override
  String toString() =>
      'Session(id: $id, workflow: $workflow, graph: $graph, '
      'inputId: $inputId)';
}

/// One call of `f.effect` that ran live: its record, kept when the effect runs
/// again after a crash.
final class Effect {
  const Effect({
    required this.id,
    required this.sessionId,
    required this.name,
    required this.key,
    required this.after,
    required this.place,
    required this.outputId,
    required this.log,
  });

  /// Reads an effect from its JSON form.
  ///
  /// Throws a [FormatException] whose message starts with the field that is
  /// missing or of the wrong kind.
  factory Effect.fromJson(Map<String, Object?> json) => Effect(
    id: readString(json, 'id'),
    sessionId: readString(json, 'sessionId'),
    name: readString(json, 'name'),
    key: readString(json, 'key'),
    after: readStringOrNull(json, 'after'),
    place: readStringOrNull(json, 'place'),
    outputId: readStringOrNull(json, 'outputId'),
    log: readString(json, 'log'),
  );

  final String id;

  /// The session the effect belongs to.
  final String sessionId;

  /// The name given to `f.effect`.
  final String name;

  /// The key that finds the effect again when the session goes on after a
  /// crash: `collect#1@e3b0c44298fc1c14`.
  final String key;

  /// The key of the effect adopted last before this one in its context, in
  /// the call it was last started in; `null` for an effect with none before it.
  final String? after;

  /// Where `f.effect` was called: `path:line`; `null` when not known.
  final String? place;

  /// The document with the effect's result. `null` until the effect has
  /// finished; the journal's `effect-finished` is what tells, this is a copy.
  final String? outputId;

  /// The name of the effect's log file, relative to the effect's directory.
  final String log;

  /// This effect with [outputId] set: it has finished.
  Effect withOutput(String outputId) => Effect(
    id: id,
    sessionId: sessionId,
    name: name,
    key: key,
    after: after,
    place: place,
    outputId: outputId,
    log: log,
  );

  /// This effect with [after] set: it runs again, after a resume, in a call
  /// that follows another effect than the call it ran in before.
  Effect withAfter(String? after) => Effect(
    id: id,
    sessionId: sessionId,
    name: name,
    key: key,
    after: after,
    place: place,
    outputId: outputId,
    log: log,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'sessionId': sessionId,
    'name': name,
    'key': key,
    'after': after,
    'place': place,
    'outputId': outputId,
    'log': log,
  };

  @override
  bool operator ==(Object other) =>
      other is Effect &&
      other.id == id &&
      other.sessionId == sessionId &&
      other.name == name &&
      other.key == key &&
      other.after == after &&
      other.place == place &&
      other.outputId == outputId &&
      other.log == log;

  @override
  int get hashCode =>
      Object.hash(id, sessionId, name, key, after, place, outputId, log);

  @override
  String toString() =>
      'Effect(id: $id, sessionId: $sessionId, name: $name, key: $key, '
      'after: $after, place: $place, outputId: $outputId, log: $log)';
}

/// Data of a session: the input of the workflow, the result of an effect or of
/// the workflow, a snapshot of the graph.
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
