import 'dart:convert';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:test/test.dart';

const String _sessionId = '8d3a9c1e-5b2f-4e7a-a0c4-1f6b2d9e3a57';
const String _otherId = '0c6e1f7a-93d4-4b58-8e21-5a7d3c9b4f06';
const String _stepId = '2e9b7a40-d1c8-4f35-9a6e-8b3c5d7f1e92';
const String _outputId = '5f2d8b6a-1c93-4e07-a4b8-9e3c7a1d5b20';

final DateTime _time = DateTime.utc(2026, 10, 3, 10, 0, 0, 482);
const String _timeText = '2026-10-03T10:00:00.482Z';

const String _key = 'collect#1@e3b0c44298fc1c14';

const String _sessionJson =
    '{"id":"$_sessionId","workflow":"review","graph":null,"inputId":null}';
const String _stepJson =
    '{"id":"$_stepId","sessionId":"$_sessionId","name":"collect",'
    '"key":"$_key","after":null,"place":"lib/review.dart:12",'
    '"outputId":null,"log":"step.log"}';
const String _stepDoneJson =
    '{"id":"$_stepId","sessionId":"$_sessionId","name":"collect",'
    '"key":"$_key","after":null,"place":"lib/review.dart:12",'
    '"outputId":"$_outputId","log":"step.log"}';
const String _eventJson =
    '{"time":"$_timeText","event":"session-finished","outputId":null}';

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
  StepAdded() => 'step',
  StepChanged() => 'step-changed',
  EventAdded() => 'event',
  DocumentAdded() => 'document',
  LogCorrupted() => 'log',
};

void main() {
  final session = Session(
    id: _sessionId,
    workflow: 'review',
    graph: null,
    inputId: null,
  );
  final step = Step(
    id: _stepId,
    sessionId: _sessionId,
    name: 'collect',
    key: _key,
    after: null,
    place: 'lib/review.dart:12',
    outputId: null,
    log: 'step.log',
  );

  /// Every change with its name and the exact text it must be written as.
  final cases = <(Change, String, String)>[
    (
      SessionAdded(session),
      'session-added',
      '{"change":"session-added","session":$_sessionJson}',
    ),
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
      EventAdded(
        sessionId: _sessionId,
        event: SessionFinished(time: _time, outputId: null),
      ),
      'event-added',
      '{"change":"event-added","sessionId":"$_sessionId","event":$_eventJson}',
    ),
    (
      DocumentAdded(sessionId: _sessionId, documentId: _outputId),
      'document-added',
      '{"change":"document-added","sessionId":"$_sessionId",'
          '"documentId":"$_outputId"}',
    ),
    (
      LogCorrupted(sessionId: _sessionId, line: 3, text: '{"time":"half'),
      'log-corrupted',
      '{"change":"log-corrupted","sessionId":"$_sessionId","line":3,'
          r'"text":"{\"time\":\"half"}',
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
      final event = Change.fromJson(_decode(cases[3].$3)) as EventAdded;
      expect(event.sessionId, _sessionId);
      expect(event.event, SessionFinished(time: _time, outputId: null));
      final document = Change.fromJson(_decode(cases[4].$3)) as DocumentAdded;
      expect(document.sessionId, _sessionId);
      expect(document.documentId, _outputId);
      final corrupted = Change.fromJson(_decode(cases[5].$3)) as LogCorrupted;
      expect(corrupted.sessionId, _sessionId);
      expect(corrupted.line, 3);
      expect(corrupted.text, '{"time":"half');
    });

    test('are exhaustively switchable', () {
      expect(
        [for (final (change, _, _) in cases) _kind(change)],
        ['session', 'step', 'step-changed', 'event', 'document', 'log'],
      );
    });

    test('compare by value and by kind', () {
      final finished = SessionFinished(time: _time, outputId: null);
      expect(StepAdded(step), isNot(StepChanged(step)));
      expect(StepAdded(step), isNot(StepAdded(step.withOutput(_outputId))));
      expect(
        DocumentAdded(sessionId: _sessionId, documentId: _outputId),
        isNot(DocumentAdded(sessionId: _sessionId, documentId: _otherId)),
      );
      expect(
        DocumentAdded(sessionId: _sessionId, documentId: _outputId),
        isNot(DocumentAdded(sessionId: _otherId, documentId: _outputId)),
      );
      expect(
        LogCorrupted(sessionId: _sessionId, line: 1, text: 'x'),
        isNot(LogCorrupted(sessionId: _sessionId, line: 2, text: 'x')),
      );
      expect(
        LogCorrupted(sessionId: _sessionId, line: 1, text: 'x'),
        isNot(LogCorrupted(sessionId: _sessionId, line: 1, text: 'y')),
      );
      expect(
        LogCorrupted(sessionId: _sessionId, line: 1, text: 'x'),
        isNot(LogCorrupted(sessionId: _otherId, line: 1, text: 'x')),
      );
      expect(
        EventAdded(sessionId: _sessionId, event: finished),
        isNot(
          EventAdded(
            sessionId: _sessionId,
            event: SessionStarted(time: _time, code: null),
          ),
        ),
      );
      expect(
        EventAdded(sessionId: _sessionId, event: finished),
        isNot(EventAdded(sessionId: _otherId, event: finished)),
      );
      expect(
        SessionAdded(session),
        isNot(
          SessionAdded(
            Session(
              id: _otherId,
              workflow: 'review',
              graph: null,
              inputId: null,
            ),
          ),
        ),
      );
    });
  });

  group('event-added', () {
    test('carries an event it does not know as it was written', () {
      const text =
          '{"time":"$_timeText","event":"session-paused","reason":"manual"}';
      final change = EventAdded(
        sessionId: _sessionId,
        event: Event.fromJson(_decode(text)),
      );
      final json = change.toJson();
      expect(
        jsonEncode(json),
        '{"change":"event-added","sessionId":"$_sessionId","event":$text}',
      );
      final read = Change.fromJson(json);
      expect(read, change);
      expect((read as EventAdded).event, isA<UnknownEvent>());
      expect(read.event.toJson(), _decode(text));
    });

    test('carries a known event with a missing field as an UnknownEvent', () {
      final read = Change.fromJson({
        'change': 'event-added',
        'sessionId': _sessionId,
        'event': {'time': _timeText, 'event': 'session-failed'},
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
        _problem(() => Change.fromJson({'change': 'run-added'})),
        'change: unknown "run-added"',
      );
    });

    test('throws on missing or mistyped own fields, naming the field', () {
      expect(
        _problem(() => Change.fromJson({'change': 'session-added'})),
        'session: missing',
      );
      expect(
        _problem(() => Change.fromJson({'change': 'step-added', 'step': 'x'})),
        'step: expected an object',
      );
      expect(
        _problem(
          () => Change.fromJson({
            'change': 'event-added',
            'event': _decode(_eventJson),
          }),
        ),
        'sessionId: missing',
      );
      expect(
        _problem(
          () => Change.fromJson({
            'change': 'event-added',
            'sessionId': _sessionId,
            'event': <Object?>[],
          }),
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
            'line': 3,
            'text': 'x',
          }),
        ),
        'sessionId: missing',
      );
      expect(
        _problem(
          () => Change.fromJson({
            'change': 'log-corrupted',
            'sessionId': _sessionId,
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
            'sessionId': _sessionId,
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
            'session': {'workflow': 'review', 'graph': null, 'inputId': null},
          }),
        ),
        'session.id: missing',
      );
      expect(
        _problem(
          () => Change.fromJson({
            'change': 'step-changed',
            'step': {...step.toJson()}..remove('log'),
          }),
        ),
        'step.log: missing',
      );
    });
  });
}
