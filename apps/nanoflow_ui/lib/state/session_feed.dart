import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_reader/nanoflow_reader.dart';

import 'batched_notifier.dart';

/// A session as the feed has given it so far: the session, its steps, its
/// journal, its documents.
///
/// The feed keeps adding to it; what it gives out are read-only views.
final class SessionData {
  SessionData(
    this.session, {
    Iterable<Event> events = const [],
    Iterable<Step> steps = const [],
    Iterable<String> documents = const [],
    Iterable<String> problems = const [],
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
  SessionState? _state;
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

  /// What replaying the journal says.
  SessionState get state => _state ??= replaySession(_events);

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
        _stepsInOrder = null;
    }
  }

  void _addStep(Step step) {
    _steps[step.id] = step;
    _stepsInOrder = null;
    _stepsByKey = null;
  }
}

/// Everything a reader's change feed has given for the `runs` directory of
/// a graph file, indexed: the sessions with their steps, journals and
/// documents.
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
        final data = _sessions[session.id] = SessionData(
          session,
          events: _waitingEvents.remove(session.id) ?? const [],
          steps: _waitingSteps.remove(session.id)?.values ?? const [],
          documents: _waitingDocuments.remove(session.id) ?? const {},
          problems: _waitingProblems.remove(session.id) ?? const [],
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

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    unawaited(_documentsAdded.close());
    super.dispose();
  }
}
