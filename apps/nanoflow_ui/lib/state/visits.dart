// migrated in Task 12: still on the old model (runs, the README graph,
// GraphSource); it does not compile until then.
/// The visits to a node in a session, and what the step details window
/// tells of one: where its input came from and when it was started
/// (docs/ui-spec.md «Окно деталей шага»). Pure.
library;

import 'package:nanoflow_model/nanoflow_model.dart';

import 'runs.dart';
import 'session_feed.dart';
import 'texts.dart';

/// A visit to a node: one step on it, in the run it belongs to.
final class Visit {
  Visit(this.run, this.state);

  /// The step's own run: an ancestor of the runs that inherit the step.
  final RunData run;

  final StepState state;

  String get stepId => state.stepId;

  String get runId => run.id;

  String get node => state.node;
}

/// The visits to [node] in [session]: its steps in every run, in the order
/// of their first `step-started`; started at the same time, in the order the
/// runs were made.
List<Visit> visitsTo(SessionData session, String node) {
  final found = [
    for (final (r, run) in runsInOrder(session).indexed)
      for (final (s, step) in run.state.steps.indexed)
        if (step.node == node) (visit: Visit(run, step), run: r, step: s),
  ];
  found.sort((a, b) {
    final byTime = a.visit.state.startedAt.compareTo(b.visit.state.startedAt);
    if (byTime != 0) return byTime;
    final byRun = a.run.compareTo(b.run);
    return byRun != 0 ? byRun : a.step.compareTo(b.step);
  });
  return [for (final f in found) f.visit];
}

/// The visit of the step [stepId] of [session]; `null` when it has not
/// started.
Visit? visitOf(SessionData session, String stepId) {
  for (final run in session.runs.values) {
    for (final step in run.state.steps) {
      if (step.stepId == stepId) return Visit(run, step);
    }
  }
  return null;
}

/// The visit a double click on [node] opens: the node's last step among the
/// steps of the selected run [runId], inherited ones too; else the node's
/// latest visit in [session]; `null` when it has none.
Visit? visitToOpen(SessionData session, String? runId, String node) {
  if (runId != null) {
    final step = stepsOfRun(
      session,
      runId,
    ).where((step) => step.node == node).lastOrNull;
    if (step != null) return Visit(step.run, step.state);
  }
  return visitsTo(session, node).lastOrNull;
}

/// Where a step's input came from.
sealed class InputSource {
  const InputSource();
}

/// The output of an earlier step: `from fix · 14:08:54`.
final class FromStep extends InputSource {
  const FromStep(this.visit);

  final Visit visit;

  /// When that step was first started.
  String get time => clockTime(visit.state.startedAt);
}

/// The input of the launch: the first step of the root run got it.
final class LaunchInput extends InputSource {
  const LaunchInput();
}

/// Where the input of [visit] came from (D7): the step before it, among the
/// steps of its run and of the runs it split from, whose output is the
/// input — a fork passes what it got on unchanged; else the launch, when it
/// is the input of the root run's first step. `null` when the step has no
/// input, or it is not known yet.
InputSource? inputSource(SessionData session, Visit visit) {
  final inputId = visit.run.steps[visit.stepId]?.inputId;
  if (inputId == null) return null;
  final steps = stepsOfRun(session, visit.runId);
  final at = steps.indexWhere((step) => step.stepId == visit.stepId);
  for (var i = at - 1; i >= 0; i--) {
    final step = steps[i];
    final output =
        step.run.finishOf(step.stepId)?.outputId ??
        step.run.steps[step.stepId]?.outputId;
    if (output == inputId) return FromStep(Visit(step.run, step.state));
  }
  final root = lineage(session, visit.runId).firstOrNull;
  final first = root?.state.steps.firstOrNull;
  if (first != null && root!.steps[first.stepId]?.inputId == inputId) {
    return const LaunchInput();
  }
  return null;
}

/// A start of a step's command, and whether the engine stopped it: another
/// start of the same step came after it.
typedef StepStart = ({DateTime at, bool interrupted});

/// Every start of the step [stepId] of [run], in the order of its journal.
List<StepStart> startsOf(RunData run, String stepId) {
  final times = [
    for (final event in run.events)
      if (event case StepStarted(stepId: final id, :final time)
          when id == stepId)
        time,
  ];
  return [
    for (final (i, time) in times.indexed)
      (at: time, interrupted: i < times.length - 1),
  ];
}
