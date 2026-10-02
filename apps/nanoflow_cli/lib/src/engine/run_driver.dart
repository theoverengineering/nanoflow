import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_store/nanoflow_store.dart';

import '../program.dart';
import 'carried_data.dart';
import 'progress.dart';
import 'step_process.dart';

/// What the runs of a session share while the engine drives them.
final class DrivenSession {
  DrivenSession({
    required this.store,
    required this.graph,
    required this.program,
    required this.progress,
    required this.clock,
  });

  final SessionHandle store;

  /// The graph the session goes by.
  final Graph graph;

  final GraphProgram program;

  final Progress progress;

  /// The time of the events the engine writes.
  final Clock clock;

  /// The `--call`s that are running.
  final Set<StepCall> calls = {};

  /// Whether a run has failed.
  bool anyFailed = false;

  final _stopped = Completer<void>();

  /// Whether the engine is stopping: it writes no more events and starts no
  /// more steps.
  bool get stopping => _stopped.isCompleted;

  /// Completes once the engine begins to stop.
  Future<void> get stopped => _stopped.future;

  /// Begins to stop: see [stopping].
  void stop() {
    if (!_stopped.isCompleted) _stopped.complete();
  }

  /// Why the session could not be written or read — its directory is gone,
  /// the disk is full, it may not be written — once that happened.
  FileSystemException? get storageFailure => _storageFailure;
  FileSystemException? _storageFailure;

  final _failed = Completer<void>();

  /// Completes once the session could not be written or read.
  Future<void> get failed => _failed.future;

  /// [driving], a run being driven, with a failure to write or read the
  /// session caught: the first such failure becomes [storageFailure], and
  /// the engine begins to stop. Other errors pass through.
  Future<void> guard(Future<void> driving) =>
      driving.catchError((Object error) {
        if (_failed.isCompleted) return;
        _storageFailure = error as FileSystemException;
        stop();
        _failed.complete();
      }, test: (error) => error is FileSystemException);

  /// Appends [event] to the journal of its run and reports it, unless the
  /// engine is stopping; gives whether it did. [node] and [children] are for
  /// [Progress.report].
  Future<bool> record(
    KnownEvent event, {
    String? node,
    List<RunStarted> children = const [],
  }) async {
    if (stopping) return false;
    await store.appendEvent(event);
    progress.report(event, node: node, children: children);
    return true;
  }
}

/// How long a run waits for the engine to begin stopping after a call ended
/// the way SIGINT or SIGTERM ends one.
const _signalGrace = Duration(milliseconds: 250);

/// Whether a call that exited with [exitCode] ended the way SIGINT or
/// SIGTERM ends one: killed by the signal (a negative code), or exiting with
/// `128 + N`, as a `--call` does when it stops on signal `N`.
bool _endedBySignal(int exitCode) =>
    [ProcessSignal.sigint, ProcessSignal.sigterm].any(
      (signal) =>
          exitCode == -signal.signalNumber ||
          exitCode == 128 + signal.signalNumber,
    );

/// How a step that finished turned out, which decides where its run goes:
/// the line of `run-failed` when it failed; otherwise its output document,
/// and for a fork the outcome it printed.
typedef StepResult = ({String? error, String? outputId, Object? outcome});

/// A run that a split created: its id, its first step and its
/// `run-started`.
typedef SplitChild = ({String runId, Step first, RunStarted started});

/// A step a run is to take: [step], at [node], into which the run carries
/// [carried].
typedef _Next = ({Step step, Node node, String? carried});

/// Drives one run, a step at a time, until it finishes, fails or splits;
/// then drives the runs its split created, all at once.
final class RunDriver {
  /// The driver of the run [_runId].
  ///
  /// [nextStep] and [children] are what an engine that stopped had made for
  /// the run's next move: the step of its next node (D6), or runs of its
  /// split, by the node they start at. The run takes them instead of making
  /// them again.
  RunDriver(
    this._session,
    this._runId, {
    this._nextStep,
    this._children = const {},
  });

  final DrivenSession _session;
  final String _runId;
  Step? _nextStep;
  final Map<String, SplitChild> _children;

  SessionHandle get _store => _session.store;

  /// Drives the run from [step], a step of [node] that is to start — for the
  /// first time, or again when it did not finish — into which the run
  /// carries [carried].
  ///
  /// Completes when the run and every run its split created have ended, or
  /// the engine is stopping.
  Future<void> drive(
    Step step, {
    required Node node,
    required String? carried,
  }) async {
    _Next? next = (step: step, node: node, carried: carried);
    while (next != null) {
      final (:step, :node, :carried) = next;
      final result = await _take(step, node);
      if (result == null) return;
      next = await _goOn(
        step,
        node,
        result,
        carried: carriedAfter(
          node,
          carried: carried,
          outputId: result.outputId,
        ),
      );
    }
  }

  /// Drives the run on from [step], a step of [node] that finished as
  /// [result], after which the run carries [carried].
  ///
  /// Completes as [drive] does.
  Future<void> goOn(
    Step step, {
    required Node node,
    required StepResult result,
    required String? carried,
  }) async {
    final next = await _goOn(step, node, result, carried: carried);
    if (next == null) return;
    await drive(next.step, node: next.node, carried: next.carried);
  }

  /// Takes [step], a step of [node]: `step-started`, the call, the output
  /// document, `step-finished`, then the output in `step.json`. Gives how
  /// the step turned out, or `null` when the run has failed because the
  /// program did not start, or the engine is stopping.
  Future<StepResult?> _take(Step step, Node node) async {
    if (!await _session.record(
      StepStarted(
        runId: _runId,
        time: _session.clock(),
        stepId: step.id,
        node: node.name,
      ),
    )) {
      return null;
    }
    final CallEnd? end;
    try {
      end = await _call(step, node);
    } on GraphProgramStartException catch (e) {
      // The step never ran: no `step-finished`.
      await _fail(step, 'cannot start the graph program: ${e.reason}');
      return null;
    }
    if (end == null) return null;
    final (:error, :printed) = _judge(node, end);
    // The output first, then the event that refers to it, then the step.
    final outputId = printed == null
        ? null
        : await _store.writeDocument(printed.value);
    if (!await _session.record(
      StepFinished(
        runId: _runId,
        time: _session.clock(),
        stepId: step.id,
        exitCode: end.exitCode,
        outputId: outputId,
      ),
      node: node.name,
    )) {
      return null;
    }
    if (outputId != null) await _store.setStepOutput(step, outputId);
    return (error: error, outputId: outputId, outcome: printed?.value);
  }

  /// Where the run goes after [step], a step of [node] that turned out as
  /// [result], after which the run carries [carried]: the run fails,
  /// finishes or splits, and the next step is `null`; or it goes on to the
  /// next step.
  Future<_Next?> _goOn(
    Step step,
    Node node,
    StepResult result, {
    required String? carried,
  }) async {
    if (result.error case final error?) {
      await _fail(step, error);
      return null;
    }
    switch (_route(node, result.outcome)) {
      case RouteMissing(:final outcome):
        await _fail(step, 'no target for outcome ${jsonEncode(outcome)}');
        return null;
      case RouteEnd():
      case RouteTo(:final target) when target.isEmpty:
        await _session.record(
          RunFinished(runId: _runId, time: _session.clock()),
        );
        return null;
      case RouteTo(:final target) when target.isList:
        await _split(target.names, carried);
        return null;
      case RouteTo(:final target):
        if (_session.stopping) return null;
        final next = _session.graph[target.names.single]!;
        final nextStep =
            _nextStep ??
            await _store.createStep(
              runId: _runId,
              node: next.name,
              inputId: inputIdOf(next, carried),
            );
        _nextStep = null;
        return (step: nextStep, node: next, carried: carried);
    }
  }

  /// Runs the `--call` of [step], a step of [node], with the step's log open;
  /// gives how it ended, or `null` when the engine is stopping.
  ///
  /// Throws a [GraphProgramStartException] when the program does not start.
  Future<CallEnd?> _call(Step step, Node node) async {
    final input = await inputLine(_store, step);
    final log = _store.openLog(_runId, step.id);
    try {
      final call = await StepCall.start(
        _session.program,
        node,
        input: input,
        log: log,
      );
      _session.calls.add(call);
      // The engine began to stop while the call was starting.
      if (_session.stopping) call.stop();
      try {
        final end = await call.ended;
        if (!_session.stopping && _endedBySignal(end.exitCode)) {
          // A terminal's Ctrl+C reaches the calls along with the engine, and
          // a call may end of it before the engine has seen its own signal.
          // The engine gets a moment to begin stopping, so that the step is
          // not written as failed.
          await _session.stopped.timeout(_signalGrace, onTimeout: () {});
        }
        return _session.stopping ? null : end;
      } finally {
        _session.calls.remove(call);
      }
    } finally {
      await log.close();
    }
  }

  /// Ends the run with `run-failed` at [step].
  Future<void> _fail(Step step, String error) async {
    final failed = await _session.record(
      RunFailed(
        runId: _runId,
        time: _session.clock(),
        stepId: step.id,
        error: error,
      ),
    );
    if (failed) _session.anyFailed = true;
  }

  /// Makes a run for each of [nodes], whose parent is this run, unless it was
  /// made before; writes `run-split`; and drives the runs all at once.
  /// [carried] is the document this run carries into them.
  Future<void> _split(List<String> nodes, String? carried) async {
    final children = <SplitChild>[];
    for (final node in nodes) {
      if (_session.stopping) return;
      final child = _children[node] ?? await _createChild(node, carried);
      _session.progress.report(child.started);
      children.add(child);
    }
    final split = await _session.record(
      RunSplit(runId: _runId, time: _session.clock()),
      children: [for (final child in children) child.started],
    );
    if (!split) return;
    await Future.wait([
      for (final child in children)
        _session.guard(
          RunDriver(_session, child.runId).drive(
            child.first,
            node: _session.graph[child.started.node]!,
            carried: carriedAtStart(child.first, fromParent: carried),
          ),
        ),
    ]);
  }

  /// Creates a run at [node], whose parent is this run, into which this run
  /// carries [carried].
  Future<SplitChild> _createChild(String node, String? carried) async {
    final (run, first) = await _store.createRun(
      parentId: _runId,
      node: node,
      inputId: inputIdOf(_session.graph[node]!, carried),
    );
    final started = (await _store.events(run.id)).first as RunStarted;
    return (runId: run.id, first: first, started: started);
  }
}

/// What the call of a step of [node] that ended with [end] comes to: the
/// one line for `run-failed` when it failed, or else, when its stdout is
/// data, the JSON value it printed.
///
/// A code other than 0 is a failure, and so is stdout that is data but
/// empty or not one JSON document. A worker without `out` that exits with 0
/// gives neither.
({String? error, ({Object? value})? printed}) _judge(Node node, CallEnd end) {
  if (end.exitCode != 0) return (error: _exited(end.exitCode), printed: null);
  if (!printsData(node)) return (error: null, printed: null);
  const invalid = (error: 'printed invalid JSON', printed: null);
  final String text;
  try {
    text = utf8.decode(end.stdout);
  } on FormatException {
    return invalid;
  }
  if (text.trim().isEmpty) return (error: 'printed no output', printed: null);
  try {
    return (error: null, printed: (value: jsonDecode(text)));
  } on FormatException {
    return invalid;
  }
}

/// How a step of [node] turned out, as its `step-finished` [finish] tells
/// once the call has gone: [outcome] is the value of the step's output
/// document.
///
/// The call's stdout is kept only as that document, once it was data; so a
/// step that printed no output and one that printed something other than one
/// JSON document cannot be told apart, and the error names both.
StepResult finishedAs(Node node, StepFinished finish, {Object? outcome}) {
  final StepFinished(:exitCode, :outputId) = finish;
  final error = exitCode != 0
      ? _exited(exitCode)
      : printsData(node) && outputId == null
      ? 'printed no output or invalid JSON'
      : null;
  return (error: error, outputId: outputId, outcome: outcome);
}

String _exited(int exitCode) => 'exited with code $exitCode';

/// Where the run goes after a step of [node] that succeeded with [outcome]:
/// a worker goes to its `then`, or ends the run without one; a fork goes
/// where its outcome leads.
Route _route(Node node, Object? outcome) => switch (node) {
  WorkerNode(exits: [final then]) => RouteTo(then),
  WorkerNode() => const RouteEnd(),
  ForkNode() => node.route(outcome),
};
