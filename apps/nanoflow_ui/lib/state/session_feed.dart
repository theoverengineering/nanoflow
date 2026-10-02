import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_reader/nanoflow_reader.dart';

import 'batched_notifier.dart';

/// A run as the feed has given it so far: the run, its steps, its journal.
///
/// The feed keeps adding to it; what it gives out are read-only views.
final class RunData {
  RunData(
    this.run, {
    Iterable<Event> events = const [],
    Iterable<Step> steps = const [],
    Iterable<String> problems = const [],
  }) {
    events.forEach(_addEvent);
    for (final step in steps) {
      _steps[step.id] = step;
    }
    _problems.addAll(problems);
  }

  final Run run;

  String get id => run.id;

  final List<KnownEvent> _events = [];
  final Map<String, Step> _steps = {};
  final List<String> _problems = [];
  final Map<String, StepFinished> _finishes = {};
  RunStarted? _started;
  RunState? _state;

  /// The run's known events in the order of its journal.
  List<KnownEvent> get events => UnmodifiableListView(_events);

  /// The run's steps by id, in the order they were given. A step may start
  /// before it is given here: the [state] has it from its `step-started`.
  Map<String, Step> get steps => UnmodifiableMapView(_steps);

  /// Why the run's journal was read incompletely: lines that are not events,
  /// events this version does not read, files of the run that could not be
  /// read. The app marks such a run `Log read incompletely`.
  List<String> get problems => UnmodifiableListView(_problems);

  bool get incomplete => _problems.isNotEmpty;

  /// What replaying the journal says.
  RunState get state => _state ??= replay(run.id, _events);

  /// The run's `run-started`; `null` before it is given.
  RunStarted? get started => _started;

  /// The `step-finished` of the step [stepId], or `null`.
  StepFinished? finishOf(String stepId) => _finishes[stepId];

  void _addEvent(Event event) {
    switch (event) {
      case UnknownEvent(:final json):
        _problems.add(
          'an event this version does not read: '
          '${jsonEncode(json)}',
        );
        return;
      case KnownEvent():
        _events.add(event);
        _state = null;
    }
    switch (event) {
      case RunStarted():
        _started ??= event;
      case StepFinished(:final stepId):
        _finishes[stepId] = event;
      default:
    }
  }
}

/// A session as the feed has given it so far.
final class SessionData {
  SessionData(
    this.session, {
    Iterable<RunData> runs = const [],
    Iterable<String> documents = const [],
  }) {
    runs.forEach(_addRun);
    _documents.addAll(documents);
  }

  final Session session;

  String get id => session.id;

  final Map<String, RunData> _runs = {};
  final Set<String> _documents = {};

  /// The session's runs by id, in the order they were given.
  Map<String, RunData> get runs => UnmodifiableMapView(_runs);

  /// The ids of the session's documents that have been written in full.
  Set<String> get documents => UnmodifiableSetView(_documents);

  /// The graph the session runs by, or `null` when what it holds is not a
  /// graph.
  late final Graph? graph = _parseGraph();

  Graph? _parseGraph() {
    try {
      return Graph.fromJson(session.graph);
    } on FormatException {
      return null;
    }
  }

  void _addRun(RunData run) => _runs[run.id] = run;
}

/// Everything a reader's change feed has given for one graph, indexed: the
/// sessions, their runs, the runs' steps and journals, the documents.
///
/// Changes may come in any order but one: a run's events come in the order of
/// its journal. What comes before the thing it belongs to waits for it.
///
/// Listeners hear of changes at most once per [batch]: a feed gives a large
/// storage thousands of changes at once.
class SessionFeed extends ChangeNotifier with BatchedNotifier {
  /// [runPath] gives a run's directory: errors of the feed about files under
  /// it mark that run [RunData.incomplete].
  ///
  /// The feed is [loading] at first, until it has been quiet for [settle], or
  /// for [maxLoading] at most: a reader gives what is on disk all at once,
  /// then new changes as they come.
  SessionFeed(
    Stream<Change> changes, {
    String? Function(String runId)? runPath,
    this.batch = const Duration(milliseconds: 50),
    this.settle = const Duration(milliseconds: 300),
    Duration maxLoading = const Duration(seconds: 5),
  }) : _runPath = runPath ?? ((_) => null) {
    _subscription = changes.listen(_apply, onError: _error);
    _settling = Timer(settle, _loaded);
    _loadingCap = Timer(maxLoading, _loaded);
  }

  /// The changes of [reader], with its run directories.
  SessionFeed.read(
    FsReader reader, {
    Duration batch = const Duration(milliseconds: 50),
    Duration settle = const Duration(milliseconds: 300),
    Duration maxLoading = const Duration(seconds: 5),
  }) : this(
         reader.changes(),
         runPath: reader.runPath,
         batch: batch,
         settle: settle,
         maxLoading: maxLoading,
       );

  @override
  final Duration batch;

  final Duration settle;
  final String? Function(String runId) _runPath;

  late final StreamSubscription<Change> _subscription;
  late Timer _settling;
  late final Timer _loadingCap;
  bool _loading = true;

  final Map<String, SessionData> _sessions = {};
  final Map<String, RunData> _runs = {};

  // What came before the thing it belongs to, by the id of that thing.
  final Map<String, List<RunData>> _waitingRuns = {};
  final Map<String, Set<String>> _waitingDocuments = {};
  final Map<String, List<Step>> _waitingSteps = {};
  final Map<String, List<Event>> _waitingEvents = {};
  final Map<String, List<String>> _waitingProblems = {};

  /// Errors of the feed that no run claims.
  final List<String> _problems = [];

  /// The sessions by id, in the order they were given.
  Map<String, SessionData> get sessions => UnmodifiableMapView(_sessions);

  SessionData? session(String id) => _sessions[id];

  /// Whether the feed is still giving what was on disk when it started.
  bool get loading => _loading;

  /// Files the feed could not read that belong to no run it has given: a
  /// session or a run that is not there for that reason.
  List<String> get problems => UnmodifiableListView(_problems);

  void _apply(Change change) {
    switch (change) {
      case SessionAdded(:final session):
        _sessions[session.id] = SessionData(
          session,
          runs: _waitingRuns.remove(session.id) ?? const [],
          documents: _waitingDocuments.remove(session.id) ?? const {},
        );
      case RunAdded(:final run):
        final data = _runs[run.id] = RunData(
          run,
          events: _waitingEvents.remove(run.id) ?? const [],
          steps: _waitingSteps.remove(run.id) ?? const [],
          problems: _waitingProblems.remove(run.id) ?? const [],
        );
        _claimProblems(data);
        final session = _sessions[run.sessionId];
        if (session != null) {
          session._addRun(data);
        } else {
          (_waitingRuns[run.sessionId] ??= []).add(data);
        }
      case StepAdded(:final step) || StepChanged(:final step):
        final run = _runs[step.runId];
        if (run != null) {
          run._steps[step.id] = step;
        } else {
          final waiting = _waitingSteps[step.runId] ??= [];
          waiting
            ..removeWhere((s) => s.id == step.id)
            ..add(step);
        }
      case EventAdded(:final event):
        final runId = switch (event) {
          KnownEvent(:final runId) => runId,
          UnknownEvent(:final runId) => runId,
        };
        if (runId == null) break;
        final run = _runs[runId];
        if (run != null) {
          run._addEvent(event);
        } else {
          (_waitingEvents[runId] ??= []).add(event);
        }
      case DocumentAdded(:final sessionId, :final documentId):
        final session = _sessions[sessionId];
        if (session != null) {
          session._documents.add(documentId);
        } else {
          (_waitingDocuments[sessionId] ??= {}).add(documentId);
        }
      case LogCorrupted(:final runId, :final line, :final text):
        _addProblem(runId, 'line $line is not an event: $text');
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
    final run = _runs.values.where((run) => _isUnder(problem, run)).firstOrNull;
    if (run != null) {
      run._problems.add(problem);
    } else {
      _problems.add(problem);
    }
    _changed();
  }

  /// Moves the problems of the feed under [run]'s directory to [run].
  void _claimProblems(RunData run) {
    final mine = _problems.where((problem) => _isUnder(problem, run)).toList();
    if (mine.isEmpty) return;
    run._problems.addAll(mine);
    _problems.removeWhere(mine.contains);
  }

  /// Whether [problem], which starts with a path, is about a file of [run].
  bool _isUnder(String problem, RunData run) {
    final dir = _runPath(run.id);
    return dir != null &&
        (problem.startsWith('$dir/') || problem.startsWith('$dir:'));
  }

  void _addProblem(String runId, String problem) {
    final run = _runs[runId];
    if (run != null) {
      run._problems.add(problem);
    } else {
      (_waitingProblems[runId] ??= []).add(problem);
    }
  }

  void _changed() {
    if (_loading) {
      _settling.cancel();
      _settling = Timer(settle, _loaded);
    }
    notifyLater();
  }

  void _loaded() {
    if (!_loading) return;
    _loading = false;
    _settling.cancel();
    _loadingCap.cancel();
    notifyNow();
  }

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    _settling.cancel();
    _loadingCap.cancel();
    super.dispose();
  }
}
