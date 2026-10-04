import 'entities.dart';
import 'events.dart';
import 'json_fields.dart';
import 'owner.dart';

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
      'effect-added' => EffectAdded(
        _readModel(json, 'effect', Effect.fromJson),
      ),
      'effect-changed' => EffectChanged(
        _readModel(json, 'effect', Effect.fromJson),
      ),
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
      'owner-changed' => OwnerChanged(
        sessionId: readString(json, 'sessionId'),
        owner: _readOwner(json),
        alive: readBoolOrNull(json, 'alive'),
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

/// An effect's record appeared.
final class EffectAdded extends Change {
  const EffectAdded(this.effect);

  final Effect effect;

  @override
  String get name => 'effect-added';

  @override
  Map<String, Object?> toJson() => {'change': name, 'effect': effect.toJson()};

  @override
  bool operator ==(Object other) =>
      other is EffectAdded && other.effect == effect;

  @override
  int get hashCode => Object.hash(name, effect);

  @override
  String toString() => 'EffectAdded($effect)';
}

/// The record of an effect was rewritten: it got the `outputId` of its
/// `effect-finished`, or another `after` as it runs again. The only change to
/// a model already given out.
final class EffectChanged extends Change {
  const EffectChanged(this.effect);

  /// The whole effect, as it is now.
  final Effect effect;

  @override
  String get name => 'effect-changed';

  @override
  Map<String, Object?> toJson() => {'change': name, 'effect': effect.toJson()};

  @override
  bool operator ==(Object other) =>
      other is EffectChanged && other.effect == effect;

  @override
  int get hashCode => Object.hash(name, effect);

  @override
  String toString() => 'EffectChanged($effect)';
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

/// Who owns a session, or that nobody does, changed, or whether the owner is
/// alive became known. Given for a session whose journal has not ended: once
/// it ends, the owner no longer matters.
final class OwnerChanged extends Change {
  const OwnerChanged({
    required this.sessionId,
    required this.owner,
    required this.alive,
  });

  /// The session the owner is of.
  final String sessionId;

  /// The owner as the session's `.owner.lock` records it; `null` when it
  /// records none: the session is released, or a version without owners wrote
  /// it.
  final Owner? owner;

  /// Whether the process of [owner] is running: `false` when there is no
  /// owner, the process is gone or its pid belongs to another process now;
  /// `null` when that cannot be known here.
  final bool? alive;

  @override
  String get name => 'owner-changed';

  @override
  Map<String, Object?> toJson() => {
    'change': name,
    'sessionId': sessionId,
    'owner': owner?.toJson(),
    'alive': alive,
  };

  @override
  bool operator ==(Object other) =>
      other is OwnerChanged &&
      other.sessionId == sessionId &&
      other.owner == owner &&
      other.alive == alive;

  @override
  int get hashCode => Object.hash(name, sessionId, owner, alive);

  @override
  String toString() =>
      'OwnerChanged(sessionId: $sessionId, owner: $owner, alive: $alive)';
}

/// The owner at `owner`, or `null`. A problem inside it is put under
/// `owner`: `owner.pid: missing`.
Owner? _readOwner(Map<String, Object?> json) {
  final fields = readObjectOrNull(json, 'owner');
  if (fields == null) return null;
  return inside('owner', () => Owner.fromJson(fields));
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
