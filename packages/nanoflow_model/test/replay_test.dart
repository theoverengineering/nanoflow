import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:test/test.dart';

// _effectB sorts before _effectA, so ordering by id would put it first.
const String _effectA = 'ee9b7a40-d1c8-4f35-9a6e-8b3c5d7f1e92';
const String _effectB = '2e9b7a40-d1c8-4f35-9a6e-8b3c5d7f1e92';
const String _effectC = '9a4d6c20-7e15-4b83-a0f9-3c2b8d5e7f41';
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

EffectStarted _effectStarted(int second, String effectId) =>
    EffectStarted(time: _at(second), effectId: effectId);

EffectFinished _effectFinished(
  int second,
  String effectId, {
  String? outputId = _output,
}) => EffectFinished(time: _at(second), effectId: effectId, outputId: outputId);

EffectFailed _effectFailed(
  int second,
  String effectId, {
  String error = 'boom',
}) => EffectFailed(
  time: _at(second),
  effectId: effectId,
  error: error,
  stack: '#0\n',
);

SessionFinished _sessionFinished(int second, {String? outputId = _result}) =>
    SessionFinished(time: _at(second), outputId: outputId);

SessionFailed _sessionFailed(int second, {String error = 'StateError: no'}) =>
    SessionFailed(time: _at(second), error: error, stack: '#0\n');

void main() {
  group('session', () {
    test('is running with no effects for an empty journal', () {
      final state = replaySession(const []);

      expect(state.status, SessionStatus.running);
      expect(state.effects, isEmpty);
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
      expect(state.effects, isEmpty);
      expect(state.startedAt, _at(1));
      expect(state.finishedAt, isNull);
    });

    test('is finished after session-finished, which gives finishedAt and '
        'outputId', () {
      final state = replaySession([
        _sessionStarted(1),
        _effectStarted(2, _effectA),
        _effectFinished(3, _effectA),
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
        _effectStarted(2, _effectA),
        _effectFailed(3, _effectA, error: 'Exception: boom'),
        _sessionFailed(4, error: 'Exception: boom'),
      ]);

      expect(state.status, SessionStatus.failed);
      expect(state.finishedAt, _at(4));
      expect(state.error, 'Exception: boom');
      expect(state.outputId, isNull);
    });

    test('stays running when an effect fails and the workflow goes on', () {
      final state = replaySession([
        _sessionStarted(1),
        _effectStarted(2, _effectA),
        _effectFailed(3, _effectA),
      ]);

      expect(state.status, SessionStatus.running);
      expect(state.finishedAt, isNull);
      expect(state.error, isNull);
    });

    test('takes codes from session-started and each session-resumed, in '
        'order', () {
      final state = replaySession([
        _sessionStarted(1, code: 'sha256:a'),
        _effectStarted(2, _effectA),
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

  group('effects', () {
    test('take startedAt from effect-started and are running until an '
        'outcome', () {
      final state = replaySession([
        _sessionStarted(1),
        _effectStarted(2, _effectA),
      ]);

      final effect = state.effects.single;
      expect(effect.effectId, _effectA);
      expect(effect.status, EffectStatus.running);
      expect(effect.starts, 1);
      expect(effect.startedAt, _at(2));
      expect(effect.finishedAt, isNull);
      expect(effect.outputId, isNull);
      expect(effect.error, isNull);
    });

    test('take finishedAt and outputId from effect-finished', () {
      final state = replaySession([
        _sessionStarted(1),
        _effectStarted(2, _effectA),
        _effectFinished(5, _effectA),
      ]);

      final effect = state.effects.single;
      expect(effect.status, EffectStatus.finished);
      expect(effect.startedAt, _at(2));
      expect(effect.finishedAt, _at(5));
      expect(effect.outputId, _output);
      expect(effect.error, isNull);
    });

    test('take finishedAt and error from effect-failed', () {
      final state = replaySession([
        _sessionStarted(1),
        _effectStarted(2, _effectA),
        _effectFailed(4, _effectA, error: 'Exception: boom'),
      ]);

      final effect = state.effects.single;
      expect(effect.status, EffectStatus.failed);
      expect(effect.finishedAt, _at(4));
      expect(effect.outputId, isNull);
      expect(effect.error, 'Exception: boom');
    });

    test('count each effect-started, and keep the first startedAt', () {
      final state = replaySession([
        _sessionStarted(1),
        _effectStarted(2, _effectA),
        _sessionResumed(6),
        _effectStarted(7, _effectA),
        _effectFinished(9, _effectA),
      ]);

      final effect = state.effects.single;
      expect(effect.starts, 2);
      expect(effect.startedAt, _at(2));
      expect(effect.finishedAt, _at(9));
      expect(effect.status, EffectStatus.finished);
    });

    test('are running again when a failed effect starts again, without the '
        'outcome of the start before', () {
      final state = replaySession([
        _sessionStarted(1),
        _effectStarted(2, _effectA),
        _effectFailed(3, _effectA),
        _sessionFailed(4),
        _sessionResumed(5),
        _effectStarted(6, _effectA),
      ]);

      final effect = state.effects.single;
      expect(effect.status, EffectStatus.running);
      expect(effect.starts, 2);
      expect(effect.finishedAt, isNull);
      expect(effect.error, isNull);
      expect(state.status, SessionStatus.running);
    });

    test('follow their first effect-started, not the order of their ids', () {
      final state = replaySession([
        _sessionStarted(1),
        _effectStarted(2, _effectA),
        _effectStarted(3, _effectB),
        _effectFinished(4, _effectB),
        _effectStarted(5, _effectC),
        _effectFinished(6, _effectA),
        _effectStarted(7, _effectA),
      ]);

      expect(
        [for (final effect in state.effects) effect.effectId],
        [_effectA, _effectB, _effectC],
      );
      expect([for (final effect in state.effects) effect.starts], [2, 1, 1]);
    });

    test('are a list that cannot be changed', () {
      final state = replaySession([
        _sessionStarted(1),
        _effectStarted(2, _effectA),
      ]);

      expect(() => state.effects.removeLast(), throwsUnsupportedError);
    });

    test('are left alone by an outcome of an effect that never started', () {
      final state = replaySession([
        _sessionStarted(1),
        _effectStarted(2, _effectA),
        _effectFinished(3, _effectB),
        _effectFailed(4, _effectC),
      ]);

      expect([for (final effect in state.effects) effect.effectId], [_effectA]);
      expect(state.effects.single.status, EffectStatus.running);
    });
  });

  group('events', () {
    test('that are unknown are skipped', () {
      final state = replaySession([
        _sessionStarted(1),
        Event.fromJson({'time': formatTime(_at(2)), 'event': 'session-paused'}),
        _effectStarted(3, _effectA),
        // A known name with a bad or missing field is an unknown event too.
        Event.fromJson({
          'time': 'not a time',
          'event': 'session-finished',
          'outputId': null,
        }),
        Event.fromJson({
          'time': formatTime(_at(5)),
          'event': 'effect-finished',
          'effectId': _effectA,
        }),
        Event.fromJson({'event': 'something-new'}),
      ]);

      expect(state.status, SessionStatus.running);
      expect(state.finishedAt, isNull);
      expect(state.effects.single.status, EffectStatus.running);
      expect(state.effects.single.starts, 1);
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
