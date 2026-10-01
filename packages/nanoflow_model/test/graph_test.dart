import 'dart:convert';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:test/test.dart';

/// The graph from the README «Формат», as JSON.
const String _readmeGraph = r'''
{
  "start": "collect",
  "types": {
    "Request": {
      "type": "object",
      "required": ["branch"],
      "properties": {"branch": {"type": "string"}}
    },
    "Change": {
      "type": "object",
      "required": ["id", "path"],
      "properties": {"id": {"type": "string"}, "path": {"type": "string"}}
    },
    "Report": {
      "type": "object",
      "required": ["change", "findings"],
      "properties": {
        "change": {"$ref": "#/Change"},
        "findings": {"type": "array", "items": {"type": "string"}}
      }
    }
  },
  "nodes": {
    "collect": {
      "command": "nodes/collect/run.sh",
      "in": {"$ref": "#/Request"},
      "out": {"$ref": "#/Change"},
      "then": "is-empty"
    },
    "is-empty": {
      "decide": "nodes/is-empty/run.sh",
      "in": {"$ref": "#/Change"},
      "then": "discard",
      "else": "inspect"
    },
    "inspect": {
      "command": "nodes/inspect/run.sh",
      "in": {"$ref": "#/Change"},
      "out": {"$ref": "#/Report"},
      "then": "verdict"
    },
    "verdict": {
      "decide": "nodes/verdict/run.sh",
      "in": {"$ref": "#/Report"},
      "then": {
        "accepted": ["publish", "notify"],
        "returned": "fix"
      }
    },
    "fix": {
      "command": "nodes/fix/run.sh",
      "in": {"$ref": "#/Report"},
      "out": {"$ref": "#/Change"},
      "then": "inspect"
    },
    "publish": {
      "command": "nodes/publish/run.sh",
      "in": {"$ref": "#/Report"}
    },
    "discard": {
      "command": "nodes/discard/run.sh",
      "in": {"$ref": "#/Change"}
    },
    "notify": {
      "command": "nodes/notify/run.sh",
      "in": {"$ref": "#/Report"}
    }
  }
}
''';

Map<String, Object?> _readme() =>
    jsonDecode(_readmeGraph) as Map<String, Object?>;

/// A graph with one fork `f` whose `decide` has the given [then] and [otherwise].
ForkNode _fork(Object? then, {Object? otherwise, bool hasElse = false}) {
  final graph = Graph.fromJson({
    'start': 'f',
    'nodes': {
      'f': {
        'decide': 'decide.sh',
        'then': then,
        if (hasElse) 'else': otherwise,
      },
    },
  });
  return graph['f']! as ForkNode;
}

Matcher _formatExceptionAt(String place) => throwsA(
  isA<FormatException>().having(
    (e) => e.message,
    'message',
    startsWith('$place: '),
  ),
);

Matcher _routesTo({
  required String label,
  required Target target,
  bool isElse = false,
}) => isA<RouteTo>()
    .having((r) => r.exit.label, 'exit.label', label)
    .having((r) => r.target, 'target', target)
    .having((r) => r.exit.isElse, 'exit.isElse', isElse);

void main() {
  group('Target', () {
    test('a node target holds one name and is not a list', () {
      const target = Target.node('inspect');

      expect(target.names, ['inspect']);
      expect(target.isList, isFalse);
      expect(target.isEmpty, isFalse);
      expect(target.toJson(), 'inspect');
    });

    test('a list target holds its names in order', () {
      const target = Target.list(['publish', 'notify']);

      expect(target.names, ['publish', 'notify']);
      expect(target.isList, isTrue);
      expect(target.isEmpty, isFalse);
      expect(target.toJson(), ['publish', 'notify']);
    });

    test('an empty list target is empty: the run ends', () {
      const target = Target.list([]);

      expect(target.names, isEmpty);
      expect(target.isList, isTrue);
      expect(target.isEmpty, isTrue);
      expect(target.toJson(), <String>[]);
    });

    test('a one-name list is not the same as a node', () {
      expect(const Target.list(['a']), isNot(const Target.node('a')));
      expect(const Target.list(['a']).toJson(), ['a']);
      expect(const Target.node('a').toJson(), 'a');
    });

    test('has value equality and a matching hashCode', () {
      expect(const Target.node('a'), const Target.node('a'));
      expect(const Target.node('a').hashCode, const Target.node('a').hashCode);
      expect(const Target.node('a'), isNot(const Target.node('b')));
      expect(const Target.list(['a', 'b']), const Target.list(['a', 'b']));
      expect(
        const Target.list(['a', 'b']).hashCode,
        const Target.list(['a', 'b']).hashCode,
      );
      expect(
        const Target.list(['a', 'b']),
        isNot(const Target.list(['b', 'a'])),
      );
      expect(const Target.list([]), const Target.list([]));
    });

    test('fromJson reads a string as a node and a list as a list', () {
      expect(Target.fromJson('inspect'), const Target.node('inspect'));
      expect(
        Target.fromJson(<Object?>['publish', 'notify']),
        const Target.list(['publish', 'notify']),
      );
      expect(Target.fromJson(<Object?>[]), const Target.list([]));
    });

    test('fromJson round trips through toJson', () {
      for (final json in <Object>[
        'a',
        <Object?>['a', 'b'],
        <Object?>[],
      ]) {
        expect(Target.fromJson(json).toJson(), json);
      }
    });

    test('fromJson rejects every other shape with a FormatException', () {
      for (final json in <Object?>[
        null,
        1,
        true,
        <String, Object?>{},
        <String, Object?>{'a': 'b'},
        <Object?>[1],
        <Object?>['a', null],
        <Object?>[
          <Object?>['a'],
        ],
      ]) {
        expect(
          () => Target.fromJson(json),
          throwsFormatException,
          reason: '$json',
        );
      }
    });
  });

  group('Exit', () {
    test('has value equality over label, target and isElse', () {
      const a = Exit(label: 'true', target: Target.node('x'));

      expect(a, const Exit(label: 'true', target: Target.node('x')));
      expect(
        a.hashCode,
        const Exit(label: 'true', target: Target.node('x')).hashCode,
      );
      expect(a, isNot(const Exit(label: 'false', target: Target.node('x'))));
      expect(a, isNot(const Exit(label: 'true', target: Target.node('y'))));
      expect(
        a,
        isNot(
          const Exit(label: 'true', target: Target.node('x'), isElse: true),
        ),
      );
      expect(const Exit(label: null, target: Target.node('x')), isNot(a));
    });
  });

  group('Graph.fromJson, the README graph', () {
    late Graph graph;

    setUp(() => graph = Graph.fromJson(_readme()));

    test('reads start, types and the nodes in declaration order', () {
      expect(graph.start, const Target.node('collect'));
      expect(graph.types.keys, ['Request', 'Change', 'Report']);
      expect(graph.types['Change'], {
        'type': 'object',
        'required': ['id', 'path'],
        'properties': {
          'id': {'type': 'string'},
          'path': {'type': 'string'},
        },
      });
      expect(graph.nodes.keys, [
        'collect',
        'is-empty',
        'inspect',
        'verdict',
        'fix',
        'publish',
        'discard',
        'notify',
      ]);
    });

    test(
      'keeps the raw JSON it was parsed from and returns it from toJson',
      () {
        final json = _readme();
        final parsed = Graph.fromJson(json);

        expect(parsed.json, same(json));
        expect(parsed.toJson(), same(json));
      },
    );

    test('looks nodes up by name', () {
      expect(graph['inspect'], same(graph.nodes['inspect']));
      expect(graph['nope'], isNull);
    });

    test('collect is a worker with in, out and an unconditional then', () {
      final node = graph['collect']! as WorkerNode;

      expect(node.name, 'collect');
      expect(node.run, 'nodes/collect/run.sh');
      expect(node.command, 'nodes/collect/run.sh');
      expect(node.input, {r'$ref': '#/Request'});
      expect(node.output, {r'$ref': '#/Change'});
      expect(node.then, const Target.node('is-empty'));
      expect(node.exits, [
        const Exit(label: null, target: Target.node('is-empty')),
      ]);
    });

    test('is-empty is an if fork with then and else', () {
      final node = graph['is-empty']! as ForkNode;

      expect(node.name, 'is-empty');
      expect(node.run, 'nodes/is-empty/run.sh');
      expect(node.decide, 'nodes/is-empty/run.sh');
      expect(node.input, {r'$ref': '#/Change'});
      expect(node.isIf, isTrue);
      expect(node.ifTrue, const Target.node('discard'));
      expect(node.cases, isNull);
      expect(node.otherwise, const Target.node('inspect'));
      expect(node.exits, [
        const Exit(label: 'true', target: Target.node('discard')),
        const Exit(label: 'else', target: Target.node('inspect'), isElse: true),
      ]);
    });

    test('verdict is a switch fork with a list target and no else', () {
      final node = graph['verdict']! as ForkNode;

      expect(node.run, 'nodes/verdict/run.sh');
      expect(node.input, {r'$ref': '#/Report'});
      expect(node.isIf, isFalse);
      expect(node.ifTrue, isNull);
      expect(node.cases, {
        'accepted': const Target.list(['publish', 'notify']),
        'returned': const Target.node('fix'),
      });
      expect(node.cases!.keys, ['accepted', 'returned']);
      expect(node.otherwise, isNull);
      expect(node.exits, [
        const Exit(
          label: 'accepted',
          target: Target.list(['publish', 'notify']),
        ),
        const Exit(label: 'returned', target: Target.node('fix')),
      ]);
    });

    test('inspect and fix are workers that loop through then', () {
      final inspect = graph['inspect']! as WorkerNode;
      final fix = graph['fix']! as WorkerNode;

      expect(inspect.output, {r'$ref': '#/Report'});
      expect(inspect.then, const Target.node('verdict'));
      expect(fix.input, {r'$ref': '#/Report'});
      expect(fix.output, {r'$ref': '#/Change'});
      expect(fix.then, const Target.node('inspect'));
      expect(fix.exits, [
        const Exit(label: null, target: Target.node('inspect')),
      ]);
    });

    test('publish, discard and notify end the run: no then, no exits', () {
      for (final name in ['publish', 'discard', 'notify']) {
        final node = graph[name]! as WorkerNode;

        expect(node.then, isNull, reason: name);
        expect(node.output, isNull, reason: name);
        expect(node.exits, isEmpty, reason: name);
        expect(node.input, isNotNull, reason: name);
      }
    });

    test('exits cannot be modified', () {
      final node = graph['collect']! as WorkerNode;

      expect(
        () => node.exits.add(const Exit(label: null, target: Target.list([]))),
        throwsUnsupportedError,
      );
    });
  });

  group('Graph.fromJson, other valid shapes', () {
    test('a graph with several start nodes and no types', () {
      final graph = Graph.fromJson({
        'start': ['a', 'b'],
        'nodes': {
          'a': {'command': 'a.sh'},
          'b': {'command': 'b.sh'},
        },
      });

      expect(graph.start, const Target.list(['a', 'b']));
      expect(graph.types, isEmpty);
    });

    test('an empty start list is valid: the run ends at once', () {
      final graph = Graph.fromJson({'start': <Object?>[], 'nodes': {}});

      expect(graph.start.isEmpty, isTrue);
      expect(graph.nodes, isEmpty);
    });

    test('a node without in has a null input', () {
      final graph = Graph.fromJson({
        'start': 'a',
        'nodes': {
          'a': {'command': 'a.sh'},
          'f': {'decide': 'f.sh', 'then': 'a'},
        },
      });

      expect(graph['a']!.input, isNull);
      expect(graph['f']!.input, isNull);
    });

    test('node order is declaration order, not name order', () {
      final graph = Graph.fromJson({
        'start': 'z',
        'nodes': {
          'z': {'command': 'z.sh'},
          'a': {'command': 'a.sh'},
          'm': {'command': 'm.sh'},
        },
      });

      expect(graph.nodes.keys, ['z', 'a', 'm']);
    });

    test('targets are not checked against the nodes: that is check work', () {
      final graph = Graph.fromJson({
        'start': 'nowhere',
        'nodes': {
          'a': {'command': 'a.sh', 'then': 'missing'},
        },
      });

      expect(graph.start, const Target.node('nowhere'));
      expect((graph['a']! as WorkerNode).then, const Target.node('missing'));
    });

    test('a switch keeps its keys in map order and puts else last', () {
      final node = _fork(
        {'b': 'x', 'a': 'y', 'c': <Object?>[]},
        hasElse: true,
        otherwise: 'z',
      );

      expect(node.exits.map((e) => e.label), ['b', 'a', 'c', 'else']);
      expect(node.exits.map((e) => e.isElse), [false, false, false, true]);
    });

    test('an empty switch map has no cases', () {
      final node = _fork(<String, Object?>{});

      expect(node.isIf, isFalse);
      expect(node.cases, isEmpty);
      expect(node.exits, isEmpty);
    });
  });

  group('ForkNode.route, if form', () {
    test('true goes to then', () {
      final node = _fork('discard', hasElse: true, otherwise: 'inspect');

      expect(
        node.route(true),
        _routesTo(label: 'true', target: const Target.node('discard')),
      );
    });

    test('true goes to then when there is no else', () {
      final node = _fork('discard');

      expect(
        node.route(true),
        _routesTo(label: 'true', target: const Target.node('discard')),
      );
    });

    test('only JSON true matches: everything else goes to else', () {
      final node = _fork('discard', hasElse: true, otherwise: 'inspect');

      for (final outcome in <Object?>[
        'true',
        1,
        1.0,
        null,
        false,
        0,
        '',
        'yes',
        <Object?>[true],
        <String, Object?>{'true': true},
      ]) {
        expect(
          node.route(outcome),
          _routesTo(
            label: 'else',
            target: const Target.node('inspect'),
            isElse: true,
          ),
          reason: '$outcome',
        );
      }
    });

    test('without else a miss ends the run', () {
      final node = _fork('discard');

      for (final outcome in <Object?>['true', 1, null, false]) {
        expect(node.route(outcome), isA<RouteEnd>(), reason: '$outcome');
      }
    });

    test('an empty else list is still an else: a route to nothing', () {
      final node = _fork('discard', hasElse: true, otherwise: <Object?>[]);

      final route = node.route(false);

      expect(
        route,
        _routesTo(label: 'else', target: const Target.list([]), isElse: true),
      );
      expect((route as RouteTo).target.isEmpty, isTrue);
    });

    test('a list then is the target of true', () {
      final node = _fork(<Object?>['a', 'b']);

      expect(
        node.route(true),
        _routesTo(label: 'true', target: const Target.list(['a', 'b'])),
      );
    });
  });

  group('ForkNode.route, switch form', () {
    final switchThen = <String, Object?>{
      'accepted': <Object?>['publish', 'notify'],
      'returned': 'fix',
      '1': 'one',
      'else': 'literal-else-key',
    };

    test('a string equal to a key goes to that key target', () {
      final node = _fork(switchThen);

      expect(
        node.route('accepted'),
        _routesTo(
          label: 'accepted',
          target: const Target.list(['publish', 'notify']),
        ),
      );
      expect(
        node.route('returned'),
        _routesTo(label: 'returned', target: const Target.node('fix')),
      );
    });

    test('the number 1 does not match the key "1"', () {
      final node = _fork({'1': 'one'});

      final route = node.route(1);

      expect(route, isA<RouteMissing>());
      expect((route as RouteMissing).outcome, 1);
      expect(
        node.route('1'),
        _routesTo(label: '1', target: const Target.node('one')),
      );
    });

    test('matching is exact: case and spaces count', () {
      final node = _fork({'accepted': 'a'});

      for (final outcome in <Object?>['Accepted', 'accepted ', ' accepted']) {
        expect(node.route(outcome), isA<RouteMissing>(), reason: '$outcome');
      }
    });

    test('no match with else goes to else', () {
      final node = _fork(
        {'accepted': 'a', 'returned': 'b'},
        hasElse: true,
        otherwise: 'fallback',
      );

      for (final outcome in <Object?>['other', 1, true, false, null, '']) {
        expect(
          node.route(outcome),
          _routesTo(
            label: 'else',
            target: const Target.node('fallback'),
            isElse: true,
          ),
          reason: '$outcome',
        );
      }
    });

    test('no match without else is RouteMissing carrying the outcome', () {
      final node = _fork({'accepted': 'a'});

      for (final outcome in <Object?>[
        'other',
        1,
        true,
        null,
        <Object?>['accepted'],
        <String, Object?>{'accepted': 1},
      ]) {
        final route = node.route(outcome);

        expect(route, isA<RouteMissing>(), reason: '$outcome');
        expect((route as RouteMissing).outcome, outcome, reason: '$outcome');
      }
    });

    test('an empty else list is a route to nothing, not an error', () {
      final node = _fork(
        {'accepted': 'a'},
        hasElse: true,
        otherwise: <Object?>[],
      );

      final route = node.route('other');

      expect(
        route,
        _routesTo(label: 'else', target: const Target.list([]), isElse: true),
      );
      expect((route as RouteTo).target.isEmpty, isTrue);
    });

    test('a key spelled else is a case, not the else exit', () {
      final node = _fork(
        {'else': 'literal'},
        hasElse: true,
        otherwise: 'fallback',
      );

      expect(
        node.route('else'),
        _routesTo(label: 'else', target: const Target.node('literal')),
      );
      expect(
        node.route('other'),
        _routesTo(
          label: 'else',
          target: const Target.node('fallback'),
          isElse: true,
        ),
      );
    });

    test('an empty list as a case target is a route to nothing', () {
      final node = _fork({'done': <Object?>[]});

      expect(
        node.route('done'),
        _routesTo(label: 'done', target: const Target.list([])),
      );
    });
  });

  group('Graph.fromJson, malformed JSON', () {
    Graph parse(Map<String, Object?> json) => Graph.fromJson(json);

    Map<String, Object?> graphWith(Object? node) => {
      'start': 'n',
      'nodes': {'n': node},
    };

    test('start is required and must be a target', () {
      _expectAt('start', () => parse({'nodes': <String, Object?>{}}));
      _expectAt('start', () => parse({'start': null, 'nodes': {}}));
      _expectAt('start', () => parse({'start': 1, 'nodes': {}}));
      _expectAt(
        'start[1]',
        () => parse({
          'start': ['a', 2],
          'nodes': {},
        }),
      );
      _expectAt(
        'start',
        () => parse({
          'start': {'a': 'b'},
          'nodes': {},
        }),
      );
    });

    test('types must be an object when present', () {
      _expectAt('types', () => parse({'start': 'a', 'types': [], 'nodes': {}}));
      _expectAt('types', () => parse({'start': 'a', 'types': 1, 'nodes': {}}));
      _expectAt(
        'types',
        () => parse({'start': 'a', 'types': null, 'nodes': {}}),
      );
    });

    test('nodes is required and must be an object of objects', () {
      _expectAt('nodes', () => parse({'start': 'a'}));
      _expectAt('nodes', () => parse({'start': 'a', 'nodes': []}));
      _expectAt('nodes', () => parse({'start': 'a', 'nodes': null}));
      _expectAt('nodes.n', () => parse(graphWith('x')));
      _expectAt('nodes.n', () => parse(graphWith(null)));
      _expectAt('nodes.n', () => parse(graphWith(['command'])));
    });

    test('a node with both command and decide is rejected', () {
      _expectAt(
        'nodes.n',
        () => parse(graphWith({'command': 'a', 'decide': 'b', 'then': 'x'})),
      );
    });

    test('a node with neither command nor decide is rejected', () {
      _expectAt('nodes.n', () => parse(graphWith(<String, Object?>{})));
      _expectAt(
        'nodes.n',
        () => parse(graphWith({'in': <String, Object?>{}, 'then': 'x'})),
      );
    });

    test('command and decide must be strings', () {
      _expectAt('nodes.n.command', () => parse(graphWith({'command': 1})));
      _expectAt('nodes.n.command', () => parse(graphWith({'command': null})));
      _expectAt(
        'nodes.n.decide',
        () => parse(
          graphWith({
            'decide': ['a'],
            'then': 'x',
          }),
        ),
      );
    });

    test('a worker then must be a node or a list, never a map', () {
      _expectAt(
        'nodes.n.then',
        () => parse(graphWith({'command': 'a', 'then': 1})),
      );
      _expectAt(
        'nodes.n.then',
        () => parse(graphWith({'command': 'a', 'then': null})),
      );
      _expectAt(
        'nodes.n.then',
        () => parse(
          graphWith({
            'command': 'a',
            'then': {'k': 'x'},
          }),
        ),
      );
      _expectAt(
        'nodes.n.then[1]',
        () => parse(
          graphWith({
            'command': 'a',
            'then': ['x', 2],
          }),
        ),
      );
    });

    test('a worker with else is rejected', () {
      _expectAt(
        'nodes.n.else',
        () => parse(graphWith({'command': 'a', 'then': 'x', 'else': 'y'})),
      );
    });

    test('a fork without then is rejected', () {
      _expectAt('nodes.n.then', () => parse(graphWith({'decide': 'a'})));
      _expectAt(
        'nodes.n.then',
        () => parse(graphWith({'decide': 'a', 'else': 'y'})),
      );
    });

    test('a fork then must be a target or a map of targets', () {
      _expectAt(
        'nodes.n.then',
        () => parse(graphWith({'decide': 'a', 'then': 1})),
      );
      _expectAt(
        'nodes.n.then',
        () => parse(graphWith({'decide': 'a', 'then': null})),
      );
      _expectAt(
        'nodes.n.then[0]',
        () => parse(
          graphWith({
            'decide': 'a',
            'then': [1],
          }),
        ),
      );
    });

    test('a fork case target is checked and named by its key', () {
      _expectAt(
        'nodes.n.then.accepted',
        () => parse(
          graphWith({
            'decide': 'a',
            'then': {'accepted': 1},
          }),
        ),
      );
      _expectAt(
        'nodes.n.then.accepted',
        () => parse(
          graphWith({
            'decide': 'a',
            'then': {'accepted': null},
          }),
        ),
      );
      _expectAt(
        'nodes.n.then.accepted',
        () => parse(
          graphWith({
            'decide': 'a',
            'then': {
              'accepted': {'a': 'b'},
            },
          }),
        ),
      );
      _expectAt(
        'nodes.n.then.returned[1]',
        () => parse(
          graphWith({
            'decide': 'a',
            'then': {
              'accepted': 'x',
              'returned': ['y', true],
            },
          }),
        ),
      );
    });

    test('a fork else must be a target', () {
      _expectAt(
        'nodes.n.else',
        () => parse(graphWith({'decide': 'a', 'then': 'x', 'else': 1})),
      );
      _expectAt(
        'nodes.n.else',
        () => parse(graphWith({'decide': 'a', 'then': 'x', 'else': null})),
      );
      _expectAt(
        'nodes.n.else[0]',
        () => parse(
          graphWith({
            'decide': 'a',
            'then': 'x',
            'else': [null],
          }),
        ),
      );
    });

    test('the place names the node that is broken', () {
      _expectAt(
        'nodes.verdict.then',
        () => parse({
          'start': 'a',
          'nodes': {
            'a': {'command': 'a.sh', 'then': 'verdict'},
            'verdict': {'decide': 'v.sh', 'then': 5},
          },
        }),
      );
    });
  });

  group('Graph.fromJson, tolerance', () {
    test('takes maps whose runtime type is Map<dynamic, dynamic>', () {
      final dynamic untyped = <dynamic, dynamic>{
        'a': {'command': 'a.sh', 'then': 'b'},
        'b': {'command': 'b.sh'},
      };
      final dynamic types = <dynamic, dynamic>{};

      final graph = Graph.fromJson({
        'start': 'a',
        'types': types,
        'nodes': untyped,
      });

      expect(graph.nodes.keys, ['a', 'b']);
      expect(graph.types, isEmpty);
    });

    test('rejects a map with a non-string key', () {
      final dynamic nodes = <dynamic, dynamic>{1: <String, Object?>{}};

      _expectAt('nodes', () => Graph.fromJson({'start': 'a', 'nodes': nodes}));
    });

    test(
      'never throws anything but FormatException, wherever a value is wrong',
      () {
        const wrong = <Object?>[
          null,
          1,
          true,
          'x',
          <Object?>[],
          <Object?>[1],
          <String, Object?>{},
          <String, Object?>{'k': 1},
        ];
        var parsed = 0;
        var rejected = 0;

        // Replaces the value at every place of the README graph in turn.
        void visit(Object? tree, List<Object> path) {
          if (tree is Map<String, Object?>) {
            for (final key in tree.keys.toList()) {
              visit(tree[key], [...path, key]);
            }
          } else if (tree is List<Object?>) {
            for (var i = 0; i < tree.length; i++) {
              visit(tree[i], [...path, i]);
            }
          }
          if (path.isEmpty) return;
          for (final value in wrong) {
            final copy = _readme();
            Object? parent = copy;
            for (final step in path.take(path.length - 1)) {
              parent = parent is Map<String, Object?>
                  ? parent[step as String]
                  : (parent! as List<Object?>)[step as int];
            }
            if (parent is Map<String, Object?>) {
              parent[path.last as String] = value;
            } else {
              (parent! as List<Object?>)[path.last as int] = value;
            }
            try {
              Graph.fromJson(copy);
              parsed++;
            } on FormatException {
              rejected++;
            }
          }
        }

        visit(_readme(), []);

        expect(parsed, greaterThan(0));
        expect(rejected, greaterThan(0));
      },
    );
  });

  group('GraphDescription', () {
    Map<String, Object?> description() => {
      'file': '/work/review/graph.yaml',
      'graph': _readme(),
    };

    test('reads the file and the graph', () {
      final parsed = GraphDescription.fromJson(description());

      expect(parsed.file, '/work/review/graph.yaml');
      expect(parsed.graph.start, const Target.node('collect'));
      expect(parsed.graph.nodes, hasLength(8));
    });

    test('round trips through toJson, also through JSON text', () {
      final json = description();

      expect(GraphDescription.fromJson(json).toJson(), json);
      expect(
        GraphDescription.fromJson(jsonDecode(jsonEncode(json))).toJson(),
        json,
      );
      expect(
        jsonEncode(GraphDescription.fromJson(json).toJson()),
        jsonEncode(json),
      );
    });

    test('toJson keeps the keys in the order file, graph', () {
      final json = GraphDescription.fromJson(description()).toJson();

      expect(json.keys, ['file', 'graph']);
      expect(json['graph'], same(GraphDescription.fromJson(json).graph.json));
    });

    test('rejects anything but an object with file and graph', () {
      for (final json in <Object?>[null, 1, 'x', <Object?>[]]) {
        expect(
          () => GraphDescription.fromJson(json),
          throwsFormatException,
          reason: '$json',
        );
      }
      _expectAt('file', () => GraphDescription.fromJson({'graph': _readme()}));
      _expectAt(
        'file',
        () => GraphDescription.fromJson({'file': 1, 'graph': _readme()}),
      );
      _expectAt('graph', () => GraphDescription.fromJson({'file': 'g.yaml'}));
      _expectAt(
        'graph',
        () =>
            GraphDescription.fromJson({'file': 'g.yaml', 'graph': <Object?>[]}),
      );
    });

    test('reports a missing file or graph like any other model does', () {
      expect(
        () => GraphDescription.fromJson({'graph': _readme()}),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'file: missing',
          ),
        ),
      );
      expect(
        () => GraphDescription.fromJson({'file': 'g.yaml'}),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'graph: missing',
          ),
        ),
      );
    });

    test('a malformed graph is reported under graph.', () {
      final graph = _readme();
      (graph['nodes']! as Map<String, Object?>)['verdict'] = {
        'decide': 'v.sh',
        'then': 5,
      };

      _expectAt(
        'graph.nodes.verdict.then',
        () => GraphDescription.fromJson({'file': 'g.yaml', 'graph': graph}),
      );
    });
  });
}

void _expectAt(String place, void Function() body) {
  expect(body, _formatExceptionAt(place));
}
