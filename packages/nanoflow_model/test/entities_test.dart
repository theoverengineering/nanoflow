import 'dart:convert';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:test/test.dart';

const String _sessionId = '8d3a9c1e-5b2f-4e7a-a0c4-1f6b2d9e3a57';
const String _otherId = '0c6e1f7a-93d4-4b58-8e21-5a7d3c9b4f06';
const String _effectId = '2e9b7a40-d1c8-4f35-9a6e-8b3c5d7f1e92';
const String _inputId = 'a7c5e3b1-4d92-4860-8f1a-6c9e2b7d3f58';
const String _outputId = '5f2d8b6a-1c93-4e07-a4b8-9e3c7a1d5b20';

const String _key = 'collect#1@e3b0c44298fc1c14';
const String _afterKey = 'inspect#1@9f2c1a7b3d5e8f04';

const String _graphJson =
    '{"format":2,"workflows":["lib/review.dart#review"],"functions":{}}';

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
    final session = Session(
      id: _sessionId,
      workflow: 'review',
      graph: _decode(_graphJson),
      inputId: _inputId,
    );
    final text =
        '{"id":"$_sessionId","workflow":"review","graph":$_graphJson,'
        '"inputId":"$_inputId"}';

    test('writes id, workflow, graph, inputId', () {
      expect(jsonEncode(session.toJson()), text);
    });

    test('writes a missing graph and input as null', () {
      expect(
        jsonEncode(
          Session(
            id: _sessionId,
            workflow: 'review',
            graph: null,
            inputId: null,
          ).toJson(),
        ),
        '{"id":"$_sessionId","workflow":"review","graph":null,'
        '"inputId":null}',
      );
    });

    test('round trips through JSON', () {
      final bare = Session(
        id: _sessionId,
        workflow: 'review',
        graph: null,
        inputId: null,
      );
      for (final model in [session, bare]) {
        final read = Session.fromJson(_decode(jsonEncode(model.toJson())));
        expect(read, model);
        expect(read.toJson(), model.toJson());
      }
    });

    test('compares the graph by value, deeply', () {
      final other = Session(
        id: _sessionId,
        workflow: 'review',
        graph: _decode(_graphJson),
        inputId: _inputId,
      );
      expect(other, session);
      expect(other.hashCode, session.hashCode);
      final changed = _decode(_graphJson);
      (changed['workflows'] as List<Object?>).add('lib/other.dart#other');
      expect(
        Session(
          id: _sessionId,
          workflow: 'review',
          graph: changed,
          inputId: _inputId,
        ),
        isNot(session),
      );
      expect(
        Session(
          id: _sessionId,
          workflow: 'review',
          graph: null,
          inputId: _inputId,
        ),
        isNot(session),
      );
    });

    test('compares every other field', () {
      Session variant({
        String id = _sessionId,
        String workflow = 'review',
        String? inputId = _inputId,
      }) => Session(
        id: id,
        workflow: workflow,
        graph: _decode(_graphJson),
        inputId: inputId,
      );
      expect(variant(id: _otherId), isNot(session));
      expect(variant(workflow: 'publish'), isNot(session));
      expect(variant(inputId: null), isNot(session));
    });

    test('has a readable toString', () {
      expect(session.toString(), startsWith('Session('));
      expect(session.toString(), contains(_sessionId));
      expect(session.toString(), contains('review'));
    });

    test('throws on missing or mistyped fields, naming the field', () {
      expect(
        _problem(
          () => Session.fromJson(
            _decode('{"workflow":"review","graph":null,"inputId":null}'),
          ),
        ),
        'id: missing',
      );
      expect(
        _problem(
          () => Session.fromJson(
            _decode('{"id":"$_sessionId","graph":null,"inputId":null}'),
          ),
        ),
        'workflow: missing',
      );
      expect(
        _problem(
          () => Session.fromJson(
            _decode(
              '{"id":"$_sessionId","workflow":7,"graph":null,"inputId":null}',
            ),
          ),
        ),
        'workflow: expected a string',
      );
      expect(
        _problem(
          () => Session.fromJson(
            _decode('{"id":"$_sessionId","workflow":"review","inputId":null}'),
          ),
        ),
        'graph: missing',
      );
      expect(
        _problem(
          () => Session.fromJson(
            _decode(
              '{"id":"$_sessionId","workflow":"review","graph":[],'
              '"inputId":null}',
            ),
          ),
        ),
        'graph: expected an object or null',
      );
      expect(
        _problem(
          () => Session.fromJson({
            'id': _sessionId,
            'workflow': 'review',
            'graph': {1: 'not a string key'},
            'inputId': null,
          }),
        ),
        'graph: expected an object or null',
      );
      expect(
        _problem(
          () => Session.fromJson(
            _decode('{"id":"$_sessionId","workflow":"review","graph":null}'),
          ),
        ),
        'inputId: missing',
      );
      expect(
        _problem(
          () => Session.fromJson(
            _decode(
              '{"id":"$_sessionId","workflow":"review","graph":null,'
              '"inputId":5}',
            ),
          ),
        ),
        'inputId: expected a string or null',
      );
    });

    test('takes a graph written as a bare map literal', () {
      // What an empty map literal inside another map literal is.
      final read = Session.fromJson({
        'id': _sessionId,
        'workflow': 'review',
        'graph': {'format': 2, 'functions': <dynamic, dynamic>{}},
        'inputId': null,
      });
      expect(read.graph, {'format': 2, 'functions': <String, Object?>{}});
    });
  });

  group('Effect', () {
    final fresh = Effect(
      id: _effectId,
      sessionId: _sessionId,
      name: 'collect',
      key: _key,
      after: _afterKey,
      place: 'lib/review.dart:12',
      outputId: null,
      log: 'effect.log',
    );

    test('writes id, sessionId, name, key, after, place, outputId, log', () {
      expect(
        jsonEncode(fresh.withOutput(_outputId).toJson()),
        '{"id":"$_effectId","sessionId":"$_sessionId","name":"collect",'
        '"key":"$_key","after":"$_afterKey","place":"lib/review.dart:12",'
        '"outputId":"$_outputId","log":"effect.log"}',
      );
    });

    test('keeps null after, place and outputId', () {
      expect(
        jsonEncode(
          Effect(
            id: _effectId,
            sessionId: _sessionId,
            name: 'collect',
            key: _key,
            after: null,
            place: null,
            outputId: null,
            log: 'effect.log',
          ).toJson(),
        ),
        '{"id":"$_effectId","sessionId":"$_sessionId","name":"collect",'
        '"key":"$_key","after":null,"place":null,"outputId":null,'
        '"log":"effect.log"}',
      );
    });

    test('round trips through JSON', () {
      final done = fresh.withOutput(_outputId);
      for (final effect in [fresh, done]) {
        expect(Effect.fromJson(_decode(jsonEncode(effect.toJson()))), effect);
      }
    });

    test('withOutput changes only the outputId', () {
      final done = fresh.withOutput(_outputId);
      expect(done.outputId, _outputId);
      expect(
        done,
        Effect(
          id: _effectId,
          sessionId: _sessionId,
          name: 'collect',
          key: _key,
          after: _afterKey,
          place: 'lib/review.dart:12',
          outputId: _outputId,
          log: 'effect.log',
        ),
      );
      expect(fresh.outputId, isNull);
    });

    test('withAfter changes only the after', () {
      final done = fresh.withOutput(_outputId);
      expect(
        done.withAfter(null),
        Effect(
          id: _effectId,
          sessionId: _sessionId,
          name: 'collect',
          key: _key,
          after: null,
          place: 'lib/review.dart:12',
          outputId: _outputId,
          log: 'effect.log',
        ),
      );
      expect(done.after, _afterKey);
    });

    test('compares by value, every field', () {
      Effect variant({
        String id = _effectId,
        String sessionId = _sessionId,
        String name = 'collect',
        String key = _key,
        String? after = _afterKey,
        String? place = 'lib/review.dart:12',
        String? outputId,
        String log = 'effect.log',
      }) => Effect(
        id: id,
        sessionId: sessionId,
        name: name,
        key: key,
        after: after,
        place: place,
        outputId: outputId,
        log: log,
      );
      expect(variant(), fresh);
      expect(variant().hashCode, fresh.hashCode);
      expect(variant(id: _otherId), isNot(fresh));
      expect(variant(sessionId: _otherId), isNot(fresh));
      expect(variant(name: 'inspect'), isNot(fresh));
      expect(variant(key: _afterKey), isNot(fresh));
      expect(variant(after: null), isNot(fresh));
      expect(variant(place: 'lib/review.dart:13'), isNot(fresh));
      expect(variant(outputId: _outputId), isNot(fresh));
      expect(variant(log: 'other.log'), isNot(fresh));
    });

    test('has a readable toString', () {
      expect(fresh.toString(), startsWith('Effect('));
      expect(fresh.toString(), contains(_key));
      expect(fresh.toString(), contains('lib/review.dart:12'));
    });

    test('throws on missing or mistyped fields, naming the field', () {
      final complete = fresh.toJson();
      for (final key in complete.keys) {
        expect(
          _problem(() => Effect.fromJson({...complete}..remove(key))),
          '$key: missing',
          reason: key,
        );
      }
      expect(
        _problem(() => Effect.fromJson({...complete, 'name': null})),
        'name: expected a string',
      );
      expect(
        _problem(() => Effect.fromJson({...complete, 'key': 1})),
        'key: expected a string',
      );
      expect(
        _problem(() => Effect.fromJson({...complete, 'after': 1})),
        'after: expected a string or null',
      );
      expect(
        _problem(() => Effect.fromJson({...complete, 'place': false})),
        'place: expected a string or null',
      );
      expect(
        _problem(() => Effect.fromJson({...complete, 'outputId': 7})),
        'outputId: expected a string or null',
      );
      expect(
        _problem(() => Effect.fromJson({...complete, 'log': null})),
        'log: expected a string',
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
