/// What the graph screen shows of a session, derived from what the feed has
/// given (docs/ui-spec.md «Сессии», «Холст», «Граф», «Logs»).
///
/// Pure: no I/O, the time is passed in. Widgets draw what is here and decide
/// nothing about it. The parts are in their own files, exported here.
library;

import 'package:nanoflow_model/nanoflow_model.dart';

import 'graph_marks.dart';
import 'log_rows.dart';
import 'outcomes.dart';
import 'runs.dart';
import 'session_feed.dart';
import 'sessions.dart';

export 'graph_marks.dart';
export 'log_rows.dart';
export 'runs.dart';
export 'sessions.dart';

/// The selected run as the canvas and the `Logs` panel show it.
final class RunView {
  RunView._(
    this.chip,
    this.header,
    List<RunStep> steps,
    List<LogRow> rows,
    this.path,
  ) : steps = List.unmodifiable(steps),
      rows = List.unmodifiable(rows);

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
        logsHeader(session, run.id, steps: steps),
        steps,
        logRows(session, run.id, outcomes: outcomes, now: now),
        pathOf(session, run.id, outcomes, steps: steps),
      );
    }
    return SessionView._(
      summary: summarize(session, now),
      graph: session.graph,
      runs: List.unmodifiable(runChips(session)),
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
