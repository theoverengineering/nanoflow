/// The `Logs` panel: its title and the rows of the steps list
/// (docs/ui-spec.md «Logs»). Pure: the time is passed in.
library;

import 'dart:convert';

import 'package:nanoflow_model/nanoflow_model.dart';

import 'graph_marks.dart' show stepOutcome;
import 'outcomes.dart';
import 'runs.dart';
import 'session_feed.dart';
import 'sessions.dart' show sessionEnd, sessionStart;
import 'texts.dart';
import 'texts.dart' as texts show shortId;

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

/// The title of the `Logs` panel for the run [runId]. [steps] are the run's
/// [stepsOfRun], when already at hand.
LogsHeader logsHeader(
  SessionData session,
  String runId, {
  List<RunStep>? steps,
}) {
  steps ??= stepsOfRun(session, runId);
  return LogsHeader._(
    runId,
    steps.length,
    steps.where((step) => step.inherited).length,
    session.runs[runId]?.run.parentId,
  );
}

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
  final outcome = stepOutcome(run, step, outcomes);
  if (outcome == null) return null;
  return switch (node.route(outcome.value)) {
    RouteTo(:final exit) => '${exit.label} → ${_targetText(exit.target)}',
    RouteEnd() => '${jsonEncode(outcome.value)} → end',
    RouteMissing() => null,
  };
}

String _targetText(Target target) =>
    target.isEmpty ? 'end' : target.names.join(', ');
