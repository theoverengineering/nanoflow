// Where the engine picks up each run of a session: in a session it has just
// created, every run is at its first step; in one it continues, the run's
// journal, which is authoritative, and its step directories tell.

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_store/nanoflow_store.dart';

import 'carried_data.dart';
import 'run_driver.dart';

/// Where the engine picks up a run of a session.
sealed class Resumption {
  const Resumption(this.runId);

  final String runId;
}

/// The run has ended: it finished, split, or [failed].
final class RunEnded extends Resumption {
  const RunEnded(super.runId, {required this.failed});

  final bool failed;
}

/// The run was made by a split that has not been written: its parent makes
/// the runs the split is missing, then drives them all.
final class RunInSplit extends Resumption {
  const RunInSplit(super.runId);
}

/// The run takes [step], a step of [node], into which it carries [carried]:
/// its first step, which has not started, or its last step, which did not
/// finish and runs again.
final class RunAtStep extends Resumption {
  const RunAtStep(
    super.runId, {
    required this.step,
    required this.node,
    required this.carried,
    required this.started,
  });

  final Step step;
  final Node node;
  final String? carried;

  /// The run's `run-started` when the run has not started a step: the engine
  /// reports it as it starts the run.
  final RunStarted? started;
}

/// The run goes on from [step], its last step, a step of [node] that
/// finished as [result]; after it the run carries [carried].
final class RunAfterStep extends Resumption {
  const RunAfterStep(
    super.runId, {
    required this.step,
    required this.node,
    required this.result,
    required this.carried,
    required this.nextStep,
    required this.children,
  });

  final Step step;
  final Node node;
  final StepResult result;
  final String? carried;

  /// The step made for the next node before the engine stopped, which no
  /// `step-started` names yet (D6).
  final Step? nextStep;

  /// The runs made for the split before the engine stopped, by the node they
  /// start at: the split has not been written.
  final Map<String, SplitChild> children;
}

/// Where the engine picks up each run of the session [store], which goes by
/// [graph]; in the order the runs were created.
///
/// A step whose `step.json` lacks the output its `step-finished` names gets
/// it (D5).
Future<List<Resumption>> resumptionsOf(SessionHandle store, Graph graph) async {
  final runs = {
    for (final run in await store.runs())
      run.id: await _RunOnDisk.load(store, run),
  };

  // The document a run carries after its finished steps; a run a split made
  // starts with what its parent carried at the split (D7).
  String? carriedBy(_RunOnDisk run) {
    final parent = runs[run.run.parentId];
    var carried = carriedAtStart(
      run.firstStep,
      fromParent: parent == null ? null : carriedBy(parent),
    );
    for (final step in run.state.steps) {
      final finish = run.finishes[step.stepId];
      if (finish == null) break;
      carried = carriedAfter(
        graph[step.node]!,
        carried: carried,
        outputId: finish.outputId,
      );
    }
    return carried;
  }

  Future<Resumption> resumptionOf(_RunOnDisk run) async {
    final id = run.run.id;
    final state = run.state;
    if (state.isEnded) {
      return RunEnded(id, failed: state.status == RunStatus.failed);
    }
    if (runs[run.run.parentId] case final parent? when !parent.state.isEnded) {
      return RunInSplit(id);
    }
    final last = state.currentStep;
    if (last == null) {
      return RunAtStep(
        id,
        step: run.firstStep,
        node: graph[run.started.node]!,
        carried: carriedBy(run),
        started: run.started,
      );
    }
    final step = run.steps[last.stepId]!;
    final node = graph[last.node]!;
    final finish = run.finishes[last.stepId];
    if (finish == null) {
      return RunAtStep(
        id,
        step: step,
        node: node,
        carried: carriedBy(run),
        started: null,
      );
    }
    final outputId = finish.outputId;
    // Only a fork's outcome decides where the run goes.
    final outcome = node is ForkNode && outputId != null
        ? await store.documentValue(outputId)
        : null;
    return RunAfterStep(
      id,
      step: step,
      node: node,
      result: finishedAs(node, finish, outcome: outcome),
      carried: carriedBy(run),
      nextStep: run.unstarted,
      children: {
        for (final child in runs.values)
          if (child.run.parentId == id)
            child.started.node: (
              runId: child.run.id,
              first: child.firstStep,
              started: child.started,
            ),
      },
    );
  }

  return [for (final run in runs.values) await resumptionOf(run)];
}

/// A run as its directory holds it.
final class _RunOnDisk {
  _RunOnDisk._({
    required this.run,
    required this.started,
    required this.state,
    required this.steps,
    required this.finishes,
    required this.unstarted,
  });

  /// Reads [run] from [store], and gives each of its steps the output its
  /// `step-finished` names when `step.json` lacks it (D5).
  static Future<_RunOnDisk> load(SessionHandle store, Run run) async {
    final events = await store.events(run.id);
    final state = replay(run.id, events);
    final finishes = {
      for (final event in events.whereType<StepFinished>()) event.stepId: event,
    };
    final startedSteps = {for (final step in state.steps) step.stepId};
    final steps = <String, Step>{};
    Step? unstarted;
    for (var step in await store.steps(run.id)) {
      final outputId = finishes[step.id]?.outputId;
      if (outputId != null && step.outputId == null) {
        step = await store.setStepOutput(step, outputId);
      }
      steps[step.id] = step;
      if (!startedSteps.contains(step.id)) unstarted = step;
    }
    return _RunOnDisk._(
      run: run,
      // A run is created with its `run-started`.
      started: events.first as RunStarted,
      state: state,
      steps: steps,
      finishes: finishes,
      unstarted: unstarted,
    );
  }

  final Run run;
  final RunStarted started;
  final RunState state;

  /// The run's steps by id.
  final Map<String, Step> steps;

  /// The `step-finished` of each finished step, by step id.
  final Map<String, StepFinished> finishes;

  /// The step no `step-started` names: the first step of a run that has not
  /// started one (D4), or the step made for the next node (D6).
  final Step? unstarted;

  /// The step the run started with, or starts with.
  Step get firstStep =>
      state.steps.isEmpty ? unstarted! : steps[state.steps.first.stepId]!;
}
