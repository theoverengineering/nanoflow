import 'package:collection/collection.dart';

import 'json_fields.dart';
import 'time.dart';

const DeepCollectionEquality _deep = DeepCollectionEquality();

/// One fact in a session's journal.
///
/// Events are only ever appended, and a session's state is what replaying
/// them gives. Every event of a known kind is a [KnownEvent]: a
/// [SessionStarted], [SessionResumed], [EffectStarted], [EffectFinished],
/// [EffectFailed], [SessionFinished] or [SessionFailed]; anything else is an
/// [UnknownEvent], so a switch over an event covers every case.
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

  /// The JSON form: `time`, `event`, then the event's own fields.
  Map<String, Object?> toJson();
}

/// A known event: one with a time.
///
/// Reading the [time] of any known event takes no switch over its kind.
sealed class KnownEvent extends Event {
  /// The time is kept in UTC with milliseconds, as it is written, so that an
  /// event equals the one read back from its JSON form.
  KnownEvent({required DateTime time})
    : time = DateTime.fromMillisecondsSinceEpoch(
        time.millisecondsSinceEpoch,
        isUtc: true,
      );

  /// When the event happened, in UTC.
  final DateTime time;

  /// The fields of the event after `event`, in the documented order.
  Map<String, Object?> get _own;

  @override
  Map<String, Object?> toJson() => {
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

/// The session was created. The first event of a session.
final class SessionStarted extends KnownEvent {
  SessionStarted({required super.time, required this.code});

  /// The hash of the code that runs the session; `null` when it could not be
  /// computed.
  final String? code;

  @override
  String get name => 'session-started';

  @override
  Map<String, Object?> get _own => {'code': code};
}

/// The session goes on after its process ended: written on every resume.
final class SessionResumed extends KnownEvent {
  SessionResumed({
    required super.time,
    required this.code,
    required this.graphId,
  });

  /// The hash of the code that runs the session now; `null` when it could
  /// not be computed.
  final String? code;

  /// The document with a new snapshot of the graph file, when the code is
  /// not the one last written; otherwise `null`.
  final String? graphId;

  @override
  String get name => 'session-resumed';

  @override
  Map<String, Object?> get _own => {'code': code, 'graphId': graphId};
}

/// An effect begins to run live. Written again each time it runs again.
final class EffectStarted extends KnownEvent {
  EffectStarted({required super.time, required this.effectId});

  final String effectId;

  @override
  String get name => 'effect-started';

  @override
  Map<String, Object?> get _own => {'effectId': effectId};
}

/// An effect returned a value. This event, and not `effect.json`, records it.
final class EffectFinished extends KnownEvent {
  EffectFinished({
    required super.time,
    required this.effectId,
    required this.outputId,
  });

  final String effectId;

  /// The document with the value the effect returned.
  final String? outputId;

  @override
  String get name => 'effect-finished';

  @override
  Map<String, Object?> get _own => {'effectId': effectId, 'outputId': outputId};
}

/// An effect threw. The exception goes on into the workflow's code, or to
/// the failure route that catches it.
final class EffectFailed extends KnownEvent {
  EffectFailed({
    required super.time,
    required this.effectId,
    required this.error,
    required this.stack,
    this.errorType,
  });

  final String effectId;

  /// The exception's text, on one line.
  final String error;

  /// The stack trace's text.
  final String stack;

  /// The name of the exception's type, `StateError`, which a failure route
  /// gets with [error] on resume too; `null` in a journal written before
  /// it was kept. Written only when set.
  final String? errorType;

  @override
  String get name => 'effect-failed';

  @override
  Map<String, Object?> get _own => {
    'effectId': effectId,
    'error': error,
    'stack': stack,
    if (errorType != null) 'errorType': errorType,
  };
}

/// The workflow function returned a value. The last event of a session.
final class SessionFinished extends KnownEvent {
  SessionFinished({required super.time, required this.outputId});

  /// The document with the value the workflow returned.
  final String? outputId;

  @override
  String get name => 'session-finished';

  @override
  Map<String, Object?> get _own => {'outputId': outputId};
}

/// The workflow function threw. The last event of a session.
final class SessionFailed extends KnownEvent {
  SessionFailed({
    required super.time,
    required this.error,
    required this.stack,
  });

  /// The exception's text, on one line.
  final String error;

  /// The stack trace's text.
  final String stack;

  @override
  String get name => 'session-failed';

  @override
  Map<String, Object?> get _own => {'error': error, 'stack': stack};
}

/// An event this version does not understand: its name is not known, or a
/// field its name requires is missing or of the wrong kind.
///
/// It keeps the map it was read from and writes it back unchanged.
final class UnknownEvent extends Event {
  const UnknownEvent(this.json);

  /// The map the event was read from.
  final Map<String, Object?> json;

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
    'session-started' => SessionStarted(
      time: readTime(json, 'time'),
      code: readStringOrNull(json, 'code'),
    ),
    'session-resumed' => SessionResumed(
      time: readTime(json, 'time'),
      code: readStringOrNull(json, 'code'),
      graphId: readStringOrNull(json, 'graphId'),
    ),
    'effect-started' => EffectStarted(
      time: readTime(json, 'time'),
      effectId: readString(json, 'effectId'),
    ),
    'effect-finished' => EffectFinished(
      time: readTime(json, 'time'),
      effectId: readString(json, 'effectId'),
      outputId: readStringOrNull(json, 'outputId'),
    ),
    'effect-failed' => EffectFailed(
      time: readTime(json, 'time'),
      effectId: readString(json, 'effectId'),
      error: readString(json, 'error'),
      stack: readString(json, 'stack'),
      // Kept since failure routes; an older journal has none.
      errorType: json.containsKey('errorType')
          ? readStringOrNull(json, 'errorType')
          : null,
    ),
    'session-finished' => SessionFinished(
      time: readTime(json, 'time'),
      outputId: readStringOrNull(json, 'outputId'),
    ),
    'session-failed' => SessionFailed(
      time: readTime(json, 'time'),
      error: readString(json, 'error'),
      stack: readString(json, 'stack'),
    ),
    _ => null,
  };
}
