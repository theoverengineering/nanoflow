import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:test/test.dart';

const String _run = '0c6e1f7a-93d4-4b58-8e21-5a7d3c9b4f06';
const String _otherRun = '7b1a9e3c-52d8-4f60-b4a7-1d9c3e5f8a24';

// _stepB sorts before _stepA, so ordering by id would put it first.
const String _stepA = 'ee9b7a40-d1c8-4f35-9a6e-8b3c5d7f1e92';
const String _stepB = '2e9b7a40-d1c8-4f35-9a6e-8b3c5d7f1e92';
const String _stepC = '9a4d6c20-7e15-4b83-a0f9-3c2b8d5e7f41';
const String _document = '5f2d8b6a-1c93-4e07-a4b8-9e3c7a1d5b20';

/// The [second]th second of a fixed minute, so that a later event has a later
/// time.
DateTime _at(int second) => DateTime.utc(2026, 9, 20, 14, 3, second, 470);

RunStarted _runStarted(int second, {String runId = _run}) =>
    RunStarted(runId: runId, time: _at(second), node: 'collect');

StepStarted _stepStarted(
  int second,
  String stepId, {
  String node = 'collect',
  String runId = _run,
}) => StepStarted(runId: runId, time: _at(second), stepId: stepId, node: node);

StepFinished _stepFinished(
  int second,
  String stepId, {
  int exitCode = 0,
  String? outputId = _document,
  String runId = _run,
}) => StepFinished(
  runId: runId,
  time: _at(second),
  stepId: stepId,
  exitCode: exitCode,
  outputId: outputId,
);

RunSplit _runSplit(int second, {String runId = _run}) =>
    RunSplit(runId: runId, time: _at(second));

RunFinished _runFinished(int second, {String runId = _run}) =>
    RunFinished(runId: runId, time: _at(second));

RunFailed _runFailed(
  int second,
  String stepId, {
  String error = 'exited with code 2',
  String runId = _run,
}) => RunFailed(runId: runId, time: _at(second), stepId: stepId, error: error);

void main() {
  group('status', () {
    test('is pending when the run has started but no step has', () {
      final state = replay(_run, [_runStarted(1)]);

      expect(state.runId, _run);
      expect(state.status, RunStatus.pending);
      expect(state.steps, isEmpty);
      expect(state.currentStep, isNull);
      expect(state.startedAt, _at(1));
      expect(state.finishedAt, isNull);
      expect(state.error, isNull);
      expect(state.isEnded, isFalse);
    });

    test('is pending with no run-started too, and then has no startedAt', () {
      final state = replay(_run, const []);

      expect(state.runId, _run);
      expect(state.status, RunStatus.pending);
      expect(state.steps, isEmpty);
      expect(state.startedAt, isNull);
      expect(state.finishedAt, isNull);
      expect(state.error, isNull);
      expect(state.isEnded, isFalse);
    });

    test('is running while the run has steps and no last event', () {
      final state = replay(_run, [_runStarted(1), _stepStarted(2, _stepA)]);

      expect(state.status, RunStatus.running);
      expect(state.startedAt, _at(1));
      expect(state.finishedAt, isNull);
      expect(state.error, isNull);
      expect(state.isEnded, isFalse);
      expect(state.currentStep?.stepId, _stepA);
    });

    test('is running between a finished step and the next one', () {
      final state = replay(_run, [
        _runStarted(1),
        _stepStarted(2, _stepA),
        _stepFinished(3, _stepA),
      ]);

      expect(state.status, RunStatus.running);
      expect(state.finishedAt, isNull);
      expect(state.isEnded, isFalse);
      expect(state.currentStep?.status, StepStatus.finished);
    });

    test('is finished after run-finished, which gives finishedAt', () {
      final state = replay(_run, [
        _runStarted(1),
        _stepStarted(2, _stepA),
        _stepFinished(3, _stepA),
        _runFinished(4),
      ]);

      expect(state.status, RunStatus.finished);
      expect(state.finishedAt, _at(4));
      expect(state.error, isNull);
      expect(state.isEnded, isTrue);
      expect(state.currentStep?.status, StepStatus.finished);
    });

    test('is failed after run-failed, which gives error and finishedAt', () {
      final state = replay(_run, [
        _runStarted(1),
        _stepStarted(2, _stepA),
        _stepFinished(3, _stepA, exitCode: 2, outputId: null),
        _runFailed(4, _stepA, error: 'exited with code 2'),
      ]);

      expect(state.status, RunStatus.failed);
      expect(state.finishedAt, _at(4));
      expect(state.error, 'exited with code 2');
      expect(state.isEnded, isTrue);
    });

    test('is failed after run-failed even before any step finished', () {
      final state = replay(_run, [
        _runStarted(1),
        _stepStarted(2, _stepA),
        _runFailed(3, _stepA, error: 'printed no output'),
      ]);

      expect(state.status, RunStatus.failed);
      expect(state.error, 'printed no output');
      expect(state.currentStep?.status, StepStatus.failed);
      expect(state.currentStep?.finishedAt, isNull);
      expect(state.currentStep?.exitCode, isNull);
    });

    test('is split after run-split, which gives finishedAt', () {
      final state = replay(_run, [
        _runStarted(1),
        _stepStarted(2, _stepA, node: 'is-empty'),
        _stepFinished(3, _stepA),
        _runSplit(4),
      ]);

      expect(state.status, RunStatus.split);
      expect(state.finishedAt, _at(4));
      expect(state.error, isNull);
      expect(state.isEnded, isTrue);
    });

    test('follows the last event even when no step has started', () {
      // A journal never has a last event without a step before it, but a state
      // is still decided by its last event.
      final state = replay(_run, [_runStarted(1), _runFinished(2)]);

      expect(state.status, RunStatus.finished);
      expect(state.steps, isEmpty);
      expect(state.finishedAt, _at(2));
    });
  });

  group('steps', () {
    test('take node and startedAt from step-started', () {
      final state = replay(_run, [
        _runStarted(1),
        _stepStarted(2, _stepA, node: 'collect'),
      ]);

      final step = state.steps.single;
      expect(step.stepId, _stepA);
      expect(step.node, 'collect');
      expect(step.status, StepStatus.running);
      expect(step.starts, 1);
      expect(step.startedAt, _at(2));
      expect(step.finishedAt, isNull);
      expect(step.exitCode, isNull);
      expect(state.currentStep, same(step));
    });

    test('take finishedAt and exitCode from step-finished', () {
      final state = replay(_run, [
        _runStarted(1),
        _stepStarted(2, _stepA),
        _stepFinished(5, _stepA, exitCode: 3, outputId: null),
      ]);

      final step = state.steps.single;
      expect(step.status, StepStatus.finished);
      expect(step.startedAt, _at(2));
      expect(step.finishedAt, _at(5));
      expect(step.exitCode, 3);
    });

    test('count each step-started, and keep the first startedAt', () {
      final state = replay(_run, [
        _runStarted(1),
        _stepStarted(2, _stepA, node: 'collect'),
        _stepStarted(7, _stepA, node: 'collect'),
      ]);

      final step = state.steps.single;
      expect(step.starts, 2);
      expect(step.startedAt, _at(2));
      expect(step.status, StepStatus.running);
      expect(state.status, RunStatus.running);
    });

    test('count restarts of a step that then finished', () {
      final state = replay(_run, [
        _runStarted(1),
        _stepStarted(2, _stepA),
        _stepStarted(7, _stepA),
        _stepFinished(9, _stepA),
      ]);

      final step = state.steps.single;
      expect(step.starts, 2);
      expect(step.startedAt, _at(2));
      expect(step.finishedAt, _at(9));
      expect(step.status, StepStatus.finished);
    });

    test('follow their first step-started, not the order of their ids', () {
      final state = replay(_run, [
        _runStarted(1),
        _stepStarted(2, _stepA, node: 'first'),
        _stepFinished(3, _stepA),
        _stepStarted(4, _stepB, node: 'second'),
        _stepFinished(5, _stepB),
        _stepStarted(6, _stepC, node: 'third'),
      ]);

      expect(
        [for (final step in state.steps) step.stepId],
        [_stepA, _stepB, _stepC],
      );
      expect(
        [for (final step in state.steps) step.node],
        ['first', 'second', 'third'],
      );
      expect(state.currentStep?.stepId, _stepC);
    });

    test('are not reordered when an earlier step starts again', () {
      final state = replay(_run, [
        _runStarted(1),
        _stepStarted(2, _stepA),
        _stepStarted(3, _stepB),
        _stepStarted(4, _stepA),
      ]);

      expect([for (final step in state.steps) step.stepId], [_stepA, _stepB]);
      expect([for (final step in state.steps) step.starts], [2, 1]);
      expect(state.currentStep?.stepId, _stepB);
    });

    test('are a list that cannot be changed', () {
      final state = replay(_run, [_runStarted(1), _stepStarted(2, _stepA)]);

      expect(() => state.steps.removeLast(), throwsA(isA<UnsupportedError>()));
    });

    test('are ignored when a later event names a step that never started', () {
      final state = replay(_run, [
        _runStarted(1),
        _stepStarted(2, _stepA),
        _stepFinished(3, _stepB),
        _runFailed(4, _stepC),
      ]);

      expect([for (final step in state.steps) step.stepId], [_stepA]);
      expect(state.steps.single.status, StepStatus.running);
      expect(state.status, RunStatus.failed);
    });
  });

  group('run-failed', () {
    test('marks its step failed even though the step has step-finished', () {
      // A route error: the command exited 0 and printed a document, then no
      // target was found for it.
      final state = replay(_run, [
        _runStarted(1),
        _stepStarted(2, _stepA, node: 'verdict'),
        _stepFinished(3, _stepA, exitCode: 0, outputId: _document),
        _runFailed(4, _stepA, error: 'no target for outcome "maybe"'),
      ]);

      final step = state.steps.single;
      expect(step.status, StepStatus.failed);
      expect(step.finishedAt, _at(3));
      expect(step.exitCode, 0);
      expect(state.status, RunStatus.failed);
      expect(state.error, 'no target for outcome "maybe"');
      expect(state.finishedAt, _at(4));
    });

    test('marks only the step it names', () {
      final state = replay(_run, [
        _runStarted(1),
        _stepStarted(2, _stepA),
        _stepFinished(3, _stepA),
        _stepStarted(4, _stepB),
        _stepFinished(5, _stepB, exitCode: 1, outputId: null),
        _runFailed(6, _stepB, error: 'exited with code 1'),
      ]);

      expect(
        [for (final step in state.steps) step.status],
        [StepStatus.finished, StepStatus.failed],
      );
    });
  });

  group('events', () {
    test('that are unknown are skipped, with or without a run', () {
      final state = replay(_run, [
        _runStarted(1),
        Event.fromJson({
          'runId': _run,
          'time': formatTime(_at(2)),
          'event': 'run-paused',
        }),
        _stepStarted(3, _stepA),
        // A known name with a bad or missing field is an unknown event too.
        Event.fromJson({
          'runId': _run,
          'time': 'not a time',
          'event': 'run-finished',
        }),
        Event.fromJson({
          'runId': _run,
          'time': formatTime(_at(5)),
          'event': 'step-finished',
          'stepId': _stepA,
        }),
        Event.fromJson({'event': 'something-new'}),
      ]);

      expect(state.status, RunStatus.running);
      expect(state.finishedAt, isNull);
      expect(state.steps.single.status, StepStatus.running);
      expect(state.steps.single.starts, 1);
    });

    test('of another run are skipped', () {
      final state = replay(_run, [
        _runStarted(1),
        _runStarted(2, runId: _otherRun),
        _stepStarted(3, _stepA),
        _stepStarted(4, _stepB, runId: _otherRun),
        _stepFinished(5, _stepB, runId: _otherRun),
        _runFailed(6, _stepB, runId: _otherRun),
        _runFinished(7, runId: _otherRun),
      ]);

      expect(state.runId, _run);
      expect(state.status, RunStatus.running);
      expect(state.startedAt, _at(1));
      expect(state.finishedAt, isNull);
      expect(state.error, isNull);
      expect([for (final step in state.steps) step.stepId], [_stepA]);
    });

    test('of two runs in one list give each run its own state', () {
      final events = [
        _runStarted(1),
        _runStarted(2, runId: _otherRun),
        _stepStarted(3, _stepA),
        _stepStarted(4, _stepB, runId: _otherRun),
        _stepFinished(5, _stepA),
        _runFinished(6),
        _runFailed(7, _stepB, runId: _otherRun, error: 'boom'),
      ];

      final state = replay(_run, events);
      final other = replay(_otherRun, events);

      expect(state.status, RunStatus.finished);
      expect(state.finishedAt, _at(6));
      expect(state.error, isNull);
      expect(other.status, RunStatus.failed);
      expect(other.finishedAt, _at(7));
      expect(other.error, 'boom');
      expect(other.steps.single.stepId, _stepB);
    });

    test('can come from any iterable, once', () {
      final events = [_runStarted(1), _stepStarted(2, _stepA)];
      var reads = 0;

      final state = replay(
        _run,
        events.map((event) {
          reads++;
          return event;
        }),
      );

      expect(reads, events.length);
      expect(state.steps, hasLength(1));
    });
  });

  group('currentStep', () {
    test('is the last step', () {
      final state = replay(_run, [
        _runStarted(1),
        _stepStarted(2, _stepA),
        _stepFinished(3, _stepA),
        _stepStarted(4, _stepB),
      ]);

      expect(state.currentStep, same(state.steps.last));
      expect(state.currentStep?.stepId, _stepB);
    });
  });
}
