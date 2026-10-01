import 'dart:convert';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:test/test.dart';

const String _runId = '0c6e1f7a-93d4-4b58-8e21-5a7d3c9b4f06';
const String _stepId = '2e9b7a40-d1c8-4f35-9a6e-8b3c5d7f1e92';
const String _outputId = '5f2d8b6a-1c93-4e07-a4b8-9e3c7a1d5b20';

final DateTime _time = DateTime.utc(2026, 9, 20, 14, 3, 11, 470);
const String _timeText = '2026-09-20T14:03:11.470Z';

Map<String, Object?> _decode(String text) =>
    jsonDecode(text) as Map<String, Object?>;

/// What a consumer of events can do without a default branch: the compiler
/// checks that every kind of event is covered.
String _kind(Event event) => switch (event) {
  RunStarted() => 'run-started',
  StepStarted() => 'step-started',
  StepFinished() => 'step-finished',
  RunSplit() => 'run-split',
  RunFinished() => 'run-finished',
  RunFailed() => 'run-failed',
  UnknownEvent() => 'unknown',
};

/// What a consumer that only needs the run an event belongs to can do without
/// a six-way switch: a known event has its `runId`, an unknown one may not.
String? _runIdOf(Event event) => switch (event) {
  KnownEvent(:final runId) => runId,
  UnknownEvent(:final runId) => runId,
};

/// Likewise for the time: only a known event is sure to have one.
DateTime? _timeOf(Event event) => switch (event) {
  KnownEvent(:final time) => time,
  UnknownEvent() => null,
};

void main() {
  /// Every event with the exact text it must be written as.
  final cases = <(Event, String)>[
    (
      RunStarted(runId: _runId, time: _time, node: 'collect'),
      '{"runId":"$_runId","time":"$_timeText","event":"run-started",'
          '"node":"collect"}',
    ),
    (
      StepStarted(runId: _runId, time: _time, stepId: _stepId, node: 'collect'),
      '{"runId":"$_runId","time":"$_timeText","event":"step-started",'
          '"stepId":"$_stepId","node":"collect"}',
    ),
    (
      StepFinished(
        runId: _runId,
        time: _time,
        stepId: _stepId,
        exitCode: 0,
        outputId: _outputId,
      ),
      '{"runId":"$_runId","time":"$_timeText","event":"step-finished",'
          '"stepId":"$_stepId","exitCode":0,"outputId":"$_outputId"}',
    ),
    (
      StepFinished(
        runId: _runId,
        time: _time,
        stepId: _stepId,
        exitCode: 2,
        outputId: null,
      ),
      '{"runId":"$_runId","time":"$_timeText","event":"step-finished",'
          '"stepId":"$_stepId","exitCode":2,"outputId":null}',
    ),
    (
      RunSplit(runId: _runId, time: _time),
      '{"runId":"$_runId","time":"$_timeText","event":"run-split"}',
    ),
    (
      RunFinished(runId: _runId, time: _time),
      '{"runId":"$_runId","time":"$_timeText","event":"run-finished"}',
    ),
    (
      RunFailed(
        runId: _runId,
        time: _time,
        stepId: _stepId,
        error: 'exited with code 2',
      ),
      '{"runId":"$_runId","time":"$_timeText","event":"run-failed",'
          '"stepId":"$_stepId","error":"exited with code 2"}',
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
        [for (final (event, _) in cases) event.name],
        [
          'run-started',
          'step-started',
          'step-finished',
          'step-finished',
          'run-split',
          'run-finished',
          'run-failed',
        ],
      );
    });

    test('expose their fields', () {
      final started = Event.fromJson(_decode(cases[0].$2)) as RunStarted;
      expect(started.runId, _runId);
      expect(started.node, 'collect');
      final finished = Event.fromJson(_decode(cases[2].$2)) as StepFinished;
      expect(finished.stepId, _stepId);
      expect(finished.exitCode, 0);
      expect(finished.outputId, _outputId);
      final failed = Event.fromJson(_decode(cases[6].$2)) as RunFailed;
      expect(failed.stepId, _stepId);
      expect(failed.error, 'exited with code 2');
    });

    test('compare by value and by kind', () {
      expect(
        RunSplit(runId: _runId, time: _time),
        isNot(RunFinished(runId: _runId, time: _time)),
      );
      expect(
        RunFinished(runId: _runId, time: _time),
        isNot(RunFinished(runId: _stepId, time: _time)),
      );
      expect(
        RunFinished(runId: _runId, time: _time),
        isNot(
          RunFinished(
            runId: _runId,
            time: _time.add(const Duration(milliseconds: 1)),
          ),
        ),
      );
      expect(
        StepFinished(
          runId: _runId,
          time: _time,
          stepId: _stepId,
          exitCode: 0,
          outputId: null,
        ),
        isNot(
          StepFinished(
            runId: _runId,
            time: _time,
            stepId: _stepId,
            exitCode: 1,
            outputId: null,
          ),
        ),
      );
      expect(
        StepFinished(
          runId: _runId,
          time: _time,
          stepId: _stepId,
          exitCode: 0,
          outputId: null,
        ),
        isNot(
          StepFinished(
            runId: _runId,
            time: _time,
            stepId: _stepId,
            exitCode: 0,
            outputId: _outputId,
          ),
        ),
      );
    });

    test('have a readable toString', () {
      final text = RunStarted(
        runId: _runId,
        time: _time,
        node: 'collect',
      ).toString();
      expect(text, startsWith('RunStarted('));
      expect(text, contains(_runId));
      expect(text, contains(_timeText));
      expect(text, contains('collect'));
    });
  });

  group('time', () {
    test('is parsed to UTC from the written form', () {
      final event = Event.fromJson(_decode(cases[4].$2)) as RunSplit;
      expect(event.time.isUtc, isTrue);
      expect(event.time, DateTime.utc(2026, 9, 20, 14, 3, 11, 470));
    });

    test('is printed with three fractional digits', () {
      expect(
        RunFinished(
          runId: _runId,
          time: DateTime.utc(2026, 9, 20, 14, 3, 11),
        ).toJson()['time'],
        '2026-09-20T14:03:11.000Z',
      );
    });

    test('is kept in UTC with milliseconds, as it is written', () {
      final local = DateTime.utc(2026, 9, 20, 14, 3, 11, 470, 123).toLocal();
      final event = RunFinished(runId: _runId, time: local);
      expect(event.time.isUtc, isTrue);
      expect(event.time.microsecond, 0);
      expect(event.time, _time);
      expect(event, RunFinished(runId: _runId, time: _time));
      expect(Event.fromJson(event.toJson()), event);
    });
  });

  group('UnknownEvent', () {
    test('is what an unknown event name gives, written back as it was', () {
      final input = _decode(
        '{"runId":"$_runId","time":"$_timeText","event":"run-paused",'
        '"reason":"manual","nested":{"a":[1,2]}}',
      );
      final event = Event.fromJson(input);
      expect(event, isA<UnknownEvent>());
      expect(event.toJson(), input);
      expect(jsonEncode(event.toJson()), jsonEncode(input));
      expect(event.name, 'run-paused');
      expect((event as UnknownEvent).runId, _runId);
      expect(event.json, input);
    });

    test('is what a known name without exitCode gives', () {
      final input = _decode(
        '{"runId":"$_runId","time":"$_timeText","event":"step-finished",'
        '"stepId":"$_stepId","outputId":null}',
      );
      final event = Event.fromJson(input);
      expect(event, isA<UnknownEvent>());
      expect(event.toJson(), input);
      expect(event.name, 'step-finished');
      expect((event as UnknownEvent).runId, _runId);
    });

    test('is what any missing or mistyped field of a known name gives', () {
      final bad = <String>[
        // exitCode of the wrong type
        '{"runId":"$_runId","time":"$_timeText","event":"step-finished",'
            '"stepId":"$_stepId","exitCode":"0","outputId":null}',
        // outputId missing: the key is always present
        '{"runId":"$_runId","time":"$_timeText","event":"step-finished",'
            '"stepId":"$_stepId","exitCode":0}',
        // node of the wrong type
        '{"runId":"$_runId","time":"$_timeText","event":"run-started",'
            '"node":5}',
        // stepId missing
        '{"runId":"$_runId","time":"$_timeText","event":"run-failed",'
            '"error":"boom"}',
        // runId missing
        '{"time":"$_timeText","event":"run-finished"}',
        // runId of the wrong type
        '{"runId":1,"time":"$_timeText","event":"run-split"}',
        // time missing
        '{"runId":"$_runId","event":"run-split"}',
        // time of the wrong type
        '{"runId":"$_runId","time":20260920,"event":"run-split"}',
      ];
      for (final text in bad) {
        final input = _decode(text);
        final event = Event.fromJson(input);
        expect(event, isA<UnknownEvent>(), reason: text);
        expect(event.toJson(), input, reason: text);
      }
    });

    test('is what a time that parseTime rejects gives', () {
      for (final time in [
        '2026-09-20T14:03:11Z', // no milliseconds
        '2026-09-20T14:03:11.470', // no zone
        '2026-09-20T14:03:11.470+00:00', // not the Z form
        '2026-02-30T14:03:11.470Z', // no such day
        'yesterday',
        '',
      ]) {
        final input = _decode(
          '{"runId":"$_runId","time":"$time","event":"run-finished"}',
        );
        final event = Event.fromJson(input);
        expect(event, isA<UnknownEvent>(), reason: time);
        expect(event.toJson(), input, reason: time);
      }
    });

    test('is what a missing or non-string event gives', () {
      final missing = _decode('{"runId":"$_runId","time":"$_timeText"}');
      expect(Event.fromJson(missing), isA<UnknownEvent>());
      expect(Event.fromJson(missing).toJson(), missing);
      expect(Event.fromJson(missing).name, '');
      final number = _decode('{"runId":"$_runId","event":7}');
      expect(Event.fromJson(number), isA<UnknownEvent>());
      expect(Event.fromJson(number).toJson(), number);
      expect(Event.fromJson(number).name, '');
      expect(Event.fromJson(<String, Object?>{}), isA<UnknownEvent>());
    });

    test('has no runId when the map has none, or not a string', () {
      expect((Event.fromJson({'event': 'x'}) as UnknownEvent).runId, isNull);
      expect(
        (Event.fromJson({'event': 'x', 'runId': 4}) as UnknownEvent).runId,
        isNull,
      );
    });

    test('compares the map by value, deeply', () {
      UnknownEvent of(String reason) => Event.fromJson({
        'runId': _runId,
        'event': 'run-paused',
        'detail': {
          'reasons': [reason],
        },
      }) as UnknownEvent;
      expect(of('manual'), of('manual'));
      expect(of('manual').hashCode, of('manual').hashCode);
      expect(of('manual'), isNot(of('timeout')));
      expect(of('manual'), isNot(RunFinished(runId: _runId, time: _time)));
    });

    test('has a readable toString', () {
      final event = Event.fromJson({'runId': _runId, 'event': 'run-paused'});
      expect(event.toString(), startsWith('UnknownEvent('));
      expect(event.toString(), contains('run-paused'));
    });
  });

  group('Event', () {
    test('is exhaustively switchable', () {
      expect(
        [for (final (event, _) in cases) _kind(event)],
        [
          'run-started',
          'step-started',
          'step-finished',
          'step-finished',
          'run-split',
          'run-finished',
          'run-failed',
        ],
      );
      expect(_kind(Event.fromJson({'event': 'future'})), 'unknown');
    });

    test('is exhaustively switchable by KnownEvent and UnknownEvent', () {
      expect([
        for (final (event, _) in cases) _runIdOf(event),
      ], everyElement(_runId));
      expect([
        for (final (event, _) in cases) _timeOf(event),
      ], everyElement(_time));
      expect(_runIdOf(Event.fromJson({'event': 'future'})), isNull);
      expect(_runIdOf(Event.fromJson({'event': 'x', 'runId': _runId})), _runId);
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
