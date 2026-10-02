/// What the details of the selected step show: which step it is, and
/// whether it has its input and output documents (docs/ui-spec.md «Logs»:
/// «Детали шага»). Pure.
library;

import 'package:nanoflow_model/nanoflow_model.dart';

import 'runs.dart';
import 'session_feed.dart';

/// Whether a step has one of its documents (ui-spec «Logs»: «Данных нет»).
enum DocumentState {
  /// The node declares no `in` (no `out`): the tab is marked `—`.
  undeclared,

  /// Not there yet: the step is running, or its `step.json` is not read.
  notYet,

  /// The step has none: it failed, or nothing was carried to it.
  missing,

  /// The document [StepDocument.documentId] holds it.
  present,
}

/// A step's input or output.
final class StepDocument {
  const StepDocument._(this.state, {this.documentId, this.message});

  final DocumentState state;

  /// The document; `null` unless [state] is [DocumentState.present].
  final String? documentId;

  /// What the tab says instead of a document.
  final String? message;

  /// Whether the tab is marked `—`: the node declares no such data.
  bool get marked => state == DocumentState.undeclared;
}

/// The selected step as its details show it.
final class StepDetails {
  const StepDetails._({
    required this.sessionId,
    required this.runId,
    required this.stepId,
    required this.node,
    required this.status,
    required this.input,
    required this.output,
  });

  final String sessionId;

  /// The run the step belongs to: an ancestor's for an inherited step.
  final String runId;

  final String stepId;

  /// The node's name.
  final String node;

  final StepStatus status;

  bool get running => status == StepStatus.running;

  final StepDocument input;
  final StepDocument output;
}

/// The step [stepId] among the steps the run [runId] of [session] shows,
/// inherited ones too; `null` when it shows no such step. [steps] are the
/// run's [stepsOfRun], when already at hand.
StepDetails? stepDetails(
  SessionData session,
  String runId,
  String stepId, {
  List<RunStep>? steps,
}) {
  final step = (steps ?? stepsOfRun(session, runId))
      .where((step) => step.stepId == stepId)
      .firstOrNull;
  if (step == null) return null;
  final run = step.run;
  final state = step.state;
  final node = session.graph?.nodes[step.node];
  final given = run.steps[stepId];
  return StepDetails._(
    sessionId: session.id,
    runId: run.id,
    stepId: stepId,
    node: step.node,
    status: state.status,
    input: _input(node, given),
    output: _output(node, state, run.finishOf(stepId)?.outputId),
  );
}

StepDocument _input(Node? node, Step? given) {
  if (node != null && node.input == null) {
    return const StepDocument._(
      DocumentState.undeclared,
      message: 'This node declares no input',
    );
  }
  if (given == null) {
    return const StepDocument._(DocumentState.notYet, message: 'Not read yet');
  }
  final id = given.inputId;
  return id == null
      ? const StepDocument._(
          DocumentState.missing,
          message: 'The step had no input',
        )
      : StepDocument._(DocumentState.present, documentId: id);
}

/// A fork's output is its outcome; `step-finished` names it before
/// `step.json` does.
StepDocument _output(Node? node, StepState state, String? outputId) {
  if (node is WorkerNode && node.output == null) {
    return const StepDocument._(
      DocumentState.undeclared,
      message: 'This node declares no output',
    );
  }
  if (outputId != null) {
    return StepDocument._(DocumentState.present, documentId: outputId);
  }
  return switch (state.status) {
    StepStatus.running => const StepDocument._(
      DocumentState.notYet,
      message: 'Not yet: the step is still running',
    ),
    StepStatus.failed => const StepDocument._(
      DocumentState.missing,
      message: 'No output: the step failed',
    ),
    StepStatus.finished => const StepDocument._(
      DocumentState.missing,
      message: 'The step gave no output',
    ),
  };
}
