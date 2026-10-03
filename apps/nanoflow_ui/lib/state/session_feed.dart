import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_reader/nanoflow_reader.dart';

import 'batched_notifier.dart';

/// A session as the feed has given it so far: the session, its steps, its
/// journal, its documents, its owner.
///
/// The feed keeps adding to it; what it gives out are read-only views.
final class SessionData {
  SessionData(
    this.session, {
    Iterable<Event> events = const [],
    Iterable<Step> steps = const [],
    Iterable<String> documents = const [],
    Iterable<String> problems = const [],
    this._owner,
    this._alive,
  }) {
    events.forEach(_addEvent);
    steps.forEach(_addStep);
    _documents.addAll(documents);
    _problems.addAll(problems);
  }

  final Session session;

  String get id => session.id;

  final List<KnownEvent> _events = [];
  final Map<String, Step> _steps = {};
  final Set<String> _documents = {};
  final List<String> _problems = [];
  Owner? _owner;
  bool? _alive;
  SessionState? _state;
  Map<String, StepState>? _statesById;
  List<Step>? _stepsInOrder;
  Map<String, Step>? _stepsByKey;

  /// The session's known events in the order of its journal.
  List<KnownEvent> get events => UnmodifiableListView(_events);

  /// The records of the session's steps by id, in the order they were
  /// given. A step may start before its record is given here: the [state]
  /// has it from its `step-started`.
  Map<String, Step> get steps => UnmodifiableMapView(_steps);

  /// The records of the session's steps in the order of their first
  /// `step-started`; a step whose record has not been given yet is left out.
  List<Step> get stepsInOrder => _stepsInOrder ??= List.unmodifiable([
    for (final step in state.steps) ?_steps[step.stepId],
  ]);

  /// The record of the session's step with [key]; `null` when none has been
  /// given. A step's `after` is the key of the step it follows.
  Step? stepWithKey(String key) =>
      (_stepsByKey ??= {for (final step in _steps.values) step.key: step})[key];

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
  /// §6): it shows `Interrupted`, and the step it was running was
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

  /// The state of the step [stepId] in [state]; `null` for a step that has
  /// not started. Looked up once per [state]: the copies of a frame look
  /// up the first step of each.
  StepState? stateOf(String stepId) => (_statesById ??= {
    for (final step in state.steps) step.stepId: step,
  })[stepId];

  void _addEvent(Event event) {
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
        _stepsInOrder = null;
    }
  }

  void _addStep(Step step) {
    _steps[step.id] = step;
    _stepsInOrder = null;
    _stepsByKey = null;
  }

  void _owned(OwnerChanged change) {
    _owner = change.owner;
    _alive = change.alive;
  }
}

/// Everything a reader's change feed has given for the `runs` directory of
/// a graph file, indexed: the sessions with their steps, journals,
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

  /// The changes of [reader], with its session directories.
  SessionFeed.read(
    FsReader reader, {
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
  final Map<String, Map<String, Step>> _waitingSteps = {};
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
          steps: _waitingSteps.remove(session.id)?.values ?? const [],
          documents: _waitingDocuments.remove(session.id) ?? const {},
          problems: _waitingProblems.remove(session.id) ?? const [],
          owner: owned?.owner,
          alive: owned?.alive,
        );
        _claimProblems(data);
      case StepAdded(:final step) || StepChanged(:final step):
        final session = _sessions[step.sessionId];
        if (session != null) {
          session._addStep(step);
        } else {
          (_waitingSteps[step.sessionId] ??= {})[step.id] = step;
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
