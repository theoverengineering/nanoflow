import 'dart:convert';

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

  /// Whether the engine is stopping: it writes no more events and starts no
  /// more steps.
  bool stopping = false;

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

/// Drives one run, a step at a time, until it finishes, fails or splits;
/// then drives the runs its split created, all at once.
final class RunDriver {
  RunDriver(this._session, this._runId);

  final DrivenSession _session;
  final String _runId;

  SessionHandle get _store => _session.store;

  /// Drives the run from [first], a step of [node] that has not started, into
  /// which the run carries the document [carried].
  ///
  /// Completes when the run and every run its split created have ended, or
  /// the engine is stopping.
  Future<void> drive(
    Step first, {
    required String node,
    required String? carried,
  }) async {
    var step = first;
    var stepNode = _session.graph[node]!;
    var data = carried;
    while (true) {
      if (!await _session.record(
        StepStarted(
          runId: _runId,
          time: _session.clock(),
          stepId: step.id,
          node: stepNode.name,
        ),
      )) {
        return;
      }
      final CallEnd? end;
      try {
        end = await _call(step, stepNode);
      } on GraphProgramStartException catch (e) {
        // The step never ran: no `step-finished`.
        return _fail(step, 'cannot start the graph program: ${e.reason}');
      }
      if (end == null) return;
      final (:error, :printed) = _judge(stepNode, end);
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
        node: stepNode.name,
      )) {
        return;
      }
      if (outputId != null) step = await _store.setStepOutput(step, outputId);
      if (error != null) return _fail(step, error);

      data = carriedAfter(stepNode, carried: data, outputId: outputId);
      switch (_route(stepNode, printed)) {
        case RouteMissing(:final outcome):
          return _fail(step, 'no target for outcome ${jsonEncode(outcome)}');
        case RouteEnd():
        case RouteTo(:final target) when target.isEmpty:
          await _session.record(
            RunFinished(runId: _runId, time: _session.clock()),
          );
          return;
        case RouteTo(:final target) when target.isList:
          return _split(target.names, data);
        case RouteTo(:final target):
          stepNode = _session.graph[target.names.single]!;
      }
      if (_session.stopping) return;
      step = await _store.createStep(
        runId: _runId,
        node: stepNode.name,
        inputId: inputIdOf(stepNode, data),
      );
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

  /// Creates a run for each of [nodes], whose parent is this run, writes
  /// `run-split`, and drives the new runs all at once. [carried] is the
  /// document this run carries into them.
  Future<void> _split(List<String> nodes, String? carried) async {
    final children = <({String runId, Step first, RunStarted started})>[];
    for (final name in nodes) {
      if (_session.stopping) return;
      final (run, first) = await _store.createRun(
        parentId: _runId,
        node: name,
        inputId: inputIdOf(_session.graph[name]!, carried),
      );
      final started = (await _store.events(run.id)).first as RunStarted;
      _session.progress.report(started);
      children.add((runId: run.id, first: first, started: started));
    }
    final split = await _session.record(
      RunSplit(runId: _runId, time: _session.clock()),
      children: [for (final child in children) child.started],
    );
    if (!split) return;
    await Future.wait([
      for (final child in children)
        RunDriver(_session, child.runId).drive(
          child.first,
          node: child.started.node,
          carried: carriedAtStart(child.first, fromParent: carried),
        ),
    ]);
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
  if (end.exitCode != 0) {
    return (error: 'exited with code ${end.exitCode}', printed: null);
  }
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

/// Where the run goes after a step of [node] that succeeded and [printed]
/// what it did: a worker goes to its `then`, or ends the run without one; a
/// fork goes where its outcome leads.
Route _route(Node node, ({Object? value})? printed) => switch (node) {
  WorkerNode(exits: [final then]) => RouteTo(then),
  WorkerNode() => const RouteEnd(),
  // A fork's stdout is always data.
  ForkNode() => node.route(printed!.value),
};
