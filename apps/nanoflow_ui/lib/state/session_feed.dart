import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nanoflow_model/nanoflow_model.dart';

import 'batched_notifier.dart';

/// A session as the feed has given it so far: the session, its effects, its
/// journal, its documents, its owner.
///
/// The feed keeps adding to it; what it gives out are read-only views.
final class SessionData {
  SessionData(
    this.session, {
    Iterable<Event> events = const [],
    Iterable<Effect> effects = const [],
    Iterable<String> documents = const [],
    Iterable<String> problems = const [],
    this._owner,
    this._alive,
  }) {
    events.forEach(_addEvent);
    effects.forEach(_addEffect);
    _documents.addAll(documents);
    _problems.addAll(problems);
  }

  final Session session;

  String get id => session.id;

  final List<KnownEvent> _events = [];
  final Map<String, Effect> _effects = {};
  final Set<String> _documents = {};
  final List<String> _problems = [];
  Owner? _owner;
  bool? _alive;
  SessionState? _state;
  int _changes = 0;
  Map<String, EffectState>? _statesById;
  List<Effect>? _effectsInOrder;
  Map<String, Effect>? _effectsByKey;

  /// The session's known events in the order of its journal.
  List<KnownEvent> get events => UnmodifiableListView(_events);

  /// The records of the session's effects by id, in the order they were
  /// given. An effect may start before its record is given here: the [state]
  /// has it from its `effect-started`.
  Map<String, Effect> get effects => UnmodifiableMapView(_effects);

  /// The records of the session's effects in the order of their first
  /// `effect-started`; an effect whose record has not been given yet is
  /// left out.
  List<Effect> get effectsInOrder => _effectsInOrder ??= List.unmodifiable([
    for (final effect in state.effects) ?_effects[effect.effectId],
  ]);

  /// The record of the session's effect with [key]; `null` when none has been
  /// given. An effect's `after` is the key of the effect it follows.
  Effect? effectWithKey(String key) => (_effectsByKey ??= {
    for (final effect in _effects.values) effect.key: effect,
  })[key];

  /// The ids of the session's documents that have been written in full.
  Set<String> get documents => UnmodifiableSetView(_documents);

  /// Why the session's journal was read incompletely: lines that are not
  /// events, events this version does not read, files of the session that
  /// could not be read. The session's card marks such a session `Log read
  /// incompletely`.
  List<String> get problems => UnmodifiableListView(_problems);

  bool get incomplete => _problems.isNotEmpty;

  /// The process that owns the session, as the last `owner-changed` tells;
  /// `null` until one has come, and when the session records none.
  Owner? get owner => _owner;

  /// Whether the process of [owner] runs, as the last `owner-changed` tells:
  /// `false` when there is no owner or it is gone; `null` until one has
  /// come, and when that cannot be known.
  bool? get alive => _alive;

  /// Whether the process that ran the session is gone though its journal
  /// has not ended (docs/superpowers/specs/2026-10-03-session-owner-design.md
  /// §6): it shows `Interrupted`, and the effect it was running was
  /// interrupted. Resuming the session goes on with it.
  bool get interrupted =>
      _alive == false && state.status == SessionStatus.running;

  /// The time the session's growing durations reach at [now]: [now], but the
  /// time of its last event once it is [interrupted] — its time stopped
  /// there.
  DateTime timeAt(DateTime now) =>
      interrupted ? _events.lastOrNull?.time ?? now : now;

  /// What replaying the journal says.
  SessionState get state => _state ??= replaySession(_events);

  /// How many events and effect records have been given so far: [state] and
  /// [effects] change only when it grows, so that what is derived from them
  /// can be kept until then.
  int get changes => _changes;

  /// The state of the effect [effectId] in [state]; `null` for an effect that
  /// has not started. Looked up once per [state].
  EffectState? stateOf(String effectId) => (_statesById ??= {
    for (final effect in state.effects) effect.effectId: effect,
  })[effectId];

  void _addEvent(Event event) {
    _changes++;
    switch (event) {
      case UnknownEvent(:final json):
        _problems.add(
          'an event this version does not read: '
          '${jsonEncode(json)}',
        );
      case KnownEvent():
        _events.add(event);
        _state = null;
        _statesById = null;
        _effectsInOrder = null;
    }
  }

  void _addEffect(Effect effect) {
    _changes++;
    _effects[effect.id] = effect;
    _effectsInOrder = null;
    _effectsByKey = null;
  }

  void _owned(OwnerChanged change) {
    _owner = change.owner;
    _alive = change.alive;
  }
}

/// Everything a reader's change feed has given for the `runs` directory of
/// a graph file, indexed: the sessions with their effects, journals,
/// documents and owners.
///
/// Changes may come in any order but one: a session's events come in the
/// order of its journal. What comes before the session it belongs to waits
/// for it.
///
/// Listeners hear of changes at most once per [batch]: a feed gives a large
/// storage thousands of changes at once.
class SessionFeed extends ChangeNotifier with BatchedNotifier {
  /// [sessionPath] gives a session's directory: errors of the feed about
  /// files under it mark that session [SessionData.incomplete].
  SessionFeed(
    Stream<Change> changes, {
    String? Function(String sessionId)? sessionPath,
    this.batch = const Duration(milliseconds: 50),
  }) : _sessionPath = sessionPath ?? ((_) => null) {
    _subscription = changes.listen(_apply, onError: _error);
  }

  /// The changes of [reader], with its session directories, if it has any.
  SessionFeed.read(
    SessionReader reader, {
    Duration batch = const Duration(milliseconds: 50),
  }) : this(reader.changes(), sessionPath: reader.sessionPath, batch: batch);

  @override
  final Duration batch;
  final String? Function(String sessionId) _sessionPath;

  final StreamController<DocumentAdded> _documentsAdded =
      StreamController.broadcast();

  late final StreamSubscription<Change> _subscription;

  final Map<String, SessionData> _sessions = {};

  // What came before the session it belongs to, by the session's id.
  final Map<String, Map<String, Effect>> _waitingEffects = {};
  final Map<String, List<Event>> _waitingEvents = {};
  final Map<String, Set<String>> _waitingDocuments = {};
  final Map<String, List<String>> _waitingProblems = {};
  final Map<String, OwnerChanged> _waitingOwners = {};

  /// Errors of the feed that no session claims.
  final List<String> _problems = [];

  /// The sessions by id, in the order they were given.
  Map<String, SessionData> get sessions => UnmodifiableMapView(_sessions);

  SessionData? session(String id) => _sessions[id];

  /// Each document as the feed gives it: a document that could not be read
  /// before may be readable now.
  Stream<DocumentAdded> get documentsAdded => _documentsAdded.stream;

  /// Files the feed could not read that belong to no session it has given:
  /// a session that is not there for that reason.
  List<String> get problems => UnmodifiableListView(_problems);

  void _apply(Change change) {
    switch (change) {
      case SessionAdded(:final session):
        final owned = _waitingOwners.remove(session.id);
        final data = _sessions[session.id] = SessionData(
          session,
          events: _waitingEvents.remove(session.id) ?? const [],
          effects: _waitingEffects.remove(session.id)?.values ?? const [],
          documents: _waitingDocuments.remove(session.id) ?? const {},
          problems: _waitingProblems.remove(session.id) ?? const [],
          owner: owned?.owner,
          alive: owned?.alive,
        );
        _claimProblems(data);
      case EffectAdded(:final effect) || EffectChanged(:final effect):
        final session = _sessions[effect.sessionId];
        if (session != null) {
          session._addEffect(effect);
        } else {
          (_waitingEffects[effect.sessionId] ??= {})[effect.id] = effect;
        }
      case EventAdded(:final sessionId, :final event):
        final session = _sessions[sessionId];
        if (session != null) {
          session._addEvent(event);
        } else {
          (_waitingEvents[sessionId] ??= []).add(event);
        }
      case DocumentAdded(:final sessionId, :final documentId):
        _documentsAdded.add(change);
        final session = _sessions[sessionId];
        if (session != null) {
          session._documents.add(documentId);
        } else {
          (_waitingDocuments[sessionId] ??= {}).add(documentId);
        }
      case LogCorrupted(:final sessionId, :final line, :final text):
        final problem = 'line $line is not an event: $text';
        final session = _sessions[sessionId];
        if (session != null) {
          session._problems.add(problem);
        } else {
          (_waitingProblems[sessionId] ??= []).add(problem);
        }
      case OwnerChanged(:final sessionId, :final owner, :final alive):
        final session = _sessions[sessionId];
        if (session != null) {
          // Told again as it was: nothing to redraw.
          if (session.owner == owner && session.alive == alive) return;
          session._owned(change);
        } else {
          _waitingOwners[sessionId] = change;
        }
    }
    _changed();
  }

  void _error(Object error, StackTrace stack) {
    final problem = switch (error) {
      FileSystemException(:final path?, :final message, :final osError) =>
        '$path: $message${osError == null ? '' : ' (${osError.message})'}',
      FormatException(:final message) => message,
      _ => '$error',
    };
    final session = _sessions.values
        .where((session) => _isUnder(problem, session))
        .firstOrNull;
    if (session != null) {
      session._problems.add(problem);
    } else {
      _problems.add(problem);
    }
    _changed();
  }

  /// Moves the problems of the feed under [session]'s directory to
  /// [session].
  void _claimProblems(SessionData session) {
    final mine = _problems
        .where((problem) => _isUnder(problem, session))
        .toList();
    if (mine.isEmpty) return;
    session._problems.addAll(mine);
    _problems.removeWhere(mine.contains);
  }

  /// Whether [problem], which starts with a path, is about a file of
  /// [session].
  bool _isUnder(String problem, SessionData session) {
    final dir = _sessionPath(session.id);
    return dir != null &&
        (problem.startsWith('$dir/') || problem.startsWith('$dir:'));
  }

  void _changed() => notifyLater();

  /// Stops listening to the changes; completes once their source has
  /// stopped: a reader's feed, once it no longer watches the processes that
  /// own sessions. [dispose] may come before or after it.
  Future<void> close() => _subscription.cancel();

  @override
  void dispose() {
    unawaited(close());
    unawaited(_documentsAdded.close());
    super.dispose();
  }
}
