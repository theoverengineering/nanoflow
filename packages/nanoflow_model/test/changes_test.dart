import 'dart:convert';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:test/test.dart';

const String _sessionId = '8d3a9c1e-5b2f-4e7a-a0c4-1f6b2d9e3a57';
const String _runId = '0c6e1f7a-93d4-4b58-8e21-5a7d3c9b4f06';
const String _stepId = '2e9b7a40-d1c8-4f35-9a6e-8b3c5d7f1e92';
const String _outputId = '5f2d8b6a-1c93-4e07-a4b8-9e3c7a1d5b20';

final DateTime _time = DateTime.utc(2026, 9, 20, 14, 3, 11, 470);
const String _timeText = '2026-09-20T14:03:11.470Z';

const String _graphJson =
    '{"start":"collect","nodes":{"collect":{"command":"run.sh"}}}';
const String _sessionJson = '{"id":"$_sessionId","graph":$_graphJson}';
const String _runJson =
    '{"id":"$_runId","sessionId":"$_sessionId","parentId":null}';
const String _stepJson =
    '{"id":"$_stepId","runId":"$_runId","inputId":null,"outputId":null,'
    '"log":"command.log"}';
const String _stepDoneJson =
    '{"id":"$_stepId","runId":"$_runId","inputId":null,'
    '"outputId":"$_outputId","log":"command.log"}';
const String _eventJson =
    '{"runId":"$_runId","time":"$_timeText","event":"run-finished"}';

Map<String, Object?> _decode(String text) =>
    jsonDecode(text) as Map<String, Object?>;

String _problem(void Function() read) {
  try {
    read();
  } on FormatException catch (e) {
    return e.message;
  }
  throw StateError('Expected a FormatException');
}

/// What a consumer of changes can do without a default branch.
String _kind(Change change) => switch (change) {
  SessionAdded() => 'session',
  RunAdded() => 'run',
  StepAdded() => 'step',
  StepChanged() => 'step-changed',
  EventAdded() => 'event',
  DocumentAdded() => 'document',
  LogCorrupted() => 'log',
};

void main() {
  final session = Session(id: _sessionId, graph: _decode(_graphJson));
  final run = Run(id: _runId, sessionId: _sessionId, parentId: null);
  final step = Step(
    id: _stepId,
    runId: _runId,
    inputId: null,
    outputId: null,
    log: 'command.log',
  );

  /// Every change with its name and the exact text it must be written as.
  final cases = <(Change, String, String)>[
    (
      SessionAdded(session),
      'session-added',
      '{"change":"session-added","session":$_sessionJson}',
    ),
    (RunAdded(run), 'run-added', '{"change":"run-added","run":$_runJson}'),
    (
      StepAdded(step),
      'step-added',
      '{"change":"step-added","step":$_stepJson}',
    ),
    (
      StepChanged(step.withOutput(_outputId)),
      'step-changed',
      '{"change":"step-changed","step":$_stepDoneJson}',
    ),
    (
      EventAdded(RunFinished(runId: _runId, time: _time)),
      'event-added',
      '{"change":"event-added","event":$_eventJson}',
    ),
    (
      DocumentAdded(sessionId: _sessionId, documentId: _outputId),
      'document-added',
      '{"change":"document-added","sessionId":"$_sessionId",'
          '"documentId":"$_outputId"}',
    ),
    (
      LogCorrupted(runId: _runId, line: 3, text: '{"runId":"half'),
      'log-corrupted',
      '{"change":"log-corrupted","runId":"$_runId","line":3,'
          r'"text":"{\"runId\":\"half"}',
    ),
  ];

  group('changes', () {
    for (final (change, name, text) in cases) {
      test('$name is written with change first, then its own fields', () {
        expect(change.name, name);
        expect(jsonEncode(change.toJson()), text);
      });

      test('$name round trips', () {
        final read = Change.fromJson(_decode(text));
        expect(read.runtimeType, change.runtimeType);
        expect(read, change);
        expect(read.hashCode, change.hashCode);
        expect(jsonEncode(read.toJson()), text);
      });

      test('$name has a readable toString', () {
        expect(change.toString(), startsWith('${change.runtimeType}('));
      });
    }

    test('expose their fields', () {
      final added = Change.fromJson(_decode(cases[0].$3)) as SessionAdded;
      expect(added.session, session);
      final document = Change.fromJson(_decode(cases[5].$3)) as DocumentAdded;
      expect(document.sessionId, _sessionId);
      expect(document.documentId, _outputId);
      final corrupted = Change.fromJson(_decode(cases[6].$3)) as LogCorrupted;
      expect(corrupted.runId, _runId);
      expect(corrupted.line, 3);
      expect(corrupted.text, '{"runId":"half');
    });

    test('are exhaustively switchable', () {
      expect(
        [for (final (change, _, _) in cases) _kind(change)],
        ['session', 'run', 'step', 'step-changed', 'event', 'document', 'log'],
      );
    });

    test('compare by value and by kind', () {
      expect(StepAdded(step), isNot(StepChanged(step)));
      expect(StepAdded(step), isNot(StepAdded(step.withOutput(_outputId))));
      expect(RunAdded(run), isNot(StepAdded(step)));
      expect(
        DocumentAdded(sessionId: _sessionId, documentId: _outputId),
        isNot(DocumentAdded(sessionId: _sessionId, documentId: _runId)),
      );
      expect(
        DocumentAdded(sessionId: _sessionId, documentId: _outputId),
        isNot(DocumentAdded(sessionId: _runId, documentId: _outputId)),
      );
      expect(
        LogCorrupted(runId: _runId, line: 1, text: 'x'),
        isNot(LogCorrupted(runId: _runId, line: 2, text: 'x')),
      );
      expect(
        LogCorrupted(runId: _runId, line: 1, text: 'x'),
        isNot(LogCorrupted(runId: _runId, line: 1, text: 'y')),
      );
      expect(
        LogCorrupted(runId: _runId, line: 1, text: 'x'),
        isNot(LogCorrupted(runId: _stepId, line: 1, text: 'x')),
      );
      expect(
        EventAdded(RunFinished(runId: _runId, time: _time)),
        isNot(EventAdded(RunSplit(runId: _runId, time: _time))),
      );
      expect(
        SessionAdded(session),
        isNot(SessionAdded(Session(id: _runId, graph: _decode(_graphJson)))),
      );
    });
  });

  group('event-added', () {
    test('carries an event it does not know as it was written', () {
      const text =
          '{"runId":"$_runId","time":"$_timeText","event":"run-paused",'
          '"reason":"manual"}';
      final change = EventAdded(Event.fromJson(_decode(text)));
      final json = change.toJson();
      expect(jsonEncode(json), '{"change":"event-added","event":$text}');
      final read = Change.fromJson(json);
      expect(read, change);
      expect((read as EventAdded).event, isA<UnknownEvent>());
      expect(read.event.toJson(), _decode(text));
    });

    test('carries a known event with a missing field as an UnknownEvent', () {
      final read = Change.fromJson({
        'change': 'event-added',
        'event': {'runId': _runId, 'time': _timeText, 'event': 'run-failed'},
      });
      expect((read as EventAdded).event, isA<UnknownEvent>());
    });
  });

  group('fromJson', () {
    test('throws on a missing, mistyped or unknown change', () {
      expect(_problem(() => Change.fromJson({})), 'change: missing');
      expect(
        _problem(() => Change.fromJson({'change': 1})),
        'change: expected a string',
      );
      expect(
        _problem(() => Change.fromJson({'change': 'run-removed'})),
        'change: unknown "run-removed"',
      );
    });

    test('throws on missing or mistyped own fields, naming the field', () {
      expect(
        _problem(() => Change.fromJson({'change': 'session-added'})),
        'session: missing',
      );
      expect(
        _problem(() => Change.fromJson({'change': 'run-added', 'run': 'x'})),
        'run: expected an object',
      );
      expect(
        _problem(
          () =>
              Change.fromJson({'change': 'event-added', 'event': <Object?>[]}),
        ),
        'event: expected an object',
      );
      expect(
        _problem(
          () => Change.fromJson({
            'change': 'document-added',
            'sessionId': _sessionId,
          }),
        ),
        'documentId: missing',
      );
      expect(
        _problem(
          () => Change.fromJson({
            'change': 'log-corrupted',
            'runId': _runId,
            'line': '3',
            'text': 'x',
          }),
        ),
        'line: expected an integer',
      );
      expect(
        _problem(
          () => Change.fromJson({
            'change': 'log-corrupted',
            'runId': _runId,
            'line': 3,
            'text': null,
          }),
        ),
        'text: expected a string',
      );
    });

    test('puts the place of a problem inside a model under its field', () {
      expect(
        _problem(
          () => Change.fromJson({
            'change': 'session-added',
            'session': {'graph': <String, Object?>{}},
          }),
        ),
        'session.id: missing',
      );
      expect(
        _problem(
          () => Change.fromJson({
            'change': 'step-changed',
            'step': {
              'id': _stepId,
              'runId': _runId,
              'inputId': null,
              'outputId': null,
            },
          }),
        ),
        'step.log: missing',
      );
    });
  });
}
