import 'events.dart';

/// Where a run is, as its last event and its steps tell.
enum RunStatus {
  /// The run has no step yet.
  pending,

  /// The run has steps and no last event.
  running,

  /// The last event is `run-finished`.
  finished,

  /// The last event is `run-failed`.
  failed,

  /// The last event is `run-split`.
  split,
}

/// Where a step is.
enum StepStatus {
  /// No `step-finished` yet.
  running,

  /// Its command ended: there is a `step-finished`.
  finished,

  /// A `run-failed` names the step. It may still have a `step-finished`: a
  /// route error comes after one.
  failed,
}

/// What replaying a run's journal says about one step.
final class StepState {
  const StepState({
    required this.stepId,
    required this.node,
    required this.status,
    required this.starts,
    required this.startedAt,
    required this.finishedAt,
    required this.exitCode,
  });

  final String stepId;

  /// The name of the node, from the first `step-started`.
  final String node;

  final StepStatus status;

  /// How many times the command was started: the number of `step-started`.
  final int starts;

  /// The time of the first `step-started`.
  final DateTime startedAt;

  /// The time of `step-finished`; `null` while the step runs.
  final DateTime? finishedAt;

  /// The exit code from `step-finished`; `null` while the step runs.
  final int? exitCode;
}

/// What replaying a run's journal says about the run.
///
/// Never stored: the state is computed again from the events.
final class RunState {
  const RunState({
    required this.runId,
    required this.status,
    required this.steps,
    required this.startedAt,
    required this.finishedAt,
    required this.error,
  });

  final String runId;

  final RunStatus status;

  /// The steps in the order of their first `step-started`.
  final List<StepState> steps;

  /// The time of `run-started`; `null` when the journal has none.
  final DateTime? startedAt;

  /// The time of the run's last event once the run has ended; `null` while it
  /// goes on.
  final DateTime? finishedAt;

  /// The `error` of `run-failed`; `null` when the run has not failed.
  final String? error;

  /// The last step, which a running run is executing; `null` before the first.
  StepState? get currentStep => steps.isEmpty ? null : steps.last;

  /// Whether the run's last event has been written: it finished, failed or
  /// split.
  bool get isEnded => switch (status) {
    RunStatus.finished || RunStatus.failed || RunStatus.split => true,
    RunStatus.pending || RunStatus.running => false,
  };
}

/// The state of run [runId] after [events], which are in the order of its
/// journal.
///
/// Events of another run are skipped, and so are events this version does not
/// know. A `step-finished` or a `run-failed` that names a step with no
/// `step-started` changes no step. Replaying never fails.
RunState replay(String runId, Iterable<Event> events) {
  // Insertion order is the order of the first `step-started`.
  final steps = <String, _Step>{};
  DateTime? startedAt;
  KnownEvent? last;

  for (final event in events) {
    if (event is! KnownEvent || event.runId != runId) continue;
    last = event;
    switch (event) {
      case RunStarted(:final time):
        startedAt ??= time;
      case StepStarted(:final stepId, :final node, :final time):
        (steps[stepId] ??= _Step(stepId, node, time)).starts++;
      case StepFinished(:final stepId, :final exitCode, :final time):
        steps[stepId]?.finish(time, exitCode);
      case RunFailed(:final stepId):
        steps[stepId]?.failed = true;
      case RunSplit() || RunFinished():
        break;
    }
  }

  final (RunStatus status, DateTime? finishedAt) = switch (last) {
    RunFinished(:final time) => (RunStatus.finished, time),
    RunFailed(:final time) => (RunStatus.failed, time),
    RunSplit(:final time) => (RunStatus.split, time),
    _ => (steps.isEmpty ? RunStatus.pending : RunStatus.running, null),
  };
  return RunState(
    runId: runId,
    status: status,
    steps: List.unmodifiable([for (final step in steps.values) step.freeze()]),
    startedAt: startedAt,
    finishedAt: finishedAt,
    error: last is RunFailed ? last.error : null,
  );
}

/// A step while its events are being replayed.
class _Step {
  _Step(this.stepId, this.node, this.startedAt);

  final String stepId;
  final String node;
  final DateTime startedAt;
  int starts = 0;
  DateTime? finishedAt;
  int? exitCode;
  bool failed = false;

  void finish(DateTime time, int code) {
    finishedAt = time;
    exitCode = code;
  }

  StepState freeze() => StepState(
    stepId: stepId,
    node: node,
    status: failed
        ? StepStatus.failed
        : finishedAt != null
        ? StepStatus.finished
        : StepStatus.running,
    starts: starts,
    startedAt: startedAt,
    finishedAt: finishedAt,
    exitCode: exitCode,
  );
}
