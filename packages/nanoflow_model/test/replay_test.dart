import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:test/test.dart';

// _stepB sorts before _stepA, so ordering by id would put it first.
const String _stepA = 'ee9b7a40-d1c8-4f35-9a6e-8b3c5d7f1e92';
const String _stepB = '2e9b7a40-d1c8-4f35-9a6e-8b3c5d7f1e92';
const String _stepC = '9a4d6c20-7e15-4b83-a0f9-3c2b8d5e7f41';
const String _output = '5f2d8b6a-1c93-4e07-a4b8-9e3c7a1d5b20';
const String _result = '7b1a9e3c-52d8-4f60-b4a7-1d9c3e5f8a24';
const String _graphA = '3f9c2a7e-5b1d-4c8e-9a6f-0d2e4b7c1a35';
const String _graphB = '8e1f4b2a-6c3d-4f7e-b5a9-2d0c7e6f1b48';

/// The [second]th second of a fixed minute, so that a later event has a later
/// time.
DateTime _at(int second) => DateTime.utc(2026, 10, 3, 10, 0, second, 482);

SessionStarted _sessionStarted(int second, {String? code = 'sha256:a'}) =>
    SessionStarted(time: _at(second), code: code);

SessionResumed _sessionResumed(
  int second, {
  String? code = 'sha256:a',
  String? graphId,
}) => SessionResumed(time: _at(second), code: code, graphId: graphId);

StepStarted _stepStarted(int second, String stepId) =>
    StepStarted(time: _at(second), stepId: stepId);

StepFinished _stepFinished(
  int second,
  String stepId, {
  String? outputId = _output,
}) => StepFinished(time: _at(second), stepId: stepId, outputId: outputId);

StepFailed _stepFailed(int second, String stepId, {String error = 'boom'}) =>
    StepFailed(time: _at(second), stepId: stepId, error: error, stack: '#0\n');

SessionFinished _sessionFinished(int second, {String? outputId = _result}) =>
    SessionFinished(time: _at(second), outputId: outputId);

SessionFailed _sessionFailed(int second, {String error = 'StateError: no'}) =>
    SessionFailed(time: _at(second), error: error, stack: '#0\n');

void main() {
  group('session', () {
    test('is running with no steps for an empty journal', () {
      final state = replaySession(const []);

      expect(state.status, SessionStatus.running);
      expect(state.steps, isEmpty);
      expect(state.startedAt, isNull);
      expect(state.finishedAt, isNull);
      expect(state.outputId, isNull);
      expect(state.error, isNull);
      expect(state.codes, isEmpty);
      expect(state.graphIds, isEmpty);
    });

    test('is running from session-started, which gives startedAt', () {
      final state = replaySession([_sessionStarted(1)]);

      expect(state.status, SessionStatus.running);
      expect(state.steps, isEmpty);
      expect(state.startedAt, _at(1));
      expect(state.finishedAt, isNull);
    });

    test('is finished after session-finished, which gives finishedAt and '
        'outputId', () {
      final state = replaySession([
        _sessionStarted(1),
        _stepStarted(2, _stepA),
        _stepFinished(3, _stepA),
        _sessionFinished(4),
      ]);

      expect(state.status, SessionStatus.finished);
      expect(state.startedAt, _at(1));
      expect(state.finishedAt, _at(4));
      expect(state.outputId, _result);
      expect(state.error, isNull);
    });

    test('is failed after session-failed, which gives finishedAt and '
        'error', () {
      final state = replaySession([
        _sessionStarted(1),
        _stepStarted(2, _stepA),
        _stepFailed(3, _stepA, error: 'Exception: boom'),
        _sessionFailed(4, error: 'Exception: boom'),
      ]);

      expect(state.status, SessionStatus.failed);
      expect(state.finishedAt, _at(4));
      expect(state.error, 'Exception: boom');
      expect(state.outputId, isNull);
    });

    test('stays running when a step fails and the workflow goes on', () {
      final state = replaySession([
        _sessionStarted(1),
        _stepStarted(2, _stepA),
        _stepFailed(3, _stepA),
      ]);

      expect(state.status, SessionStatus.running);
      expect(state.finishedAt, isNull);
      expect(state.error, isNull);
    });

    test('takes codes from session-started and each session-resumed, in '
        'order', () {
      final state = replaySession([
        _sessionStarted(1, code: 'sha256:a'),
        _stepStarted(2, _stepA),
        _sessionResumed(3, code: null),
        _sessionResumed(4, code: 'sha256:b', graphId: _graphA),
      ]);

      expect(state.codes, ['sha256:a', null, 'sha256:b']);
      expect(state.startedAt, _at(1));
    });

    test('takes graphIds only from session-resumed that has one', () {
      final state = replaySession([
        _sessionStarted(1),
        _sessionResumed(2, graphId: _graphA),
        _sessionResumed(3),
        _sessionResumed(4, graphId: _graphB),
      ]);

      expect(state.graphIds, [_graphA, _graphB]);
    });

    test('has codes and graphIds that cannot be changed', () {
      final state = replaySession([_sessionStarted(1)]);

      expect(() => state.codes.add(null), throwsUnsupportedError);
      expect(() => state.graphIds.add(_graphA), throwsUnsupportedError);
    });
  });

  group('steps', () {
    test('take startedAt from step-started and are running until an '
        'outcome', () {
      final state = replaySession([
        _sessionStarted(1),
        _stepStarted(2, _stepA),
      ]);

      final step = state.steps.single;
      expect(step.stepId, _stepA);
      expect(step.status, StepStatus.running);
      expect(step.starts, 1);
      expect(step.startedAt, _at(2));
      expect(step.finishedAt, isNull);
      expect(step.outputId, isNull);
      expect(step.error, isNull);
    });

    test('take finishedAt and outputId from step-finished', () {
      final state = replaySession([
        _sessionStarted(1),
        _stepStarted(2, _stepA),
        _stepFinished(5, _stepA),
      ]);

      final step = state.steps.single;
      expect(step.status, StepStatus.finished);
      expect(step.startedAt, _at(2));
      expect(step.finishedAt, _at(5));
      expect(step.outputId, _output);
      expect(step.error, isNull);
    });

    test('take finishedAt and error from step-failed', () {
      final state = replaySession([
        _sessionStarted(1),
        _stepStarted(2, _stepA),
        _stepFailed(4, _stepA, error: 'Exception: boom'),
      ]);

      final step = state.steps.single;
      expect(step.status, StepStatus.failed);
      expect(step.finishedAt, _at(4));
      expect(step.outputId, isNull);
      expect(step.error, 'Exception: boom');
    });

    test('count each step-started, and keep the first startedAt', () {
      final state = replaySession([
        _sessionStarted(1),
        _stepStarted(2, _stepA),
        _sessionResumed(6),
        _stepStarted(7, _stepA),
        _stepFinished(9, _stepA),
      ]);

      final step = state.steps.single;
      expect(step.starts, 2);
      expect(step.startedAt, _at(2));
      expect(step.finishedAt, _at(9));
      expect(step.status, StepStatus.finished);
    });

    test('are running again when a failed step starts again, without the '
        'outcome of the start before', () {
      final state = replaySession([
        _sessionStarted(1),
        _stepStarted(2, _stepA),
        _stepFailed(3, _stepA),
        _sessionFailed(4),
        _sessionResumed(5),
        _stepStarted(6, _stepA),
      ]);

      final step = state.steps.single;
      expect(step.status, StepStatus.running);
      expect(step.starts, 2);
      expect(step.finishedAt, isNull);
      expect(step.error, isNull);
      expect(state.status, SessionStatus.running);
    });

    test('follow their first step-started, not the order of their ids', () {
      final state = replaySession([
        _sessionStarted(1),
        _stepStarted(2, _stepA),
        _stepStarted(3, _stepB),
        _stepFinished(4, _stepB),
        _stepStarted(5, _stepC),
        _stepFinished(6, _stepA),
        _stepStarted(7, _stepA),
      ]);

      expect(
        [for (final step in state.steps) step.stepId],
        [_stepA, _stepB, _stepC],
      );
      expect([for (final step in state.steps) step.starts], [2, 1, 1]);
    });

    test('are a list that cannot be changed', () {
      final state = replaySession([
        _sessionStarted(1),
        _stepStarted(2, _stepA),
      ]);

      expect(() => state.steps.removeLast(), throwsUnsupportedError);
    });

    test('are left alone by an outcome of a step that never started', () {
      final state = replaySession([
        _sessionStarted(1),
        _stepStarted(2, _stepA),
        _stepFinished(3, _stepB),
        _stepFailed(4, _stepC),
      ]);

      expect([for (final step in state.steps) step.stepId], [_stepA]);
      expect(state.steps.single.status, StepStatus.running);
    });
  });

  group('events', () {
    test('that are unknown are skipped', () {
      final state = replaySession([
        _sessionStarted(1),
        Event.fromJson({'time': formatTime(_at(2)), 'event': 'session-paused'}),
        _stepStarted(3, _stepA),
        // A known name with a bad or missing field is an unknown event too.
        Event.fromJson({
          'time': 'not a time',
          'event': 'session-finished',
          'outputId': null,
        }),
        Event.fromJson({
          'time': formatTime(_at(5)),
          'event': 'step-finished',
          'stepId': _stepA,
        }),
        Event.fromJson({'event': 'something-new'}),
      ]);

      expect(state.status, SessionStatus.running);
      expect(state.finishedAt, isNull);
      expect(state.steps.single.status, StepStatus.running);
      expect(state.steps.single.starts, 1);
    });

    test('decide the status by the last known one', () {
      final state = replaySession([
        _sessionStarted(1),
        _sessionFinished(2),
        Event.fromJson({'event': 'something-new'}),
      ]);

      expect(state.status, SessionStatus.finished);
      expect(state.finishedAt, _at(2));
    });
  });
}
