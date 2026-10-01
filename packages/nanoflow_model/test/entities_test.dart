import 'dart:convert';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:test/test.dart';

const String _sessionId = '8d3a9c1e-5b2f-4e7a-a0c4-1f6b2d9e3a57';
const String _runId = '0c6e1f7a-93d4-4b58-8e21-5a7d3c9b4f06';
const String _childId = 'b41f8d2c-6e05-4a9b-b3c7-7d2e9f1a5c84';
const String _stepId = '2e9b7a40-d1c8-4f35-9a6e-8b3c5d7f1e92';
const String _inputId = 'a7c5e3b1-4d92-4860-8f1a-6c9e2b7d3f58';
const String _outputId = '5f2d8b6a-1c93-4e07-a4b8-9e3c7a1d5b20';

const String _graphJson =
    '{"start":"collect","nodes":{"collect":{"command":"run.sh","then":[]}}}';

Map<String, Object?> _decode(String text) =>
    jsonDecode(text) as Map<String, Object?>;

/// The message of the [FormatException] thrown by [read].
String _problem(void Function() read) {
  try {
    read();
  } on FormatException catch (e) {
    return e.message;
  }
  throw StateError('Expected a FormatException');
}

void main() {
  group('Session', () {
    final session = Session(id: _sessionId, graph: _decode(_graphJson));
    final text = '{"id":"$_sessionId","graph":$_graphJson}';

    test('writes id then graph', () {
      expect(jsonEncode(session.toJson()), text);
    });

    test('round trips through JSON', () {
      expect(Session.fromJson(_decode(text)), session);
      expect(Session.fromJson(_decode(text)).toJson(), session.toJson());
    });

    test('compares the graph by value, deeply', () {
      final other = Session(id: _sessionId, graph: _decode(_graphJson));
      expect(other, session);
      expect(other.hashCode, session.hashCode);
      final changed = _decode(_graphJson);
      ((changed['nodes'] as Map<String, Object?>)['collect']
              as Map<String, Object?>)['command'] =
          'other.sh';
      expect(Session(id: _sessionId, graph: changed), isNot(session));
      expect(Session(id: _runId, graph: _decode(_graphJson)), isNot(session));
    });

    test('has a readable toString', () {
      expect(session.toString(), startsWith('Session('));
      expect(session.toString(), contains(_sessionId));
    });

    test('throws on missing or mistyped fields, naming the field', () {
      expect(
        _problem(() => Session.fromJson(_decode('{"graph":$_graphJson}'))),
        'id: missing',
      );
      expect(
        _problem(
          () => Session.fromJson(_decode('{"id":1,"graph":$_graphJson}')),
        ),
        'id: expected a string',
      );
      expect(
        _problem(() => Session.fromJson(_decode('{"id":"$_sessionId"}'))),
        'graph: missing',
      );
      expect(
        _problem(
          () => Session.fromJson(_decode('{"id":"$_sessionId","graph":[]}')),
        ),
        'graph: expected an object',
      );
      expect(
        _problem(
          () => Session.fromJson({
            'id': _sessionId,
            'graph': {1: 'not a string key'},
          }),
        ),
        'graph: expected an object',
      );
    });

    test('takes a graph written as a bare map literal', () {
      // What an empty map literal inside another map literal is.
      final read = Session.fromJson({
        'id': _sessionId,
        'graph': {'start': 'a', 'nodes': <dynamic, dynamic>{}},
      });
      expect(read.graph, {'start': 'a', 'nodes': <String, Object?>{}});
    });
  });

  group('Run', () {
    final root = Run(id: _runId, sessionId: _sessionId, parentId: null);
    final child = Run(id: _childId, sessionId: _sessionId, parentId: _runId);

    test('writes id, sessionId, parentId and keeps a null parentId', () {
      expect(
        jsonEncode(root.toJson()),
        '{"id":"$_runId","sessionId":"$_sessionId","parentId":null}',
      );
      expect(
        jsonEncode(child.toJson()),
        '{"id":"$_childId","sessionId":"$_sessionId","parentId":"$_runId"}',
      );
    });

    test('round trips through JSON', () {
      for (final run in [root, child]) {
        expect(Run.fromJson(_decode(jsonEncode(run.toJson()))), run);
      }
    });

    test('compares by value', () {
      expect(Run(id: _runId, sessionId: _sessionId, parentId: null), root);
      expect(
        Run(id: _runId, sessionId: _sessionId, parentId: null).hashCode,
        root.hashCode,
      );
      expect(root, isNot(child));
      expect(
        Run(id: _runId, sessionId: _sessionId, parentId: _childId),
        isNot(root),
      );
    });

    test('has a readable toString', () {
      expect(child.toString(), startsWith('Run('));
      expect(child.toString(), contains(_runId));
    });

    test('throws on missing or mistyped fields, naming the field', () {
      expect(
        _problem(
          () => Run.fromJson(_decode('{"id":"$_runId","sessionId":"s"}')),
        ),
        'parentId: missing',
      );
      expect(
        _problem(
          () => Run.fromJson(
            _decode('{"id":"$_runId","sessionId":"s","parentId":3}'),
          ),
        ),
        'parentId: expected a string or null',
      );
      expect(
        _problem(
          () => Run.fromJson(_decode('{"id":"$_runId","parentId":null}')),
        ),
        'sessionId: missing',
      );
    });
  });

  group('Step', () {
    final fresh = Step(
      id: _stepId,
      runId: _runId,
      inputId: _inputId,
      outputId: null,
      log: 'command.log',
    );

    test('writes id, runId, inputId, outputId, log and keeps nulls', () {
      expect(
        jsonEncode(fresh.toJson()),
        '{"id":"$_stepId","runId":"$_runId","inputId":"$_inputId",'
        '"outputId":null,"log":"command.log"}',
      );
      expect(
        jsonEncode(
          Step(
            id: _stepId,
            runId: _runId,
            inputId: null,
            outputId: null,
            log: null,
          ).toJson(),
        ),
        '{"id":"$_stepId","runId":"$_runId","inputId":null,'
        '"outputId":null,"log":null}',
      );
    });

    test('round trips through JSON', () {
      final done = fresh.withOutput(_outputId);
      for (final step in [fresh, done]) {
        expect(Step.fromJson(_decode(jsonEncode(step.toJson()))), step);
      }
    });

    test('withOutput changes only the outputId', () {
      final done = fresh.withOutput(_outputId);
      expect(done.outputId, _outputId);
      expect(
        done,
        Step(
          id: _stepId,
          runId: _runId,
          inputId: _inputId,
          outputId: _outputId,
          log: 'command.log',
        ),
      );
      expect(fresh.outputId, isNull);
    });

    test('compares by value', () {
      final same = Step(
        id: _stepId,
        runId: _runId,
        inputId: _inputId,
        outputId: null,
        log: 'command.log',
      );
      expect(same, fresh);
      expect(same.hashCode, fresh.hashCode);
      expect(fresh.withOutput(_outputId), isNot(fresh));
      expect(
        Step(
          id: _stepId,
          runId: _runId,
          inputId: null,
          outputId: null,
          log: 'command.log',
        ),
        isNot(fresh),
      );
      expect(
        Step(
          id: _stepId,
          runId: _runId,
          inputId: _inputId,
          outputId: null,
          log: null,
        ),
        isNot(fresh),
      );
    });

    test('has a readable toString', () {
      expect(fresh.toString(), startsWith('Step('));
      expect(fresh.toString(), contains('command.log'));
    });

    test('throws on missing or mistyped fields, naming the field', () {
      expect(
        _problem(
          () => Step.fromJson(
            _decode(
              '{"id":"$_stepId","runId":"$_runId","inputId":null,'
              '"outputId":null}',
            ),
          ),
        ),
        'log: missing',
      );
      expect(
        _problem(
          () => Step.fromJson(
            _decode(
              '{"id":"$_stepId","runId":"$_runId","inputId":null,'
              '"outputId":7,"log":null}',
            ),
          ),
        ),
        'outputId: expected a string or null',
      );
      expect(
        _problem(
          () => Step.fromJson(
            _decode(
              '{"id":"$_stepId","runId":null,"inputId":null,'
              '"outputId":null,"log":null}',
            ),
          ),
        ),
        'runId: expected a string',
      );
    });
  });

  group('Document', () {
    test('writes id, sessionId, value', () {
      expect(
        jsonEncode(
          Document(
            id: _inputId,
            sessionId: _sessionId,
            value: {'a': 1},
          ).toJson(),
        ),
        '{"id":"$_inputId","sessionId":"$_sessionId","value":{"a":1}}',
      );
    });

    test('keeps any JSON value through a round trip, null included', () {
      for (final value in <Object?>[
        null,
        true,
        3,
        1.5,
        'text',
        <Object?>[1, 'two', null],
        <String, Object?>{
          'branch': 'main',
          'nested': {
            'list': [1, 2],
          },
        },
      ]) {
        final document = Document(
          id: _inputId,
          sessionId: _sessionId,
          value: value,
        );
        final read = Document.fromJson(_decode(jsonEncode(document.toJson())));
        expect(read, document);
        expect(read.value, value);
      }
    });

    test('writes a null value rather than leaving the key out', () {
      expect(
        jsonEncode(
          Document(id: _inputId, sessionId: _sessionId, value: null).toJson(),
        ),
        '{"id":"$_inputId","sessionId":"$_sessionId","value":null}',
      );
    });

    test('compares the value by value, deeply', () {
      Document of(Object? value) =>
          Document(id: _inputId, sessionId: _sessionId, value: value);
      final a = of({
        'list': [
          1,
          {'x': 'y'},
        ],
      });
      final b = of({
        'list': [
          1,
          {'x': 'y'},
        ],
      });
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(
        a,
        isNot(
          of({
            'list': [
              1,
              {'x': 'z'},
            ],
          }),
        ),
      );
      expect(of(null), isNot(of('null')));
      expect(of(1), isNot(of(1.5)));
      expect(
        Document(id: _outputId, sessionId: _sessionId, value: 1),
        isNot(of(1)),
      );
    });

    test('has a readable toString', () {
      final document = Document(
        id: _inputId,
        sessionId: _sessionId,
        value: {'branch': 'main'},
      );
      expect(document.toString(), startsWith('Document('));
      expect(document.toString(), contains('branch'));
    });

    test('throws when value is missing but accepts null', () {
      expect(
        _problem(
          () => Document.fromJson(
            _decode('{"id":"$_inputId","sessionId":"$_sessionId"}'),
          ),
        ),
        'value: missing',
      );
      expect(
        Document.fromJson(
          _decode('{"id":"$_inputId","sessionId":"$_sessionId","value":null}'),
        ).value,
        isNull,
      );
      expect(
        _problem(
          () => Document.fromJson(_decode('{"sessionId":"s","value":1}')),
        ),
        'id: missing',
      );
    });
  });
}
