import 'dart:convert';

import 'package:nanoflow_cli/nanoflow_cli.dart';
import 'package:test/test.dart';

/// [value] as `jsonDecode` gives it: what a graph program prints.
Map<String, Object?> json(Map<String, Object?> value) =>
    jsonDecode(jsonEncode(value)) as Map<String, Object?>;

/// The graph from README «Формат».
Map<String, Object?> readmeGraph() => json({
  'start': 'collect',
  'types': {
    'Request': {
      'type': 'object',
      'required': ['branch'],
      'properties': {
        'branch': {'type': 'string'},
      },
    },
    'Change': {
      'type': 'object',
      'required': ['id', 'path'],
      'properties': {
        'id': {'type': 'string'},
        'path': {'type': 'string'},
      },
    },
    'Report': {
      'type': 'object',
      'required': ['change', 'findings'],
      'properties': {
        'change': {r'$ref': '#/Change'},
        'findings': {
          'type': 'array',
          'items': {'type': 'string'},
        },
      },
    },
  },
  'nodes': {
    'collect': {
      'command': 'nodes/collect/run.sh',
      'in': {r'$ref': '#/Request'},
      'out': {r'$ref': '#/Change'},
      'then': 'is-empty',
    },
    'is-empty': {
      'decide': 'nodes/is-empty/run.sh',
      'in': {r'$ref': '#/Change'},
      'then': 'discard',
      'else': 'inspect',
    },
    'inspect': {
      'command': 'nodes/inspect/run.sh',
      'in': {r'$ref': '#/Change'},
      'out': {r'$ref': '#/Report'},
      'then': 'verdict',
    },
    'verdict': {
      'decide': 'nodes/verdict/run.sh',
      'in': {r'$ref': '#/Report'},
      'then': {
        'accepted': ['publish', 'notify'],
        'returned': 'fix',
      },
    },
    'fix': {
      'command': 'nodes/fix/run.sh',
      'in': {r'$ref': '#/Report'},
      'out': {r'$ref': '#/Change'},
      'then': 'inspect',
    },
    'publish': {
      'command': 'nodes/publish/run.sh',
      'in': {r'$ref': '#/Report'},
    },
    'discard': {
      'command': 'nodes/discard/run.sh',
      'in': {r'$ref': '#/Change'},
    },
    'notify': {
      'command': 'nodes/notify/run.sh',
      'in': {r'$ref': '#/Report'},
    },
  },
});

/// The node [name] of [graph], to change it in place.
Map<String, Object?> nodeOf(Map<String, Object?> graph, String name) =>
    (graph['nodes'] as Map<String, Object?>)[name] as Map<String, Object?>;

/// A graph of [nodes] that starts at [start].
Map<String, Object?> graphOf(Object start, Map<String, Object?> nodes) =>
    json({'start': start, 'nodes': nodes});

/// A worker that goes to [then], or ends the run without it.
Map<String, Object?> worker([Object? then]) => {
  'command': 'run.sh',
  'then': ?then,
};

/// A fork whose `then` is [then] and whose `else` is [otherwise].
Map<String, Object?> fork(Object then, [Object? otherwise]) => {
  'decide': 'decide.sh',
  'then': then,
  'else': ?otherwise,
};

void main() {
  test('the README graph passes', () {
    expect(checkGraph(readmeGraph()), isEmpty);
  });

  group('structure', () {
    test('a typo in a key is an unknown key of its node', () {
      final graph = readmeGraph();
      final inspect = nodeOf(graph, 'inspect');
      inspect['thn'] = inspect.remove('then');
      expect(checkGraph(graph), ['nodes.inspect: unknown key "thn"']);
    });

    test('a node has command or decide, not both', () {
      final graph = readmeGraph();
      nodeOf(graph, 'inspect')['decide'] = 'nodes/inspect/decide.sh';
      expect(checkGraph(graph), ['nodes.inspect: has both command and decide']);
    });

    test('a node has command or decide, not neither', () {
      final graph = readmeGraph();
      nodeOf(graph, 'inspect').remove('command');
      expect(checkGraph(graph), [
        'nodes.inspect: has neither command nor decide',
      ]);
    });

    test('a fork needs then', () {
      final graph = readmeGraph();
      nodeOf(graph, 'verdict').remove('then');
      expect(checkGraph(graph), ['nodes.verdict.then: missing']);
    });

    test('a worker has no else', () {
      final graph = readmeGraph();
      nodeOf(graph, 'inspect')['else'] = 'fix';
      expect(checkGraph(graph), ['nodes.inspect: unknown key "else"']);
    });

    test('a fork has no out', () {
      final graph = readmeGraph();
      nodeOf(graph, 'verdict')['out'] = {r'$ref': '#/Report'};
      expect(checkGraph(graph), ['nodes.verdict: unknown key "out"']);
    });

    test('the graph has no keys but start, types and nodes', () {
      final graph = readmeGraph()..['extra'] = true;
      expect(checkGraph(graph), ['graph: unknown key "extra"']);
    });

    test('the graph needs start and nodes', () {
      expect(checkGraph(readmeGraph()..remove('start')), ['start: missing']);
      expect(checkGraph(readmeGraph()..remove('nodes')), ['nodes: missing']);
    });

    test('the graph is an object', () {
      for (final graph in <Object?>[
        null,
        ['collect'],
        'collect',
        5,
      ]) {
        expect(checkGraph(graph), [
          'graph: expected an object',
        ], reason: '$graph');
      }
    });

    test('a problem ack names in its own words is passed on in them', () {
      final graph = readmeGraph()..['types'] = {'Score': double.infinity};
      expect(checkGraph(graph), [
        'graph: Expected an acyclic JSON value with finite numbers.',
      ]);
    });

    test('a value of the wrong type is placed at its key', () {
      final cases = <String, void Function(Map<String, Object?>)>{
        'start: expected a node name or a list of node names': (g) =>
            g['start'] = 5,
        'start[1]: expected a node name': (g) => g['start'] = ['collect', 5],
        'types: expected an object': (g) => g['types'] = ['Change'],
        'types.Change: expected a schema (an object or a boolean)': (g) =>
            (g['types'] as Map<String, Object?>)['Change'] = 'object',
        'nodes: expected an object': (g) => g['nodes'] = ['collect'],
        'nodes.fix: expected an object': (g) =>
            (g['nodes'] as Map<String, Object?>)['fix'] = 'nodes/fix/run.sh',
        'nodes.inspect.command: expected a string': (g) =>
            nodeOf(g, 'inspect')['command'] = ['nodes/inspect/run.sh'],
        'nodes.verdict.decide: expected a string': (g) =>
            nodeOf(g, 'verdict')['decide'] = true,
        'nodes.inspect.in: expected a schema (an object or a boolean)': (g) =>
            nodeOf(g, 'inspect')['in'] = '#/Change',
        'nodes.inspect.out: expected a schema (an object or a boolean)': (g) =>
            nodeOf(g, 'inspect')['out'] = null,
        'nodes.inspect.then: expected a node name or a list of node names': (
          g,
        ) => nodeOf(g, 'inspect')['then'] = {'ok': 'verdict'},
        'nodes.verdict.then: expected a node name, a list of node names '
            'or a map of outcomes to targets': (g) =>
            nodeOf(g, 'verdict')['then'] = 1,
        'nodes.verdict.then.accepted[1]: expected a node name': (g) =>
            nodeOf(g, 'verdict')['then'] = {
              'accepted': ['publish', 7],
            },
        'nodes.is-empty.else: expected a node name or a list of node names': (
          g,
        ) => nodeOf(g, 'is-empty')['else'] = false,
      };
      for (final MapEntry(key: error, value: spoil) in cases.entries) {
        final graph = readmeGraph();
        spoil(graph);
        expect(checkGraph(graph), [error], reason: error);
      }
    });

    test('names and commands are not empty', () {
      final cases = <String, void Function(Map<String, Object?>)>{
        'start: is empty': (g) => g['start'] = '',
        'start[0]: is empty': (g) => g['start'] = ['', 'collect'],
        'nodes.inspect.command: is empty': (g) =>
            nodeOf(g, 'inspect')['command'] = '',
        'nodes.verdict.decide: is empty': (g) =>
            nodeOf(g, 'verdict')['decide'] = '',
        'nodes.verdict.then.returned: is empty': (g) =>
            nodeOf(g, 'verdict')['then'] = {'returned': ''},
      };
      for (final MapEntry(key: error, value: spoil) in cases.entries) {
        final graph = readmeGraph();
        spoil(graph);
        expect(checkGraph(graph), [error], reason: error);
      }
    });

    test('a list index is not mistaken for a key that looks like one', () {
      final graph = readmeGraph();
      nodeOf(graph, 'verdict')['then'] = {'0': 5};
      expect(checkGraph(graph), [
        'nodes.verdict.then.0: expected a node name or a list of node names',
      ]);
    });

    test('every broken node has a line of its own, in graph order', () {
      final graph = readmeGraph();
      nodeOf(graph, 'notify')['command'] = 5;
      nodeOf(graph, 'collect')['thn'] = 'is-empty';
      (graph['nodes'] as Map<String, Object?>)['fix'] = null;
      expect(checkGraph(graph), [
        'nodes.collect: unknown key "thn"',
        'nodes.fix: expected an object',
        'nodes.notify.command: expected a string',
      ]);
    });

    test('a problem outside the nodes stops the check at it', () {
      // ack meets the broken node first: the graph's keys come in this order.
      final broken = readmeGraph()..['extra'] = true;
      nodeOf(broken, 'collect')['thn'] = 'is-empty';
      expect(checkGraph(broken), ['graph: unknown key "extra"']);
      final badTypes = json({
        'start': 'a',
        'nodes': {
          'a': {'command': 5},
        },
        'types': {'Change': 'object'},
      });
      expect(checkGraph(badTypes), [
        'types.Change: expected a schema (an object or a boolean)',
      ]);
    });

    test('a structural problem hides the problems of meaning', () {
      final graph = readmeGraph()..['start'] = 'nowhere';
      nodeOf(graph, 'fix')['thn'] = 'inspect';
      expect(checkGraph(graph), ['nodes.fix: unknown key "thn"']);
    });
  });

  group('meaning', () {
    test('a target names an existing node', () {
      expect(checkGraph(graphOf('a', {'a': worker('b')})), [
        'nodes.a.then: unknown node "b"',
      ]);
    });

    test('start names existing nodes', () {
      expect(checkGraph(graphOf('b', {'a': worker()})), [
        'start: unknown node "b"',
        'nodes.a: unreachable from start',
      ]);
      expect(checkGraph(graphOf(['a', 'b'], {'a': worker()})), [
        'start: unknown node "b"',
      ]);
    });

    test('a target nested in a switch map names an existing node', () {
      final graph = readmeGraph();
      nodeOf(graph, 'verdict')['then'] = {
        'accepted': ['publish', 'notfy'],
        'returned': 'fix',
      };
      expect(checkGraph(graph), [
        'nodes.verdict.then.accepted: unknown node "notfy"',
        'nodes.notify: unreachable from start',
      ]);
    });

    test('else names an existing node', () {
      expect(checkGraph(graphOf('f', {'f': fork([], 'x')})), [
        'nodes.f.else: unknown node "x"',
      ]);
    });

    test('a list of targets has no name twice', () {
      final graph = readmeGraph();
      nodeOf(graph, 'verdict')['then'] = {
        'accepted': ['publish', 'notify', 'publish', 'publish'],
        'returned': 'fix',
      };
      expect(checkGraph(graph), [
        'nodes.verdict.then.accepted: "publish" is listed more than once',
      ]);
      expect(checkGraph(graphOf(['a', 'a'], {'a': worker()})), [
        'start: "a" is listed more than once',
      ]);
    });

    test('a list of targets has more than one name', () {
      expect(
        checkGraph(
          graphOf(
            ['a'],
            {
              'a': worker(['b']),
              'b': worker(),
            },
          ),
        ),
        [
          'start: a list of one node; write "a" without a list',
          'nodes.a.then: a list of one node; write "b" without a list',
        ],
      );
    });

    test('an empty list is a target that ends the run', () {
      expect(
        checkGraph(
          graphOf('a', {
            'a': worker('f'),
            'f': fork('b', <String>[]),
            'b': worker(<String>[]),
          }),
        ),
        isEmpty,
      );
    });

    test('start is not empty', () {
      expect(checkGraph(graphOf(<String>[], {})), ['start: is empty']);
    });

    test('every node is reachable from start', () {
      expect(
        checkGraph(
          graphOf('a', {
            'lost': worker('a'),
            'a': worker(),
            'also-lost': worker(),
          }),
        ),
        [
          'nodes.lost: unreachable from start',
          'nodes.also-lost: unreachable from start',
        ],
      );
    });

    test('a node is reachable through else', () {
      expect(
        checkGraph(
          graphOf('f', {'f': fork('a', 'b'), 'a': worker(), 'b': worker()}),
        ),
        isEmpty,
      );
    });

    test('a node is reachable through a switch key', () {
      expect(
        checkGraph(
          graphOf('f', {
            'f': fork({
              'yes': 'a',
              'no': ['b', 'c'],
            }),
            'a': worker(),
            'b': worker(),
            'c': worker('f'),
          }),
        ),
        isEmpty,
      );
    });

    test('a node is reachable from any start node', () {
      expect(
        checkGraph(
          graphOf(['a', 'b'], {'a': worker(), 'b': worker('c'), 'c': worker()}),
        ),
        isEmpty,
      );
    });

    test('errors follow the order of their places in the graph', () {
      final graph = graphOf(
        ['a', 'a', 'x'],
        {
          'a': worker(['y']),
          'lost': fork({
            'one': ['b', 'z', 'b'],
            'two': 'w',
          }, 'v'),
          'b': worker(),
        },
      );
      final expected = [
        'start: "a" is listed more than once',
        'start: unknown node "x"',
        'nodes.a.then: a list of one node; write "y" without a list',
        'nodes.a.then: unknown node "y"',
        'nodes.lost: unreachable from start',
        'nodes.lost.then.one: "b" is listed more than once',
        'nodes.lost.then.one: unknown node "z"',
        'nodes.lost.then.two: unknown node "w"',
        'nodes.lost.else: unknown node "v"',
        'nodes.b: unreachable from start',
      ];
      expect(checkGraph(graph), expected);
      expect(checkGraph(graph), expected);
    });
  });
}
