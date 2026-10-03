/// What the details of a step show: which step it is, where in the code it
/// was called, its output document and, for a step that failed, its error
/// with the stack (docs/ui-spec.md «Logs»: «Детали шага»; spec §9 «Окно
/// шага»). A step has no input: it takes its data from its closure. Pure.
library;

import 'package:nanoflow_model/nanoflow_model.dart';

import 'session_feed.dart';
import 'visits.dart' show StartOutcome, outcomeOf;

/// Whether a step has its output.
enum DocumentState {
  /// Not there yet: the step is running, or was interrupted.
  notYet,

  /// The step has none: it failed, or finished without naming one.
  missing,

  /// The document [StepDocument.documentId] holds it.
  present,
}

/// A step's output.
final class StepDocument {
  const StepDocument._(this.state, {this.documentId, this.message});

  final DocumentState state;

  /// The document; `null` unless [state] is [DocumentState.present].
  final String? documentId;

  /// What the tab says instead of a document.
  final String? message;
}

/// A step as its details show it.
final class StepDetails {
  const StepDetails._({
    required this.sessionId,
    required this.stepId,
    required this.name,
    required this.place,
    required this.status,
    required this.output,
    required this.error,
    required this.stack,
  });

  final String sessionId;

  final String stepId;

  /// The name given to `f.step`.
  final String name;

  /// Where `f.step` was called: `lib/review.dart:49`; `null` when not
  /// known.
  final String? place;

  /// How its last start stands: interrupted when the process of its
  /// session went while it ran.
  final StartOutcome status;

  bool get running => status == StartOutcome.running;

  final StepDocument output;

  /// The error of the step's last `step-failed`, while it is failed.
  final String? error;

  /// The stack of that `step-failed`.
  final String? stack;
}

/// The step [stepId] of [session]; `null` until it has started and its
/// record has been read.
StepDetails? stepDetails(SessionData session, String stepId) {
  final record = session.steps[stepId];
  final state = session.state.steps
      .where((step) => step.stepId == stepId)
      .firstOrNull;
  if (record == null || state == null) return null;
  final failure = state.status == StepStatus.failed
      ? session.events.whereType<StepFailed>().lastWhere(
          (event) => event.stepId == stepId,
        )
      : null;
  final status = outcomeOf(session, state);
  return StepDetails._(
    sessionId: session.id,
    stepId: stepId,
    name: record.name,
    place: record.place,
    status: status,
    output: _output(status, state.outputId),
    error: failure?.error,
    stack: failure?.stack,
  );
}

/// `step-finished` names the output, [outputId], before `step.json` does.
StepDocument _output(StartOutcome status, String? outputId) => switch (status) {
  StartOutcome.running => const StepDocument._(
    DocumentState.notYet,
    message: 'Not yet: the step is still running',
  ),
  StartOutcome.interrupted => const StepDocument._(
    DocumentState.notYet,
    message: 'Not yet: the step was interrupted — the process stopped',
  ),
  StartOutcome.failed => const StepDocument._(
    DocumentState.missing,
    message: 'No output: the step failed',
  ),
  StartOutcome.finished => switch (outputId) {
    final id? => StepDocument._(DocumentState.present, documentId: id),
    null => const StepDocument._(
      DocumentState.missing,
      message: 'The step gave no output',
    ),
  },
};
