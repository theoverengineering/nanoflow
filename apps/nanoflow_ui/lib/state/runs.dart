/// A session's runs as the canvas and the `Logs` panel show them: in the
/// order they were created, in their state, with the steps each one shows
/// (docs/ui-spec.md «Холст»). Pure.
library;

import 'package:nanoflow_model/nanoflow_model.dart';

import 'outcomes.dart';
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

RunPhase phaseOf(RunData run) => _phase(run.state.status);

/// [run]'s phase as its events from before [t] tell.
RunPhase phaseAt(RunData run, DateTime t) {
  final events = run.events;
  if (events.every((event) => event.time.isBefore(t))) return phaseOf(run);
  return _phase(
    replay(run.id, events.where((event) => event.time.isBefore(t))).status,
  );
}

RunPhase _phase(RunStatus status) => switch (status) {
  RunStatus.pending => RunPhase.notStarted,
  RunStatus.running => RunPhase.running,
  RunStatus.finished => RunPhase.finished,
  RunStatus.failed => RunPhase.failed,
  RunStatus.split => RunPhase.split,
};

/// The run opening [session] at [at] selects (ui-spec «Выбор»): of the runs
/// started before [at], as they were then, the first running one, else the
/// first failed one, else the last; `null` when none had started.
///
/// What happens after [at] does not change it, and runs read later that had
/// started before it do: the choice stays put while the feed catches up.
RunData? openingRun(SessionData session, DateTime at) {
  final runs = [
    for (final run in runsInOrder(session))
      if (run.started?.time.isBefore(at) ?? false) run,
  ];
  RunData? first(RunPhase phase) =>
      runs.where((run) => phaseAt(run, at) == phase).firstOrNull;
  return first(RunPhase.running) ?? first(RunPhase.failed) ?? runs.lastOrNull;
}

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
  /// [problems] are why the run is read incompletely; by default, those of
  /// its journal.
  RunChip(RunData run, {Iterable<String>? problems})
    : runId = run.id,
      phase = phaseOf(run),
      problems = List.unmodifiable(problems ?? run.problems);

  final String runId;

  String get shortId => texts.shortId(runId);

  final RunPhase phase;

  /// Why the run is marked [logReadIncompletely]: what of its journal, its
  /// files and its fork outcomes could not be read.
  final List<String> problems;

  /// Whether the run is marked [logReadIncompletely].
  bool get incomplete => problems.isNotEmpty;

  /// The word next to the run's id: `split` for a run that split.
  String? get word => phase == RunPhase.split ? 'split' : null;
}

/// The run switcher of [session].
List<RunChip> runChips(SessionData session, KnownOutcomes outcomes) => [
  for (final run in runsInOrder(session))
    RunChip(run, problems: runProblems(session, run, outcomes)),
];

/// Why [run] of [session] is read incompletely: its journal's and its files'
/// problems, and fork outcomes that could not be read.
List<String> runProblems(
  SessionData session,
  RunData run,
  KnownOutcomes outcomes,
) => [
  ...run.problems,
  for (final document in forkOutputsOf(session.graph, run))
    if (outcomes.problemOf(document) case final problem?)
      'the outcome in document $document cannot be read: $problem',
];

/// The output documents of the fork steps of [run] that have finished: their
/// outcomes say where the run went. None without a [graph].
Iterable<String> forkOutputsOf(Graph? graph, RunData run) => [
  if (graph != null)
    for (final step in run.state.steps)
      if (graph.nodes[step.node] is ForkNode &&
          step.status == StepStatus.finished)
        ?run.finishOf(step.stepId)?.outputId,
];

/// The output documents of every fork step of [session] that has finished.
Set<String> forkOutputs(SessionData session) => {
  for (final run in session.runs.values) ...forkOutputsOf(session.graph, run),
};

/// The outcome of the fork [step] of [run]: the value of its output document,
/// once known.
Outcome? stepOutcome(RunData run, StepState step, KnownOutcomes outcomes) {
  final outputId = run.finishOf(step.stepId)?.outputId;
  return outputId == null ? null : outcomes[outputId];
}

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
