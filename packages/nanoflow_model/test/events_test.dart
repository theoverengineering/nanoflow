import 'dart:convert';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:test/test.dart';

const String _stepId = '2e9b7a40-d1c8-4f35-9a6e-8b3c5d7f1e92';
const String _outputId = '5f2d8b6a-1c93-4e07-a4b8-9e3c7a1d5b20';
const String _graphId = '9a4d6c20-7e15-4b83-a0f9-3c2b8d5e7f41';
const String _code = 'sha256:7d3e9f0c';

final DateTime _time = DateTime.utc(2026, 10, 3, 10, 0, 0, 482);
const String _timeText = '2026-10-03T10:00:00.482Z';

const String _stack = '#0      main (file:///app/bin/main.dart:5:3)\n';

Map<String, Object?> _decode(String text) =>
    jsonDecode(text) as Map<String, Object?>;

/// What a consumer of events can do without a default branch: the compiler
/// checks that every kind of event is covered.
String _kind(Event event) => switch (event) {
  SessionStarted() => 'session-started',
  SessionResumed() => 'session-resumed',
  StepStarted() => 'step-started',
  StepFinished() => 'step-finished',
  StepFailed() => 'step-failed',
  SessionFinished() => 'session-finished',
  SessionFailed() => 'session-failed',
  UnknownEvent() => 'unknown',
};

/// What a consumer that only needs the time of an event can do without a
/// seven-way switch: only a known event is sure to have one.
DateTime? _timeOf(Event event) => switch (event) {
  KnownEvent(:final time) => time,
  UnknownEvent() => null,
};

void main() {
  /// Every event with the exact text it must be written as.
  final cases = <(Event, String)>[
    (
      SessionStarted(time: _time, code: _code),
      '{"time":"$_timeText","event":"session-started","code":"$_code"}',
    ),
    (
      SessionStarted(time: _time, code: null),
      '{"time":"$_timeText","event":"session-started","code":null}',
    ),
    (
      SessionResumed(time: _time, code: _code, graphId: _graphId),
      '{"time":"$_timeText","event":"session-resumed","code":"$_code",'
          '"graphId":"$_graphId"}',
    ),
    (
      SessionResumed(time: _time, code: null, graphId: null),
      '{"time":"$_timeText","event":"session-resumed","code":null,'
          '"graphId":null}',
    ),
    (
      StepStarted(time: _time, stepId: _stepId),
      '{"time":"$_timeText","event":"step-started","stepId":"$_stepId"}',
    ),
    (
      StepFinished(time: _time, stepId: _stepId, outputId: _outputId),
      '{"time":"$_timeText","event":"step-finished","stepId":"$_stepId",'
          '"outputId":"$_outputId"}',
    ),
    (
      StepFinished(time: _time, stepId: _stepId, outputId: null),
      '{"time":"$_timeText","event":"step-finished","stepId":"$_stepId",'
          '"outputId":null}',
    ),
    (
      StepFailed(
        time: _time,
        stepId: _stepId,
        error: 'Exception: boom',
        stack: _stack,
      ),
      '{"time":"$_timeText","event":"step-failed","stepId":"$_stepId",'
          '"error":"Exception: boom","stack":${jsonEncode(_stack)}}',
    ),
    (
      SessionFinished(time: _time, outputId: _outputId),
      '{"time":"$_timeText","event":"session-finished",'
          '"outputId":"$_outputId"}',
    ),
    (
      SessionFinished(time: _time, outputId: null),
      '{"time":"$_timeText","event":"session-finished","outputId":null}',
    ),
    (
      SessionFailed(time: _time, error: 'StateError: no', stack: _stack),
      '{"time":"$_timeText","event":"session-failed",'
          '"error":"StateError: no","stack":${jsonEncode(_stack)}}',
    ),
  ];

  group('known events', () {
    for (final (event, text) in cases) {
      test('${event.name} is written with keys in the documented order', () {
        expect(jsonEncode(event.toJson()), text);
      });

      test('${event.name} round trips and is not an UnknownEvent', () {
        final read = Event.fromJson(_decode(text));
        expect(read, isNot(isA<UnknownEvent>()));
        expect(read.runtimeType, event.runtimeType);
        expect(read, event);
        expect(read.hashCode, event.hashCode);
        expect(jsonEncode(read.toJson()), text);
      });
    }

    test('names are the values of the event field', () {
      expect(
        {for (final (event, _) in cases) event.name},
        {
          'session-started',
          'session-resumed',
          'step-started',
          'step-finished',
          'step-failed',
          'session-finished',
          'session-failed',
        },
      );
    });

    test('expose their fields', () {
      final resumed = Event.fromJson(_decode(cases[2].$2)) as SessionResumed;
      expect(resumed.code, _code);
      expect(resumed.graphId, _graphId);
      final finished = Event.fromJson(_decode(cases[5].$2)) as StepFinished;
      expect(finished.stepId, _stepId);
      expect(finished.outputId, _outputId);
      final failed = Event.fromJson(_decode(cases[7].$2)) as StepFailed;
      expect(failed.stepId, _stepId);
      expect(failed.error, 'Exception: boom');
      expect(failed.stack, _stack);
      final ended = Event.fromJson(_decode(cases[10].$2)) as SessionFailed;
      expect(ended.error, 'StateError: no');
      expect(ended.stack, _stack);
    });

    test('compare by value and by kind', () {
      expect(
        SessionFinished(time: _time, outputId: null),
        isNot(SessionStarted(time: _time, code: null)),
      );
      expect(
        SessionStarted(time: _time, code: _code),
        isNot(SessionStarted(time: _time, code: null)),
      );
      expect(
        SessionStarted(time: _time, code: _code),
        isNot(
          SessionStarted(
            time: _time.add(const Duration(milliseconds: 1)),
            code: _code,
          ),
        ),
      );
      expect(
        StepFinished(time: _time, stepId: _stepId, outputId: null),
        isNot(StepFinished(time: _time, stepId: _stepId, outputId: _outputId)),
      );
      expect(
        StepFailed(time: _time, stepId: _stepId, error: 'a', stack: ''),
        isNot(StepFailed(time: _time, stepId: _stepId, error: 'a', stack: 's')),
      );
    });

    test('have a readable toString', () {
      final text = StepFinished(
        time: _time,
        stepId: _stepId,
        outputId: _outputId,
      ).toString();
      expect(text, startsWith('StepFinished('));
      expect(text, contains(_stepId));
      expect(text, contains(_timeText));
      expect(text, contains(_outputId));
    });
  });

  group('time', () {
    test('is parsed to UTC from the written form', () {
      final event = Event.fromJson(_decode(cases[4].$2)) as StepStarted;
      expect(event.time.isUtc, isTrue);
      expect(event.time, DateTime.utc(2026, 10, 3, 10, 0, 0, 482));
    });

    test('is printed with three fractional digits', () {
      expect(
        SessionFinished(
          time: DateTime.utc(2026, 10, 3, 10),
          outputId: null,
        ).toJson()['time'],
        '2026-10-03T10:00:00.000Z',
      );
    });

    test('is kept in UTC with milliseconds, as it is written', () {
      final local = DateTime.utc(2026, 10, 3, 10, 0, 0, 482, 123).toLocal();
      final event = StepStarted(time: local, stepId: _stepId);
      expect(event.time.isUtc, isTrue);
      expect(event.time.microsecond, 0);
      expect(event.time, _time);
      expect(event, StepStarted(time: _time, stepId: _stepId));
      expect(Event.fromJson(event.toJson()), event);
    });
  });

  group('UnknownEvent', () {
    test('is what an unknown event name gives, written back as it was', () {
      final input = _decode(
        '{"time":"$_timeText","event":"session-paused",'
        '"reason":"manual","nested":{"a":[1,2]}}',
      );
      final event = Event.fromJson(input);
      expect(event, isA<UnknownEvent>());
      expect(event.toJson(), input);
      expect(jsonEncode(event.toJson()), jsonEncode(input));
      expect(event.name, 'session-paused');
      expect((event as UnknownEvent).json, input);
    });

    test('is what any missing or mistyped field of a known name gives', () {
      final bad = <String>[
        // code missing: the key is always present
        '{"time":"$_timeText","event":"session-started"}',
        // code of the wrong type
        '{"time":"$_timeText","event":"session-started","code":1}',
        // graphId missing
        '{"time":"$_timeText","event":"session-resumed","code":null}',
        // graphId of the wrong type
        '{"time":"$_timeText","event":"session-resumed","code":null,'
            '"graphId":[]}',
        // stepId missing
        '{"time":"$_timeText","event":"step-started"}',
        // stepId null
        '{"time":"$_timeText","event":"step-started","stepId":null}',
        // outputId missing
        '{"time":"$_timeText","event":"step-finished","stepId":"$_stepId"}',
        // outputId of the wrong type
        '{"time":"$_timeText","event":"step-finished","stepId":"$_stepId",'
            '"outputId":3}',
        // stack missing
        '{"time":"$_timeText","event":"step-failed","stepId":"$_stepId",'
            '"error":"boom"}',
        // error null
        '{"time":"$_timeText","event":"step-failed","stepId":"$_stepId",'
            '"error":null,"stack":""}',
        // outputId missing
        '{"time":"$_timeText","event":"session-finished"}',
        // stack of the wrong type
        '{"time":"$_timeText","event":"session-failed","error":"boom",'
            '"stack":["#0"]}',
        // time missing
        '{"event":"session-finished","outputId":null}',
        // time of the wrong type
        '{"time":20261003,"event":"session-finished","outputId":null}',
      ];
      for (final text in bad) {
        final input = _decode(text);
        final event = Event.fromJson(input);
        expect(event, isA<UnknownEvent>(), reason: text);
        expect(event.toJson(), input, reason: text);
        expect(jsonEncode(event.toJson()), text, reason: text);
      }
    });

    test('is what a time that parseTime rejects gives', () {
      for (final time in [
        '2026-10-03T10:00:00Z', // no milliseconds
        '2026-10-03T10:00:00.482', // no zone
        '2026-10-03T10:00:00.482+00:00', // not the Z form
        '2026-02-30T10:00:00.482Z', // no such day
        'yesterday',
        '',
      ]) {
        final input = _decode(
          '{"time":"$time","event":"session-finished","outputId":null}',
        );
        final event = Event.fromJson(input);
        expect(event, isA<UnknownEvent>(), reason: time);
        expect(event.toJson(), input, reason: time);
      }
    });

    test('is what a missing or non-string event gives', () {
      final missing = _decode('{"time":"$_timeText"}');
      expect(Event.fromJson(missing), isA<UnknownEvent>());
      expect(Event.fromJson(missing).toJson(), missing);
      expect(Event.fromJson(missing).name, '');
      final number = _decode('{"time":"$_timeText","event":7}');
      expect(Event.fromJson(number), isA<UnknownEvent>());
      expect(Event.fromJson(number).toJson(), number);
      expect(Event.fromJson(number).name, '');
      expect(Event.fromJson(<String, Object?>{}), isA<UnknownEvent>());
    });

    test('is what an event of the old run journals gives', () {
      final input = _decode(
        '{"runId":"$_stepId","time":"$_timeText","event":"run-finished"}',
      );
      expect(Event.fromJson(input), isA<UnknownEvent>());
    });

    test('compares the map by value, deeply', () {
      UnknownEvent of(String reason) => Event.fromJson({
        'event': 'session-paused',
        'detail': {
          'reasons': [reason],
        },
      }) as UnknownEvent;
      expect(of('manual'), of('manual'));
      expect(of('manual').hashCode, of('manual').hashCode);
      expect(of('manual'), isNot(of('timeout')));
      expect(of('manual'), isNot(SessionFinished(time: _time, outputId: null)));
    });

    test('has a readable toString', () {
      final event = Event.fromJson({'event': 'session-paused'});
      expect(event.toString(), startsWith('UnknownEvent('));
      expect(event.toString(), contains('session-paused'));
    });
  });

  group('Event', () {
    test('is exhaustively switchable', () {
      expect(
        [for (final (event, _) in cases) _kind(event)],
        [for (final (event, _) in cases) event.name],
      );
      expect(_kind(Event.fromJson({'event': 'future'})), 'unknown');
    });

    test('is exhaustively switchable by KnownEvent and UnknownEvent', () {
      expect([
        for (final (event, _) in cases) _timeOf(event),
      ], everyElement(_time));
      expect(_timeOf(Event.fromJson({'event': 'future'})), isNull);
    });

    test('every known event is a KnownEvent and an unknown one is not', () {
      for (final (event, _) in cases) {
        expect(event, isA<KnownEvent>(), reason: event.name);
      }
      expect(Event.fromJson({'event': 'future'}), isNot(isA<KnownEvent>()));
    });
  });
}
