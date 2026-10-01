import 'package:collection/collection.dart';

import 'json_fields.dart';
import 'time.dart';

const DeepCollectionEquality _deep = DeepCollectionEquality();

/// One fact in a run's journal.
///
/// The engine only ever appends events, and a run's state is what replaying
/// them gives. Every event of a known kind is a [KnownEvent]: a [RunStarted],
/// [StepStarted], [StepFinished], [RunSplit], [RunFinished] or [RunFailed];
/// anything else is an [UnknownEvent], so a switch over an event covers every
/// case.
sealed class Event {
  const Event();

  /// Reads an event from its JSON form. Never throws.
  ///
  /// An event with a name that is not known, or with a known name and fields
  /// that are missing or of the wrong kind (a `time` that [parseTime] rejects
  /// included), becomes an [UnknownEvent] that writes back the map it was read
  /// from. A journal written by a newer version stays readable that way.
  static Event fromJson(Map<String, Object?> json) {
    try {
      return _parse(json) ?? UnknownEvent(json);
    } on FormatException {
      return UnknownEvent(json);
    }
  }

  /// The value of the `event` field.
  String get name;

  /// The JSON form: `runId`, `time`, `event`, then the event's own fields.
  Map<String, Object?> toJson();
}

/// A known event: one with a run and a time.
///
/// Reading the [runId] or the [time] of any known event takes no switch over
/// its kind.
sealed class KnownEvent extends Event {
  /// The time is kept in UTC with milliseconds, as it is written, so that an
  /// event equals the one read back from its JSON form.
  KnownEvent({required this.runId, required DateTime time})
    : time = DateTime.fromMillisecondsSinceEpoch(
        time.millisecondsSinceEpoch,
        isUtc: true,
      );

  /// The run the event belongs to.
  final String runId;

  /// When the event happened, in UTC.
  final DateTime time;

  /// The fields of the event after `event`, in the documented order.
  Map<String, Object?> get _own;

  @override
  Map<String, Object?> toJson() => {
    'runId': runId,
    'time': formatTime(time),
    'event': name,
    ..._own,
  };

  @override
  bool operator ==(Object other) =>
      other is KnownEvent && _deep.equals(other.toJson(), toJson());

  @override
  int get hashCode => _deep.hash(toJson());

  @override
  String toString() {
    final fields = [
      for (final MapEntry(:key, :value) in toJson().entries)
        if (key != 'event') '$key: $value',
    ];
    return '$runtimeType(${fields.join(', ')})';
  }
}

/// The run was created. The first event of a run.
final class RunStarted extends KnownEvent {
  RunStarted({required super.runId, required super.time, required this.node});

  /// The node the run starts at.
  final String node;

  @override
  String get name => 'run-started';

  @override
  Map<String, Object?> get _own => {'node': node};
}

/// A step's command is about to run. Written again each time the engine
/// restarts the command of an unfinished step.
final class StepStarted extends KnownEvent {
  StepStarted({
    required super.runId,
    required super.time,
    required this.stepId,
    required this.node,
  });

  final String stepId;

  /// The name of the node.
  final String node;

  @override
  String get name => 'step-started';

  @override
  Map<String, Object?> get _own => {'stepId': stepId, 'node': node};
}

/// A step's command ended. This event, and nothing else, records the outcome
/// of a step.
final class StepFinished extends KnownEvent {
  StepFinished({
    required super.runId,
    required super.time,
    required this.stepId,
    required this.exitCode,
    required this.outputId,
  });

  final String stepId;

  /// The exit code of the step's process.
  final int exitCode;

  /// The document the command produced: the data of a worker or the outcome of
  /// a fork. `null` for a worker without `out`, and on failure.
  final String? outputId;

  @override
  String get name => 'step-finished';

  @override
  Map<String, Object?> get _own => {
    'stepId': stepId,
    'exitCode': exitCode,
    'outputId': outputId,
  };
}

/// The run goes on as several new runs. The last event of the run.
final class RunSplit extends KnownEvent {
  RunSplit({required super.runId, required super.time});

  @override
  String get name => 'run-split';

  @override
  Map<String, Object?> get _own => const {};
}

/// The run has nowhere to go. The last event of the run.
final class RunFinished extends KnownEvent {
  RunFinished({required super.runId, required super.time});

  @override
  String get name => 'run-finished';

  @override
  Map<String, Object?> get _own => const {};
}

/// A command failed or a route could not be found. The last event of the run.
final class RunFailed extends KnownEvent {
  RunFailed({
    required super.runId,
    required super.time,
    required this.stepId,
    required this.error,
  });

  /// The step it happened at.
  final String stepId;

  /// One line about what happened.
  final String error;

  @override
  String get name => 'run-failed';

  @override
  Map<String, Object?> get _own => {'stepId': stepId, 'error': error};
}

/// An event this version does not understand: its name is not known, or a
/// field its name requires is missing or of the wrong kind.
///
/// It keeps the map it was read from and writes it back unchanged.
final class UnknownEvent extends Event {
  const UnknownEvent(this.json);

  /// The map the event was read from.
  final Map<String, Object?> json;

  /// The `runId` of the map, or `null` when it has none that is a string.
  String? get runId {
    final value = json['runId'];
    return value is String ? value : null;
  }

  /// The `event` of the map, or an empty string when it has none that is a
  /// string.
  @override
  String get name {
    final value = json['event'];
    return value is String ? value : '';
  }

  @override
  Map<String, Object?> toJson() => json;

  @override
  bool operator ==(Object other) =>
      other is UnknownEvent && _deep.equals(other.json, json);

  @override
  int get hashCode => _deep.hash(json);

  @override
  String toString() => 'UnknownEvent($json)';
}

/// The event of a known name, `null` for any other name.
///
/// Throws a [FormatException] when a field of a known name is missing or of
/// the wrong kind.
Event? _parse(Map<String, Object?> json) {
  final name = json['event'];
  if (name is! String) return null;
  return switch (name) {
    'run-started' => RunStarted(
      runId: readString(json, 'runId'),
      time: readTime(json, 'time'),
      node: readString(json, 'node'),
    ),
    'step-started' => StepStarted(
      runId: readString(json, 'runId'),
      time: readTime(json, 'time'),
      stepId: readString(json, 'stepId'),
      node: readString(json, 'node'),
    ),
    'step-finished' => StepFinished(
      runId: readString(json, 'runId'),
      time: readTime(json, 'time'),
      stepId: readString(json, 'stepId'),
      exitCode: readInt(json, 'exitCode'),
      outputId: readStringOrNull(json, 'outputId'),
    ),
    'run-split' => RunSplit(
      runId: readString(json, 'runId'),
      time: readTime(json, 'time'),
    ),
    'run-finished' => RunFinished(
      runId: readString(json, 'runId'),
      time: readTime(json, 'time'),
    ),
    'run-failed' => RunFailed(
      runId: readString(json, 'runId'),
      time: readTime(json, 'time'),
      stepId: readString(json, 'stepId'),
      error: readString(json, 'error'),
    ),
    _ => null,
  };
}
