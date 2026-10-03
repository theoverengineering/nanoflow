/// What the step details window shows of a step: the step among all the
/// visits to its node, how it went, when it started and ended, and its
/// place in the code; or, for a node without steps, the node's name and
/// place alone (docs/ui-spec.md «Окно деталей шага»; spec §9 «Окно шага»).
/// Pure: the time is passed in.
library;

import 'package:nanoflow_model/nanoflow_model.dart';

import 'session_feed.dart';
import 'step_details.dart';
import 'step_places.dart';
import 'texts.dart';
import 'visits.dart';

/// How the step went, at the top of the window: `finished · 4m 02s`,
/// `running · 2m 14s`, `failed · 0.1s`.
typedef StepResult = ({StepStatus status, String text});

/// A start of the step, as the window lists it: `14:09:20`, and how it
/// ended.
typedef StartText = ({String time, StartOutcome outcome});

/// The facts of the step: `Started`, `Finished`, `Starts`.
final class StepFacts {
  StepFacts._({
    required this.started,
    required this.finished,
    required this.took,
    required List<StartText> starts,
  }) : starts = List.unmodifiable(starts);

  /// The first start, to the millisecond: `14:09:20.118`.
  final String started;

  /// The outcome of the last start, to the millisecond; `null` while the
  /// step runs.
  final String? finished;

  /// `took 4m 02s`; `null` with [finished].
  final String? took;

  /// Every start, and how it ended.
  final List<StartText> starts;
}

/// The step details window on a step, or on a node without one.
final class VisitDetails {
  VisitDetails._({
    required this.name,
    required this.place,
    required List<Visit> visits,
    this.index,
    this.step,
    this.result,
    this.facts,
    this.copy,
  }) : visits = List.unmodifiable(visits);

  /// The step's name, or the node's.
  final String name;

  /// Where the step was called, or where the node is: `lib/review.dart:49`.
  final String? place;

  /// Every visit to the step's node among the steps shown, in order.
  final List<Visit> visits;

  /// Which of [visits] is shown; `null` for a node alone.
  final int? index;

  Visit? get visit => switch (index) {
    final i? => visits[i],
    null => null,
  };

  /// `Visit 2 of 2`.
  String? get visitText =>
      index == null ? null : 'Visit ${index! + 1} of ${visits.length}';

  /// The visit before, and the one after.
  Visit? get previous =>
      index != null && index! > 0 ? visits[index! - 1] : null;
  Visit? get next =>
      index != null && index! < visits.length - 1 ? visits[index! + 1] : null;

  /// The step: its output, its error with the stack.
  final StepDetails? step;

  final StepResult? result;

  final StepFacts? facts;

  /// The copies the step is in: `pkg 2 › target 1`; `null` outside copies.
  final String? copy;
}

/// The window on the step [stepId] of [session] among [steps], the steps
/// shown, at [now]; [copyOf] names the copy of a step. Without the step —
/// for `Current graph`, or a node without steps — the window shows the
/// step node [node] alone.
VisitDetails visitDetails({
  required SessionData? session,
  required Iterable<StepState> steps,
  required StepPlaces places,
  required String? stepId,
  StepNode? node,
  String? Function(String stepId)? copyOf,
  required DateTime now,
}) {
  final details = session == null || stepId == null
      ? null
      : stepDetails(session, stepId);
  if (session == null || details == null) {
    return VisitDetails._(
      name: node?.name ?? '',
      place: node?.place,
      visits: const [],
    );
  }
  final visits = visitsLike(session, steps, places, details.stepId);
  final index = visits.indexWhere((visit) => visit.stepId == details.stepId);
  final state = visits[index].state;
  final took = formatDuration(
    (state.finishedAt ?? now).difference(state.startedAt),
  );
  return VisitDetails._(
    name: details.name,
    place: details.place,
    visits: visits,
    index: index,
    step: details,
    result: (status: state.status, text: '${state.status.name} · $took'),
    facts: StepFacts._(
      started: clockTimeMillis(state.startedAt),
      finished: state.finishedAt == null
          ? null
          : clockTimeMillis(state.finishedAt!),
      took: state.finishedAt == null ? null : 'took $took',
      starts: [
        for (final start in startsOf(session, details.stepId))
          (time: clockTime(start.at), outcome: start.outcome),
      ],
    ),
    copy: copyOf?.call(details.stepId),
  );
}
