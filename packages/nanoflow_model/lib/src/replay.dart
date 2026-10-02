import 'events.dart';

/// Where a session is, as its last event tells.
enum SessionStatus {
  /// The last event is neither `session-finished` nor `session-failed`.
  running,

  /// The last event is `session-finished`.
  finished,

  /// The last event is `session-failed`.
  failed,
}

/// Where a step is, as the events after its last `step-started` tell.
enum StepStatus {
  /// No `step-finished` or `step-failed` after the last `step-started`.
  running,

  /// A `step-finished` after the last `step-started`.
  finished,

  /// A `step-failed` after the last `step-started`.
  failed,
}

/// What replaying a session's journal says about one step.
final class StepState {
  const StepState({
    required this.stepId,
    required this.status,
    required this.starts,
    required this.startedAt,
    required this.finishedAt,
    required this.outputId,
    required this.error,
  });

  final String stepId;

  final StepStatus status;

  /// How many times the step ran live: the number of its `step-started`.
  final int starts;

  /// The time of the first `step-started`.
  final DateTime startedAt;

  /// The time of the outcome of the last start; `null` while the step runs.
  final DateTime? finishedAt;

  /// The `outputId` of `step-finished`; `null` unless the step finished.
  final String? outputId;

  /// The `error` of `step-failed`; `null` unless the step failed.
  final String? error;
}

/// What replaying a session's journal says about the session.
///
/// Never stored: the state is computed again from the events.
final class SessionState {
  const SessionState({
    required this.status,
    required this.steps,
    required this.startedAt,
    required this.finishedAt,
    required this.outputId,
    required this.error,
    required this.codes,
    required this.graphIds,
  });

  final SessionStatus status;

  /// The steps in the order of their first `step-started`.
  final List<StepState> steps;

  /// The time of `session-started`; `null` when the journal has none.
  final DateTime? startedAt;

  /// The time of the last event once the session has ended; `null` while it
  /// runs.
  final DateTime? finishedAt;

  /// The `outputId` of `session-finished`; `null` unless the session
  /// finished.
  final String? outputId;

  /// The `error` of `session-failed`; `null` unless the session failed.
  final String? error;

  /// The hashes of the code that ran the session, in order: of
  /// `session-started`, then of each `session-resumed`.
  final List<String?> codes;

  /// The documents with the graph snapshots of the `session-resumed` events
  /// that have one, in order.
  final List<String> graphIds;
}

/// The state of a session after [events], which are in the order of its
/// journal.
///
/// Events this version does not know are skipped. An outcome of a step with
/// no `step-started` changes no step. Replaying never fails.
SessionState replaySession(List<Event> events) {
  // Insertion order is the order of the first `step-started`.
  final steps = <String, _Step>{};
  final codes = <String?>[];
  final graphIds = <String>[];
  DateTime? startedAt;
  KnownEvent? last;

  for (final event in events) {
    if (event is! KnownEvent) continue;
    last = event;
    switch (event) {
      case SessionStarted(:final time, :final code):
        startedAt ??= time;
        codes.add(code);
      case SessionResumed(:final code, :final graphId):
        codes.add(code);
        if (graphId != null) graphIds.add(graphId);
      case StepStarted(:final stepId, :final time):
        (steps[stepId] ??= _Step(stepId, time)).start();
      case StepFinished(:final stepId, :final time, :final outputId):
        steps[stepId]?.end(StepStatus.finished, time, outputId: outputId);
      case StepFailed(:final stepId, :final time, :final error):
        steps[stepId]?.end(StepStatus.failed, time, error: error);
      case SessionFinished() || SessionFailed():
        break;
    }
  }

  final (status, finishedAt, outputId, error) = switch (last) {
    SessionFinished(:final time, :final outputId) => (
      SessionStatus.finished,
      time,
      outputId,
      null,
    ),
    SessionFailed(:final time, :final error) => (
      SessionStatus.failed,
      time,
      null,
      error,
    ),
    _ => (SessionStatus.running, null, null, null),
  };
  return SessionState(
    status: status,
    steps: List.unmodifiable([for (final step in steps.values) step.freeze()]),
    startedAt: startedAt,
    finishedAt: finishedAt,
    outputId: outputId,
    error: error,
    codes: List.unmodifiable(codes),
    graphIds: List.unmodifiable(graphIds),
  );
}

/// A step while its events are being replayed.
class _Step {
  _Step(this.stepId, this.startedAt);

  final String stepId;
  final DateTime startedAt;
  int starts = 0;
  StepStatus status = StepStatus.running;
  DateTime? finishedAt;
  String? outputId;
  String? error;

  /// A new start: the outcome of the start before no longer holds.
  void start() {
    starts++;
    status = StepStatus.running;
    finishedAt = null;
    outputId = null;
    error = null;
  }

  void end(
    StepStatus status,
    DateTime time, {
    String? outputId,
    String? error,
  }) {
    this.status = status;
    finishedAt = time;
    this.outputId = outputId;
    this.error = error;
  }

  StepState freeze() => StepState(
    stepId: stepId,
    status: status,
    starts: starts,
    startedAt: startedAt,
    finishedAt: finishedAt,
    outputId: outputId,
    error: error,
  );
}
