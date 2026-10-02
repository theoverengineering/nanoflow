/// A session's runs as the canvas and the `Logs` panel show them: in the
/// order they were created, in their state, with the steps each one shows
/// (docs/ui-spec.md «Холст»). Pure.
library;

import 'package:nanoflow_model/nanoflow_model.dart';

import 'session_feed.dart';
import 'texts.dart' as texts show shortId;

/// The mark of a run whose journal could not be read in full: lines that are
/// not events, events this version does not know, files it could not read.
const logReadIncompletely = 'Log read incompletely';

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

  /// Whether the run is marked [logReadIncompletely].
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
