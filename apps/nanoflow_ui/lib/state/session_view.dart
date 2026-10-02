/// What the graph screen shows of a session, derived from what the feed has
/// given (docs/ui-spec.md «Сессии», «Холст», «Граф», «Logs»).
///
/// Pure: no I/O, the time is passed in. Widgets draw what is here and decide
/// nothing about it.
library;

import 'dart:convert';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:path/path.dart' as p;

import '../layout/layout_graph.dart' show counterText;
import 'outcomes.dart';
import 'session_feed.dart';
import 'texts.dart';
import 'texts.dart' as texts show shortId;

/// The mark of a run whose journal could not be read in full: lines that are
/// not events, events this version does not know, files it could not read.
const logRunIncompletely = 'Log read incompletely';

// Sessions.

/// Where a session is (ui-spec «Сессии»).
enum SessionStatus {
  /// At least one run has not ended.
  running,

  /// Every run has ended, at least one with `run-failed`.
  failed,

  /// Every run has ended, none failed.
  finished,
}

/// A session's card in the sessions column and its strip over the canvas.
final class SessionSummary {
  SessionSummary._({
    required this.id,
    required this.startedAt,
    required this.status,
    required this.duration,
    required this.runs,
    required this.failedRuns,
    required this.firstLine,
  });

  final String id;

  String get shortId => texts.shortId(id);

  /// The first `run-started` of the session's runs, in UTC.
  final DateTime startedAt;

  final SessionStatus status;

  /// From [startedAt] to the end of the last run; for a running session, to
  /// now.
  final Duration duration;

  /// How many runs the session has.
  final int runs;

  /// How many of them failed.
  final int failedRuns;

  /// The day and time the session started: `Today · 14:03:11`.
  final String firstLine;

  /// `Running for 12m 26s`, `Failed in 6m 18s`, `Finished in 3m 04s`.
  String get statusText => switch (status) {
    SessionStatus.running => 'Running for ${formatDuration(duration)}',
    SessionStatus.failed => 'Failed in ${formatDuration(duration)}',
    SessionStatus.finished => 'Finished in ${formatDuration(duration)}',
  };

  /// `1 failed` next to the status of a running session with failed runs.
  String? get failedBadge => status == SessionStatus.running && failedRuns > 0
      ? '$failedRuns failed'
      : null;

  /// `1 run`, `3 runs`.
  String get runsText => count(runs, 'run');

  /// `started 14:03:11`, on the strip over the canvas.
  String get startedText => 'started ${clockTime(startedAt)}';

  /// `running 12m 26s`, `failed in 6m 18s`, `finished in 3m 04s`, on the
  /// strip over the canvas, to the second.
  String get stripStatus => switch (status) {
    SessionStatus.running => 'running ${formatElapsed(duration)}',
    SessionStatus.failed => 'failed in ${formatElapsed(duration)}',
    SessionStatus.finished => 'finished in ${formatElapsed(duration)}',
  };
}

/// The summary of [session] at [now]; `null` while none of its runs has a
/// `run-started`: a session has no start time before that.
SessionSummary? summarize(SessionData session, DateTime now) {
  final start = sessionStart(session);
  if (start == null) return null;
  final runs = session.runs.values;
  final ended = runs.every((run) => run.state.isEnded);
  final failed = runs.where((run) => run.state.status == RunStatus.failed);
  return SessionSummary._(
    id: session.id,
    startedAt: start,
    status: !ended
        ? SessionStatus.running
        : failed.isNotEmpty
        ? SessionStatus.failed
        : SessionStatus.finished,
    duration: (sessionEnd(session) ?? now).difference(start),
    runs: runs.length,
    failedRuns: failed.length,
    firstLine: dayAndTime(start, now),
  );
}

/// The first `run-started` of [session]'s runs; `null` before there is one.
DateTime? sessionStart(SessionData session) {
  DateTime? start;
  for (final run in session.runs.values) {
    final time = run.started?.time;
    if (time != null && (start == null || time.isBefore(start))) start = time;
  }
  return start;
}

/// When the last run of [session] ended; `null` while a run goes on.
DateTime? sessionEnd(SessionData session) {
  DateTime? end;
  for (final run in session.runs.values) {
    final time = run.state.finishedAt;
    if (time == null) return null;
    if (end == null || time.isAfter(end)) end = time;
  }
  return end;
}

/// What the sessions column says instead of sessions when the graph has
/// none.
const noRunsYet = 'No runs yet';

/// How to start a session of the YAML graph [graphFile]: sessions are read
/// from the `runs` directory next to it, where `nanoflow run` started from
/// its directory puts them.
String noRunsHint(String graphFile) =>
    "Start a session from the graph's directory: "
    'nanoflow run -- nanoflow-yaml ${p.basename(graphFile)}';

/// The summaries of [sessions] that have started, newest first.
List<SessionSummary> sessionSummaries(
  Iterable<SessionData> sessions,
  DateTime now,
) => [
  for (final session in sessionsNewestFirst(sessions)) summarize(session, now)!,
];

/// Those of [sessions] that have started, newest first (ui-spec «Сессии»).
List<SessionData> sessionsNewestFirst(Iterable<SessionData> sessions) {
  final started = [
    for (final session in sessions)
      if (sessionStart(session) case final start?) (session, start),
  ];
  started.sort((a, b) {
    final byTime = b.$2.compareTo(a.$2);
    return byTime != 0 ? byTime : a.$1.id.compareTo(b.$1.id);
  });
  return [for (final (session, _) in started) session];
}

// Runs.

/// Where a run is, as the run switcher shows it (ui-spec «Холст»).
enum RunPhase {
  /// No `step-started` yet.
  notStarted,
  running,
  finished,
  failed,
  split,
}

RunPhase phaseOf(RunData run) => switch (run.state.status) {
  RunStatus.pending => RunPhase.notStarted,
  RunStatus.running => RunPhase.running,
  RunStatus.finished => RunPhase.finished,
  RunStatus.failed => RunPhase.failed,
  RunStatus.split => RunPhase.split,
};

/// The runs of [session] in the order they were created: by `run-started`,
/// then by id; runs without `run-started` yet come last.
List<RunData> runsInOrder(SessionData session) {
  final runs = [...session.runs.values];
  runs.sort((a, b) {
    final at = a.started?.time;
    final bt = b.started?.time;
    if (at != null && bt != null && at != bt) return at.compareTo(bt);
    if ((at == null) != (bt == null)) return at == null ? 1 : -1;
    return a.id.compareTo(b.id);
  });
  return runs;
}

/// A run in the run switcher.
final class RunChip {
  RunChip(RunData run)
    : runId = run.id,
      phase = phaseOf(run),
      incomplete = run.incomplete;

  final String runId;

  String get shortId => texts.shortId(runId);

  final RunPhase phase;

  /// Whether the run is marked [logRunIncompletely].
  final bool incomplete;

  /// The word next to the run's id: `split` for a run that split.
  String? get word => phase == RunPhase.split ? 'split' : null;
}

/// The run switcher of [session].
List<RunChip> runChips(SessionData session) => [
  for (final run in runsInOrder(session)) RunChip(run),
];

/// The run [runId] and its ancestors, from the root run down to it; empty
/// when [session] has no such run.
List<RunData> lineage(SessionData session, String runId) {
  final chain = <RunData>[];
  final seen = <String>{};
  String? id = runId;
  while (id != null && seen.add(id)) {
    final run = session.runs[id];
    if (run == null) break;
    chain.add(run);
    id = run.run.parentId;
  }
  return chain.reversed.toList();
}

/// A step of a run as the run shows it: its own, or one of an ancestor's.
final class RunStep {
  RunStep(this.run, this.state, {required this.inherited});

  /// The run the step belongs to.
  final RunData run;

  final StepState state;

  /// Whether the step is an ancestor's.
  final bool inherited;

  String get stepId => state.stepId;

  String get node => state.node;
}

/// The steps of the run [runId]: its ancestors' from the root run down to the
/// split that made it, then its own (ui-spec «Холст»).
List<RunStep> stepsOfRun(SessionData session, String runId) => [
  for (final run in lineage(session, runId))
    for (final step in run.state.steps)
      RunStep(run, step, inherited: run.id != runId),
];

// The graph.

/// A node's state over all runs of a session; a later value wins over an
/// earlier one (ui-spec «Граф»).
enum NodeState {
  /// No steps.
  notVisited,

  /// Finished steps.
  visited,

  /// A step without `step-finished`.
  running,

  /// A run failed on a step of the node.
  failed,
}

/// An exit of a node: its index in the node's exits.
typedef ExitKey = ({String node, int exit});

/// An arrow: from an exit of a node to a node of its target.
typedef ArrowKey = ({String from, int exit, String to});

/// A run's id over the tile of the node it is on.
final class RunMarker {
  RunMarker(this.runId, this.phase);

  final String runId;

  String get shortId => texts.shortId(runId);

  /// The marker is drawn in the color of the run's state.
  final RunPhase phase;
}

/// What a session puts on its graph: node states, run markers, visit and
/// arrow counters.
final class GraphMarks {
  GraphMarks._(this._states, this._visits, this.passes, this._markers);

  /// The marks of every run of [session]. A fork step counts once its
  /// outcome is known through [outcomes].
  factory GraphMarks.of(SessionData session, OutcomeOf outcomes) {
    final graph = session.graph;
    final states = <String, NodeState>{};
    final visits = <String, int>{};
    final passes = <ExitKey, int>{};
    final markers = <String, List<RunMarker>>{};
    for (final run in runsInOrder(session)) {
      for (final step in run.state.steps) {
        visits.update(step.node, (n) => n + 1, ifAbsent: () => 1);
        final state = switch (step.status) {
          StepStatus.failed => NodeState.failed,
          StepStatus.running => NodeState.running,
          StepStatus.finished => NodeState.visited,
        };
        final known = states[step.node];
        if (known == null || state.index > known.index) {
          states[step.node] = state;
        }
        final exit = _exitTaken(graph, run, step, outcomes);
        if (exit != null) passes.update(exit, (n) => n + 1, ifAbsent: () => 1);
      }
      final phase = phaseOf(run);
      final node = run.state.steps.lastOrNull?.node ?? run.started?.node;
      if (phase != RunPhase.split && node != null) {
        (markers[node] ??= []).add(RunMarker(run.id, phase));
      }
    }
    return GraphMarks._(states, visits, passes, markers);
  }

  final Map<String, NodeState> _states;
  final Map<String, int> _visits;
  final Map<String, List<RunMarker>> _markers;

  /// How many times runs went through each exit; exits never gone through
  /// are not here.
  final Map<ExitKey, int> passes;

  NodeState stateOf(String node) => _states[node] ?? NodeState.notVisited;

  /// How many steps the node has had.
  int visitsOf(String node) => _visits[node] ?? 0;

  /// `2×` over a node entered more than once; `null` otherwise.
  String? visitText(String node) {
    final visits = visitsOf(node);
    return visits > 1 ? counterText(visits) : null;
  }

  int passesOf(String node, int exit) => passes[(node: node, exit: exit)] ?? 0;

  /// Whether a run went through the exit: arrows no run took are darker.
  bool isTaken(String node, int exit) => passesOf(node, exit) > 0;

  /// `1×` on the arrows of an exit runs went through; `null` otherwise.
  String? counterOf(String node, int exit) {
    final passes = passesOf(node, exit);
    return passes > 0 ? counterText(passes) : null;
  }

  /// The runs on [node], in the order they were created: every run but those
  /// that split, on the node of its last step; a run not started, on its
  /// start node.
  List<RunMarker> markersOn(String node) => _markers[node] ?? const [];
}

/// The exit [step] of [run] went through: a worker's `then`, the exit a
/// fork's outcome chose. `null` when it went through none (yet): it runs,
/// its run failed on it, its exit code is not 0, its outcome is not known, or
/// its node has no exit for it.
ExitKey? _exitTaken(
  Graph? graph,
  RunData run,
  StepState step,
  OutcomeOf outcomes,
) {
  if (step.status != StepStatus.finished || step.exitCode != 0) return null;
  switch (graph?.nodes[step.node]) {
    case WorkerNode(:final then):
      return then == null ? null : (node: step.node, exit: 0);
    case final ForkNode fork:
      final outcome = _outcome(run, step, outcomes);
      if (outcome == null) return null;
      return switch (fork.route(outcome.value)) {
        RouteTo(:final exit) => (
          node: step.node,
          exit: fork.exits.indexOf(exit),
        ),
        RouteEnd() || RouteMissing() => null,
      };
    case null:
      return null;
  }
}

Outcome? _outcome(RunData run, StepState step, OutcomeOf outcomes) {
  final outputId = run.finishOf(step.stepId)?.outputId;
  return outputId == null ? null : outcomes(outputId);
}

/// The output documents of [session]'s fork steps that have finished: their
/// outcomes say where the runs went.
Set<String> forkOutputs(SessionData session) {
  final graph = session.graph;
  if (graph == null) return const {};
  return {
    for (final run in session.runs.values)
      for (final step in run.state.steps)
        if (graph.nodes[step.node] is ForkNode &&
            step.status == StepStatus.finished)
          ?run.finishOf(step.stepId)?.outputId,
  };
}

/// The way a run went: drawn in the accent color.
final class RunPath {
  RunPath._(this.exits, this.arrows, this.inputs);

  /// The exits its steps went through.
  final Set<ExitKey> exits;

  /// The arrows from those exits into the nodes of the steps after them.
  final Set<ArrowKey> arrows;

  /// The nodes entered by an arrow: their input bars.
  final Set<String> inputs;
}

/// The path of the run [runId]: the exits its steps, inherited ones too, went
/// through, the arrows on to the next step, and the nodes they entered.
RunPath pathOf(SessionData session, String runId, OutcomeOf outcomes) =>
    _path(session, runId, stepsOfRun(session, runId), outcomes);

RunPath _path(
  SessionData session,
  String runId,
  List<RunStep> steps,
  OutcomeOf outcomes,
) {
  final graph = session.graph;
  final nodes = [for (final step in steps) step.node];
  final run = session.runs[runId];
  // A run not started yet has been sent to its start node.
  final start = run?.started?.node;
  if (run != null && run.state.steps.isEmpty && start != null) {
    if (run.run.parentId != null) nodes.add(start);
  }
  final exits = <ExitKey>{};
  final arrows = <ArrowKey>{};
  for (var i = 0; i < steps.length; i++) {
    final exit = _exitTaken(graph, steps[i].run, steps[i].state, outcomes);
    if (exit == null) continue;
    exits.add(exit);
    if (i + 1 >= nodes.length) continue;
    final target = graph!.nodes[exit.node]!.exits[exit.exit].target;
    if (target.names.contains(nodes[i + 1])) {
      arrows.add((from: exit.node, exit: exit.exit, to: nodes[i + 1]));
    }
  }
  return RunPath._(exits, arrows, {...nodes.skip(1)});
}

// Logs.

/// The title of the `Logs` panel: `run e5f6 · 8 steps, 7 inherited from
/// k7f2`.
final class LogsHeader {
  LogsHeader._(this.runId, this.steps, this.inherited, this.parentId);

  final String runId;

  String get shortId => texts.shortId(runId);

  /// How many steps the run shows, inherited ones too.
  final int steps;

  /// How many of them are its ancestors'.
  final int inherited;

  /// The run the selected one split from; `null` for a root run.
  final String? parentId;

  /// `8 steps, 7 inherited from k7f2`; `7 steps` for a root run.
  String get stepsText {
    final all = count(steps, 'step');
    final parent = parentId;
    return inherited == 0 || parent == null
        ? all
        : '$all, $inherited inherited from ${texts.shortId(parent)}';
  }

  String get text => 'run $shortId · $stepsText';
}

/// The title of the `Logs` panel for the run [runId].
LogsHeader logsHeader(SessionData session, String runId) =>
    _header(session, runId, stepsOfRun(session, runId));

LogsHeader _header(SessionData session, String runId, List<RunStep> steps) =>
    LogsHeader._(
      runId,
      steps.length,
      steps.where((step) => step.inherited).length,
      session.runs[runId]?.run.parentId,
    );

/// A row of the steps list.
sealed class LogRow {}

/// A step.
final class StepRow extends LogRow {
  StepRow._({
    required this.stepId,
    required this.runId,
    required this.name,
    required this.status,
    required this.inherited,
    required this.detail,
    required this.failure,
    required this.started,
    required this.duration,
    required this.starts,
    required this.barStart,
    required this.barEnd,
  });

  final String stepId;

  /// The run the step belongs to.
  final String runId;

  /// The node's name.
  final String name;

  /// The icon: finished, running, failed.
  final StepStatus status;

  /// An ancestor's step: dimmed.
  final bool inherited;

  /// After the name: for a fork, its outcome and where it went
  /// (`returned → fix`); for a failed step, the error of `run-failed`.
  final String? detail;

  /// Whether [detail] is an error.
  final bool failure;

  /// The time of the first `step-started`: `14:03:11`.
  final String started;

  /// To `step-finished`, or to now while the step runs.
  final Duration duration;

  /// [duration] as shown: `2m 29s`.
  String get took => formatDuration(duration);

  /// How many times the step's command was started.
  final int starts;

  /// `2 starts` for a step started more than once.
  String? get startsText => starts > 1 ? '$starts starts' : null;

  /// Where the step's bar begins and ends on the session's time scale, from
  /// 0 to 1.
  final double barStart;
  final double barEnd;

  /// A running step's bar is striped.
  bool get striped => status == StepStatus.running;
}

/// Where a run split from its parent: `split · run e5f6`.
final class SplitRow extends LogRow {
  SplitRow._(this.runId);

  /// The run the split made, whose steps follow.
  final String runId;

  String get text => 'split · run ${texts.shortId(runId)}';
}

/// The last row of a run that has ended.
final class EndRow extends LogRow {
  EndRow._(this.phase, this.error, this.children, this.at);

  /// [RunPhase.finished], [RunPhase.failed] or [RunPhase.split].
  final RunPhase phase;

  /// The error of `run-failed`.
  final String? error;

  /// The runs a split made, in the order they were created: links.
  final List<String> children;

  /// When the run ended.
  final DateTime at;

  /// `Run finished`, `Run failed: exited with code 1`, `Run split into`
  /// followed by the [children].
  String get text => switch (phase) {
    RunPhase.failed => 'Run failed: $error',
    RunPhase.split => 'Run split into',
    _ => 'Run finished',
  };
}

/// The common time scale of a session's step bars: from its start to its
/// end, or to now while it runs.
final class TimeScale {
  TimeScale(this.start, this.end);

  final DateTime start;
  final DateTime end;

  /// Where [t] is on the scale, from 0 at [start] to 1 at [end].
  double fraction(DateTime t) {
    final span = end.difference(start).inMicroseconds;
    if (span <= 0) return 0;
    return (t.difference(start).inMicroseconds / span).clamp(0.0, 1.0);
  }
}

/// The time scale of [session] at [now].
TimeScale timeScale(SessionData session, DateTime now) =>
    TimeScale(sessionStart(session) ?? now, sessionEnd(session) ?? now);

/// The steps list of the run [runId]: its steps in order, inherited ones
/// too, a [SplitRow] where each split begins, and an [EndRow] once the run
/// has ended.
List<LogRow> logRows(
  SessionData session,
  String runId, {
  required OutcomeOf outcomes,
  required DateTime now,
}) {
  final scale = timeScale(session, now);
  final chain = lineage(session, runId);
  final rows = <LogRow>[];
  for (final (i, run) in chain.indexed) {
    if (i > 0) rows.add(SplitRow._(run.id));
    for (final step in run.state.steps) {
      rows.add(
        _stepRow(
          session.graph,
          run,
          step,
          run.id != runId,
          outcomes,
          now,
          scale,
        ),
      );
    }
  }
  final run = chain.lastOrNull;
  final ended = run?.state.finishedAt;
  if (run != null && ended != null) {
    rows.add(
      EndRow._(phaseOf(run), run.state.error, [
        for (final child in runsInOrder(session))
          if (child.run.parentId == run.id) child.id,
      ], ended),
    );
  }
  return rows;
}

StepRow _stepRow(
  Graph? graph,
  RunData run,
  StepState step,
  bool inherited,
  OutcomeOf outcomes,
  DateTime now,
  TimeScale scale,
) {
  final failed = step.status == StepStatus.failed;
  // A step that could not start fails without `step-finished` (D16).
  final end = step.finishedAt ?? (failed ? run.state.finishedAt : null) ?? now;
  return StepRow._(
    stepId: step.stepId,
    runId: run.id,
    name: step.node,
    status: step.status,
    inherited: inherited,
    detail: failed
        ? run.state.error
        : _routeText(graph?.nodes[step.node], run, step, outcomes),
    failure: failed,
    started: clockTime(step.startedAt),
    duration: end.difference(step.startedAt),
    starts: step.starts,
    barStart: scale.fraction(step.startedAt),
    barEnd: scale.fraction(end),
  );
}

/// A fork step's outcome and where it sent the run: `returned → fix`,
/// `accepted → publish, notify`, `else → inspect`; `end` where it sent the
/// run nowhere. `null` for a worker, and while the outcome is not known.
String? _routeText(
  Node? node,
  RunData run,
  StepState step,
  OutcomeOf outcomes,
) {
  if (node is! ForkNode || step.status != StepStatus.finished) return null;
  final outcome = _outcome(run, step, outcomes);
  if (outcome == null) return null;
  return switch (node.route(outcome.value)) {
    RouteTo(:final exit) => '${exit.label} → ${_targetText(exit.target)}',
    RouteEnd() => '${jsonEncode(outcome.value)} → end',
    RouteMissing() => null,
  };
}

String _targetText(Target target) =>
    target.isEmpty ? 'end' : target.names.join(', ');

// The whole of it.

/// The selected run as the canvas and the `Logs` panel show it.
final class RunView {
  RunView._(this.chip, this.header, this.steps, this.rows, this.path);

  final RunChip chip;

  final LogsHeader header;

  /// Its steps, inherited ones first.
  final List<RunStep> steps;

  final List<LogRow> rows;

  final RunPath path;
}

/// Everything the graph screen shows of a session at a moment.
final class SessionView {
  SessionView._({
    required this.summary,
    required this.graph,
    required this.runs,
    required this.marks,
    required this.run,
    required this.selectedNode,
  });

  /// [session] at [now], with the run [runId] and its step [stepId]
  /// selected.
  factory SessionView.of(
    SessionData session, {
    required DateTime now,
    required OutcomeOf outcomes,
    String? runId,
    String? stepId,
  }) {
    final run = runId == null ? null : session.runs[runId];
    RunView? runView;
    if (run != null) {
      final steps = stepsOfRun(session, run.id);
      runView = RunView._(
        RunChip(run),
        _header(session, run.id, steps),
        steps,
        logRows(session, run.id, outcomes: outcomes, now: now),
        _path(session, run.id, steps, outcomes),
      );
    }
    return SessionView._(
      summary: summarize(session, now),
      graph: session.graph,
      runs: runChips(session),
      marks: GraphMarks.of(session, outcomes),
      run: runView,
      selectedNode: runView?.steps
          .where((step) => step.stepId == stepId)
          .firstOrNull
          ?.node,
    );
  }

  /// `null` while no run of the session has started.
  final SessionSummary? summary;

  /// The graph the session holds; `null` when it is not a graph.
  final Graph? graph;

  /// The run switcher.
  final List<RunChip> runs;

  final GraphMarks marks;

  /// The selected run; `null` when none is.
  final RunView? run;

  /// The node of the selected step: ringed on the canvas.
  final String? selectedNode;
}
