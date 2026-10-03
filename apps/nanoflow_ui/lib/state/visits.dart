/// The visits to a node in a session, and the starts of a step
/// (docs/ui-spec.md «Окно деталей шага»: `Visit 2 of 2`, `Starts`). A visit
/// is a step on the node, found by its place (D13). Pure.
library;

import 'package:nanoflow_model/nanoflow_model.dart';

import 'session_feed.dart';
import 'step_places.dart';

/// A visit to a node: one step on it.
final class Visit {
  Visit(this.record, this.state);

  final Step record;

  final StepState state;

  String get stepId => state.stepId;

  String get name => record.name;
}

/// Those of [steps] of [session] whose records [keep] keeps, as visits in
/// the order of [steps]; a step whose record is not read yet is left out.
List<Visit> _visits(
  SessionData session,
  Iterable<StepState> steps,
  bool Function(Step record) keep,
) => [
  for (final step in steps)
    if (session.steps[step.stepId] case final record? when keep(record))
      Visit(record, step),
];

/// The visits to the step node [node]: those of [steps] of [session] at its
/// place, as [places] finds them.
List<Visit> visitsTo(
  SessionData session,
  Iterable<StepState> steps,
  StepPlaces places,
  StepNode node,
) => _visits(session, steps, (record) => places.isIn(record, node));

/// The visits like the step [stepId] of [session]: those of [steps] on the
/// nodes it is on ([places]); for a step on no node, those at its very
/// place with its name. Just the step, when it is not among [steps].
List<Visit> visitsLike(
  SessionData session,
  Iterable<StepState> steps,
  StepPlaces places,
  String stepId,
) {
  final step = session.steps[stepId];
  if (step == null) return const [];
  final at = places.of(step);
  final visits = _visits(
    session,
    steps,
    (record) => at.isEmpty
        ? record.place == step.place && record.name == step.name
        : places.of(record).any(at.contains),
  );
  if (visits.any((visit) => visit.stepId == stepId)) return visits;
  final state = session.state.steps.where((s) => s.stepId == stepId);
  return [for (final s in state) Visit(step, s)];
}

/// The visit a double click on the step node [node] opens: the last of
/// [steps] of [session] on it; `null` when none is.
Visit? visitToOpen(
  SessionData session,
  Iterable<StepState> steps,
  StepPlaces places,
  StepNode node,
) => visitsTo(session, steps, places, node).lastOrNull;

/// How a start of a step ended; how a step stands is how its last start
/// did ([outcomeOf]).
enum StartOutcome {
  /// It goes on: nothing came after it yet.
  running,

  /// `step-finished`.
  finished,

  /// `step-failed`.
  failed,

  /// The process running it stopped: another start of the step came first,
  /// a resume ran the step again; or nothing came after it, and the
  /// process of its session is gone (`SessionData.interrupted`).
  interrupted,
}

/// How [step] of [session] stands: as its journal tells, but interrupted
/// while it runs in a session whose process is gone.
StartOutcome outcomeOf(SessionData session, StepState step) =>
    switch (step.status) {
      StepStatus.running when session.interrupted => StartOutcome.interrupted,
      StepStatus.running => StartOutcome.running,
      StepStatus.finished => StartOutcome.finished,
      StepStatus.failed => StartOutcome.failed,
    };

/// A start of a step, and how it ended.
typedef StepStart = ({DateTime at, StartOutcome outcome});

/// Every start of the step [stepId] of [session], in the order of its
/// journal; the last one interrupted when it was running and the process
/// of the session is gone.
List<StepStart> startsOf(SessionData session, String stepId) {
  final starts = <StepStart>[];
  void end(StartOutcome outcome) {
    final last = starts.lastOrNull;
    if (last != null && last.outcome == StartOutcome.running) {
      starts.last = (at: last.at, outcome: outcome);
    }
  }

  for (final event in session.events) {
    switch (event) {
      case StepStarted(stepId: final id, :final time) when id == stepId:
        end(StartOutcome.interrupted);
        starts.add((at: time, outcome: StartOutcome.running));
      case StepFinished(stepId: final id) when id == stepId:
        end(StartOutcome.finished);
      case StepFailed(stepId: final id) when id == stepId:
        end(StartOutcome.failed);
      default:
        break;
    }
  }
  if (session.interrupted) end(StartOutcome.interrupted);
  return starts;
}
