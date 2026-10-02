import 'entities.dart';
import 'events.dart';
import 'json_fields.dart';

/// One thing that happened to the sessions in a `runs` directory: an entry of
/// the feed a reader gives.
///
/// The feed is first everything that is already there, then what appears. A
/// change carries a model, or, for a document, only where to ask for it.
sealed class Change {
  const Change();

  /// Reads a change from its JSON form.
  ///
  /// Throws a [FormatException] whose message starts with the place of the
  /// problem, such as `session.id`, for a change that is not known or has a
  /// field that is missing or of the wrong kind. An event inside an
  /// [EventAdded] is the exception: it falls back to an [UnknownEvent].
  static Change fromJson(Map<String, Object?> json) {
    final name = readString(json, 'change');
    return switch (name) {
      'session-added' => SessionAdded(
        _readModel(json, 'session', Session.fromJson),
      ),
      'step-added' => StepAdded(_readModel(json, 'step', Step.fromJson)),
      'step-changed' => StepChanged(_readModel(json, 'step', Step.fromJson)),
      'event-added' => EventAdded(
        sessionId: readString(json, 'sessionId'),
        event: Event.fromJson(readObject(json, 'event')),
      ),
      'document-added' => DocumentAdded(
        sessionId: readString(json, 'sessionId'),
        documentId: readString(json, 'documentId'),
      ),
      'log-corrupted' => LogCorrupted(
        sessionId: readString(json, 'sessionId'),
        line: readInt(json, 'line'),
        text: readString(json, 'text'),
      ),
      _ => throw FormatException('change: unknown "$name"'),
    };
  }

  /// The value of the `change` field.
  String get name;

  /// The JSON form: `change`, then the change's own fields.
  Map<String, Object?> toJson();
}

/// A session appeared.
final class SessionAdded extends Change {
  const SessionAdded(this.session);

  final Session session;

  @override
  String get name => 'session-added';

  @override
  Map<String, Object?> toJson() => {
    'change': name,
    'session': session.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is SessionAdded && other.session == session;

  @override
  int get hashCode => Object.hash(name, session);

  @override
  String toString() => 'SessionAdded($session)';
}

/// A step's record appeared.
final class StepAdded extends Change {
  const StepAdded(this.step);

  final Step step;

  @override
  String get name => 'step-added';

  @override
  Map<String, Object?> toJson() => {'change': name, 'step': step.toJson()};

  @override
  bool operator ==(Object other) => other is StepAdded && other.step == step;

  @override
  int get hashCode => Object.hash(name, step);

  @override
  String toString() => 'StepAdded($step)';
}

/// A step got its `outputId`: the only change to a model already given out.
final class StepChanged extends Change {
  const StepChanged(this.step);

  /// The whole step, with the new `outputId`.
  final Step step;

  @override
  String get name => 'step-changed';

  @override
  Map<String, Object?> toJson() => {'change': name, 'step': step.toJson()};

  @override
  bool operator ==(Object other) => other is StepChanged && other.step == step;

  @override
  int get hashCode => Object.hash(name, step);

  @override
  String toString() => 'StepChanged($step)';
}

/// An event was appended to a session's journal.
final class EventAdded extends Change {
  const EventAdded({required this.sessionId, required this.event});

  /// The session whose journal holds the event.
  final String sessionId;

  /// The event as it is in the journal: an [UnknownEvent] when it is not known.
  final Event event;

  @override
  String get name => 'event-added';

  @override
  Map<String, Object?> toJson() => {
    'change': name,
    'sessionId': sessionId,
    'event': event.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is EventAdded &&
      other.sessionId == sessionId &&
      other.event == event;

  @override
  int get hashCode => Object.hash(name, sessionId, event);

  @override
  String toString() => 'EventAdded(sessionId: $sessionId, event: $event)';
}

/// A document was written in full. Its value is for the reader to give on
/// request.
final class DocumentAdded extends Change {
  const DocumentAdded({required this.sessionId, required this.documentId});

  final String sessionId;

  final String documentId;

  @override
  String get name => 'document-added';

  @override
  Map<String, Object?> toJson() => {
    'change': name,
    'sessionId': sessionId,
    'documentId': documentId,
  };

  @override
  bool operator ==(Object other) =>
      other is DocumentAdded &&
      other.sessionId == sessionId &&
      other.documentId == documentId;

  @override
  int get hashCode => Object.hash(name, sessionId, documentId);

  @override
  String toString() =>
      'DocumentAdded(sessionId: $sessionId, documentId: $documentId)';
}

/// A line of a session's journal that is not an event.
final class LogCorrupted extends Change {
  const LogCorrupted({
    required this.sessionId,
    required this.line,
    required this.text,
  });

  /// The session whose journal has the line.
  final String sessionId;

  /// The number of the line in the journal, counted from 1.
  final int line;

  /// The line as it is.
  final String text;

  @override
  String get name => 'log-corrupted';

  @override
  Map<String, Object?> toJson() => {
    'change': name,
    'sessionId': sessionId,
    'line': line,
    'text': text,
  };

  @override
  bool operator ==(Object other) =>
      other is LogCorrupted &&
      other.sessionId == sessionId &&
      other.line == line &&
      other.text == text;

  @override
  int get hashCode => Object.hash(name, sessionId, line, text);

  @override
  String toString() =>
      'LogCorrupted(sessionId: $sessionId, line: $line, text: $text)';
}

/// The model at [key], read by [fromJson]. A problem inside the model is put
/// under [key]: `session.id: missing`.
T _readModel<T>(
  Map<String, Object?> json,
  String key,
  T Function(Map<String, Object?> json) fromJson,
) {
  final fields = readObject(json, key);
  return inside(key, () => fromJson(fields));
}
