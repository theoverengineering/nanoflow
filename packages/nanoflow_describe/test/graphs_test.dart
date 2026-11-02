// Graphs of nodes in the graph file (graph node objects design §8–§9): each
// a function whose body has an effect for each node, where the graph first
// names it, a call for each graph that is a node, and the forks and edges of
// its routes.

import 'package:test/test.dart';

import 'support.dart';

const _file = 'lib/graphs.dart';

Map<String, Object?> _effect(String id, String name, int line, {String? doc}) =>
    {
      'id': id,
      'kind': 'effect',
      'name': name,
      'place': '$_file:$line',
      'doc': doc,
    };

Map<String, Object?> _fork(String id, String label, int line) => {
  'id': id,
  'kind': 'fork',
  'label': label,
  'place': '$_file:$line',
};

Map<String, Object?> _call(String id, String function, int line) => {
  'id': id,
  'kind': 'call',
  'functions': ['$_file#$function'],
  'place': '$_file:$line',
};

Map<String, Object?> _edge(
  String? from,
  String? to, [
  String? label,
  String? each,
]) => {'from': from, 'to': to, 'label': label, 'each': ?each};

Map<String, Object?> _function(
  String name,
  int line,
  List<Map<String, Object?>> nodes,
  List<Map<String, Object?>> edges, {
  String? doc,
}) => {
  'name': name,
  'place': '$_file:$line',
  'doc': doc,
  'body': {'nodes': nodes, 'edges': edges},
};

/// A warning of lib/graph_warnings.dart, in the declaration of the graph
/// [function] — its variable —, or of none.
Map<String, Object?> _warning(int line, String message, [String? function]) => {
  'place': 'lib/graph_warnings.dart:$line',
  'message': message,
  'function': function == null ? null : 'lib/graph_warnings.dart#$function',
};

/// The function [id] of the graph file [graph].
Map<String, Object?> _functionOf(Map<String, Object?> graph, String id) =>
    (graph['functions']! as Map<String, Object?>)[id]! as Map<String, Object?>;

/// The effect nodes of the function [id] of [graph].
List<Map<String, Object?>> _effectsOf(Map<String, Object?> graph, String id) =>
    [
      for (final node
          in ((_functionOf(graph, id)['body']! as Map)['nodes']! as List))
        if (node case {'kind': 'effect'}) node as Map<String, Object?>,
    ];

const _collectDoc =
    'The change of the branch, or Empty when it changes nothing.';
const _inspectDoc = 'What is wrong with the change.';
const _reviewDoc = 'Reviews the change of a branch.';
const _polishDoc =
    'Fixes a change until its report has no findings, or gives up.';

void main() {
  test('draws graphs of nodes: effects at their first mention, the switch, ?: '
      'or if a route decides by first as its node\'s exits, a fork for a later '
      'switch, edges for sets and null, joins, a graph as a call', () async {
    final graph = await describeFixture('graphs');
    expectFile(
      graph,
      expectedGraphs(
        functions: {
          '$_file#announce': _function(
            'announce',
            112,
            [_effect('1', 'publish', 113), _effect('2', 'notify', 114)],
            [
              _edge(null, '1'),
              _edge(null, '2'),
              _edge('1', null),
              _edge('2', null),
            ],
          ),
          '$_file#polish': _function(
            'polish',
            87,
            [
              // The ?: of fix's route goes to inspect either way: an arrow.
              _effect('1', 'fix', 88),
              // The if inspect's route decides by first is inspect's own
              // exits; the switch in its else is a fork.
              _effect('2', 'inspect', 90, doc: _inspectDoc),
              _fork('3', 'switch (report.verdict)', 98),
              _effect('4', 'giveUp', 104),
            ],
            [
              _edge(null, '1'),
              _edge('1', '2'),
              _edge('2', null, 'report.findings == 0'),
              _edge('2', '3', 'else'),
              _edge('3', '1', 'Verdict.retry'),
              _edge('3', '4', 'Verdict.fail'),
              _edge('3', null, 'Verdict.pass'),
              _edge('4', null),
            ],
            doc: _polishDoc,
          ),
          '$_file#review': _function(
            'review',
            67,
            [
              // The switch collect's route decides by first is collect's own
              // exits, no fork.
              _effect('1', 'collect', 68, doc: _collectDoc),
              _effect('2', 'discard', 70),
              // So is the ?: of inspect's: its condition and else.
              _effect('3', 'inspect', 74, doc: _inspectDoc),
              _effect('4', 'publish', 79),
              _effect('5', 'notify', 79),
              _call('6', 'polish', 80),
              _effect('7', 'summarize', 83),
            ],
            [
              _edge(null, '1'),
              _edge('1', '2', 'Empty'),
              _edge('1', '2', "Found when change.path.endsWith('.md')"),
              _edge('1', '3', 'Found'),
              _edge('2', null),
              _edge('3', '4', 'report.findings == 0'),
              _edge('3', '5', 'report.findings == 0'),
              _edge('3', '6', 'else'),
              _edge('4', '7'),
              _edge('5', '7'),
              _edge('6', '4'),
              _edge('6', '5'),
              _edge('7', null),
            ],
            doc: _reviewDoc,
          ),
        },
      ),
    );
  });

  test('draws a for element of a set as an edge to the node it runs once per '
      "item, marked with the loop's header, without a fork (each-edge "
      'design)', () async {
    const file = 'lib/graph_sets.dart';
    final graph = await describeFixture('graph_sets');

    Map<String, Object?> body(String name) =>
        _functionOf(graph, '$file#$name')['body']! as Map<String, Object?>;
    Map<String, Object?> at(Map<String, Object?> node, int line) => {
      ...node,
      'place': '$file:$line',
    };

    expect(body('fan'), {
      'nodes': [
        at(_effect('1', 'split', 0), 12),
        at(_effect('2', 'work', 0), 13),
      ],
      'edges': [
        _edge(null, '1'),
        _edge('1', null, 'items.isEmpty'),
        _edge('1', '2', 'else', 'for item in items'),
        _edge('2', null),
      ],
    });
    expect(body('count'), {
      'nodes': [
        at(_effect('1', 'first', 0), 18),
        at(_effect('2', 'skip', 0), 20),
        at(_effect('3', 'work', 0), 21),
      ],
      'edges': [
        _edge(null, '1'),
        _edge('1', '2'),
        _edge('1', '3', null, 'for (var i = 0; i < n; i++)'),
        _edge('2', null),
        _edge('3', null),
      ],
    });
    // Once or once per item: the if decides something, though both go to
    // work.
    expect(body('either'), {
      'nodes': [
        at(_effect('1', 'first', 0), 30),
        at(_effect('2', 'work', 0), 32),
      ],
      'edges': [
        _edge(null, '1'),
        _edge('1', '2', 'n > 0'),
        _edge('1', '2', 'else', 'for i in [n, n]'),
        _edge('2', null),
      ],
    });
    expect(graph['warnings'], [
      {
        'place': '$file:22',
        'message':
            'route value not drawn: for (final i in [n]) if (i > 0) '
            'work(i)',
        'function': '$file#count',
      },
    ]);
  });

  test('draws the if or ?: a route decides by first as its node\'s exits, '
      'the condition and else, and those its else decides by as more of '
      'them', () async {
    const file = 'lib/graph_ifs.dart';
    final graph = await describeFixture('graph_ifs');

    Map<String, Object?> body(String name) =>
        _functionOf(graph, '$file#$name')['body']! as Map<String, Object?>;
    Map<String, Object?> at(Map<String, Object?> node, int line) => {
      ...node,
      'place': '$file:$line',
    };

    // An else-if chain: an exit for each condition, in order, and else.
    Map<String, Object?> sizes(int start, int small, int big, int huge) => {
      'nodes': [
        at(_effect('1', 'read', 0), start),
        at(_effect('2', 'small', 0), small),
        at(_effect('3', 'big', 0), big),
        at(_effect('4', 'huge', 0), huge),
      ],
      'edges': [
        _edge(null, '1'),
        _edge('1', '2', 'n < 10'),
        _edge('1', '3', 'n < 100'),
        _edge('1', '4', 'else'),
        _edge('2', null),
        _edge('3', null),
        _edge('4', null),
      ],
    };
    expect(body('sizes'), sizes(20, 22, 24, 26));
    expect(body('chained'), sizes(32, 34, 36, 37));
    // With no else, else goes where the code after the if does.
    expect(body('returns'), {
      'nodes': [
        at(_effect('1', 'read', 0), 42),
        at(_effect('2', 'small', 0), 43),
        at(_effect('3', 'big', 0), 44),
      ],
      'edges': [
        _edge(null, '1'),
        _edge('1', '2', 'n < 10'),
        _edge('1', '3', 'n < 100'),
        _edge('1', null, 'else'),
        _edge('2', null),
        _edge('3', null),
      ],
    });
    expect(body('cases'), {
      'nodes': [
        at(_effect('1', 'write', 0), 50),
        at(_effect('2', 'skip', 0), 51),
      ],
      'edges': [
        _edge(null, '1'),
        _edge('1', '2', "draft case Draft(text: '')"),
        _edge('1', null, 'else'),
        _edge('2', null),
      ],
    });
    // A ?: the condition's way decides by is a fork.
    expect(body('nested'), {
      'nodes': [
        at(_effect('1', 'read', 0), 57),
        at(_fork('2', 'n < 5', 0), 57),
        at(_effect('3', 'small', 0), 57),
        at(_effect('4', 'big', 0), 57),
        at(_effect('5', 'huge', 0), 57),
      ],
      'edges': [
        _edge(null, '1'),
        _edge('1', '2', 'n < 10'),
        _edge('1', '5', 'else'),
        _edge('2', '3', 'true'),
        _edge('2', '4', 'false'),
        _edge('3', null),
        _edge('4', null),
        _edge('5', null),
      ],
    });
    expect(graph['warnings'], isEmpty);
  });

  test('draws no default for a route\'s switch on a record of types a switch '
      'must cover, and one for a record it need not; reads block doc '
      'comments', () async {
    const file = 'lib/graph_corners.dart';
    final graph = await describeFixture('graph_corners');

    Map<String, Object?> body(String name) =>
        _functionOf(graph, '$file#$name')['body']! as Map<String, Object?>;
    Map<String, Object?> at(Map<String, Object?> node, int line) => {
      ...node,
      'place': '$file:$line',
    };
    const receiveDoc = 'Takes an alert in.';
    const pageDoc = 'Pages someone.\n\nOnly when it is urgent.';

    expect(body('route'), {
      'nodes': [
        at(_effect('1', 'receive', 0, doc: receiveDoc), 36),
        at(_effect('2', 'page', 0, doc: pageDoc), 39),
        // An empty block comment is no doc, and no trouble.
        at(_effect('3', 'mail', 0), 41),
        at(_effect('4', 'log', 0), 43),
        at(_effect('5', 'chat', 0), 45),
      ],
      'edges': [
        _edge(null, '1'),
        _edge('1', '2', '(true, _)'),
        _edge('1', '3', '(false, (Speed.slow, _))'),
        _edge('1', '4', '(false, (Speed.fast, true))'),
        _edge('1', '5', '(false, (Speed.fast, false))'),
        _edge('2', null),
        _edge('3', null),
        _edge('4', null),
        _edge('5', null),
      ],
    });
    expect(body('retry'), {
      'nodes': [
        at(_effect('1', 'receive', 0, doc: receiveDoc), 52),
        at(_effect('2', 'page', 0, doc: pageDoc), 55),
        at(_effect('3', 'mail', 0), 57),
      ],
      'edges': [
        _edge(null, '1'),
        _edge('1', '2', '(true, _)'),
        _edge('1', '3', '(false, 0)'),
        _edge('1', null, 'default'),
        _edge('2', null),
        _edge('3', null),
      ],
    });
    expect(graph['warnings'], isEmpty);
  });

  test('the same node in two graphs has a place of its own in each', () async {
    final graph = await describeFixture('graphs');
    String? placeOf(String id, String name) =>
        _effectsOf(
              graph,
              '$_file#$id',
            ).singleWhere((effect) => effect['name'] == name)['place']
            as String?;
    expect(placeOf('review', 'inspect'), '$_file:74');
    expect(placeOf('polish', 'inspect'), '$_file:90');
  });

  test('gives nodes and graphs the doc comment over their variable', () async {
    final graph = await describeFixture('graphs');
    expect(_functionOf(graph, '$_file#review')['doc'], _reviewDoc);
    expect(_functionOf(graph, '$_file#polish')['doc'], _polishDoc);
    Map<Object?, Object?> docsOf(String id) => {
      for (final effect in _effectsOf(graph, '$_file#$id'))
        effect['name']: effect['doc'],
    };
    expect(docsOf('review'), {
      'collect': _collectDoc,
      'discard': null,
      'inspect': _inspectDoc,
      'publish': null,
      'notify': null,
      'summarize': null,
    });
    expect(docsOf('polish'), {
      'fix': null,
      'inspect': _inspectDoc,
      'giveUp': null,
    });
  });

  test('warns, of the graph whose declaration each warning is in', () async {
    final graph = await describeFixture('graph_warnings');
    expect(graph['warnings'], [
      // In functions, and in a node's declaration: no graph.
      _warning(32, 'a node outside a top-level variable is not drawn'),
      _warning(34, 'a graph outside a top-level variable is not drawn'),
      _warning(38, 'node name is not a string literal'),
      _warning(42, 'graph name is not a string literal', 'namedGraph'),
      _warning(46, 'two nodes are named check in graph twins', 'twins'),
      _warning(51, 'route not drawn: check', 'unread'),
      _warning(52, 'route value not drawn: [done(report)]', 'unread'),
      _warning(57, 'left cannot be reached', 'orphaned'),
      _warning(
        63,
        'the route of the join takes (String, String), not the record of its '
            "nodes' outputs",
        'joined',
      ),
      _warning(68, 'side effect outside an effect: DateTime.now()', 'timed'),
      _warning(
        71,
        'graph fanned is a node and can end in several ends at once',
        'fanned',
      ),
      _warning(
        75,
        'graph started is a node and can end in several ends at once',
        'started',
      ),
      _warning(88, 'graph part not drawn: aPart', 'indirect'),
      // Graphs of one name: each warns of the other.
      _warning(
        90,
        'graph name twin is also the name of '
            'lib/graph_warnings.dart#twinGraph',
        'twin',
      ),
      _warning(
        94,
        'graph name twin is also the name of lib/graph_warnings.dart#twin',
        'twinGraph',
      ),
      _warning(
        97,
        'route is async or a generator: (change) async => check(change)',
        'awaited',
      ),
      _warning(
        98,
        'route is async or a generator: (report) sync* {yield done(report);}',
        'awaited',
      ),
    ]);
    // A name that is not a literal is the name of the variable.
    final named = _functionOf(graph, 'lib/graph_warnings.dart#namedGraph');
    expect(named['name'], 'namedGraph');
    expect(_effectsOf(graph, 'lib/graph_warnings.dart#namedGraph'), [
      {
        'id': '1',
        'kind': 'effect',
        'name': 'named',
        'place': 'lib/graph_warnings.dart:42',
        'doc': null,
      },
    ]);
    // A node no way reaches is drawn still, with its arrows.
    expect(
      (_functionOf(graph, 'lib/graph_warnings.dart#orphaned')['body']!
          as Map)['edges'],
      [
        {'from': null, 'to': '1', 'label': null},
        {'from': '1', 'to': '2', 'label': null},
        {'from': '2', 'to': null, 'label': null},
        {'from': '3', 'to': null, 'label': null},
      ],
    );
    expect(
      _effectsOf(
        graph,
        'lib/graph_warnings.dart#orphaned',
      ).map((effect) => effect['name']),
      ['begin', 'check', 'left'],
    );
  });

  test('gives the edge of a call with a limit the limit as written, a '
      'literal or not, in a for element or not, of a graph or a node (call '
      'limit design)', () async {
    const file = 'lib/graph_limits.dart';
    final graph = await describeFixture('graph_limits');
    Map<String, Object?> at(Map<String, Object?> node, int line) => {
      ...node,
      'place': '$file:$line',
    };

    expect(_functionOf(graph, '$file#night')['body'], {
      'nodes': [
        at(_effect('1', 'plan', 0), 21),
        {
          'id': '2',
          'kind': 'call',
          'functions': ['$file#idea'],
          'place': '$file:23',
        },
        at(_effect('3', 'report', 0), 24),
        at(_effect('4', 'sum', 0), 27),
      ],
      'edges': [
        _edge(null, '1'),
        {
          ..._edge('1', '2', null, 'for i in night.ideas'),
          'limit': 'night.parallel',
        },
        {..._edge('1', '3', null, 'for i in night.ideas'), 'limit': '2'},
        {..._edge('2', '4'), 'limit': '1'},
        _edge('3', '4'),
        _edge('4', null),
      ],
    });
    // A fork whose ways lead to the same call with the same limit decides
    // nothing: one arrow, which keeps the limit.
    expect(_functionOf(graph, '$file#either')['body'], {
      'nodes': [
        at(_effect('1', 'develop', 0), 33),
        at(_effect('2', 'sum', 0), 33),
      ],
      'edges': [
        _edge(null, '1'),
        {..._edge('1', '2'), 'limit': '2'},
        _edge('2', null),
      ],
    });
    expect(_functionOf(graph, '$file#eitherOr')['body'], {
      'nodes': [
        at(_effect('1', 'develop', 0), 38),
        at(_effect('2', 'sum', 0), 38),
      ],
      'edges': [
        _edge(null, '1'),
        {..._edge('1', '2', 'i > 0'), 'limit': '2'},
        _edge('1', '2', 'else'),
        _edge('2', null),
      ],
    });
    expect(graph['warnings'], isEmpty);
  });

  test('gives an effect the concurrency of its node when it is an integer '
      'literal, and warns of one that is not', () async {
    const file = 'lib/graph_concurrency.dart';
    final graph = await describeFixture('graph_concurrency');
    expect(_effectsOf(graph, '$file#limited'), [
      {
        'id': '1',
        'kind': 'effect',
        'name': 'heavy',
        'place': '$file:12',
        'doc': null,
        'concurrency': 4,
      },
      {
        'id': '2',
        'kind': 'effect',
        'name': 'light',
        'place': '$file:12',
        'doc': null,
      },
      {
        'id': '3',
        'kind': 'effect',
        'name': 'counted',
        'place': '$file:13',
        'doc': null,
      },
    ]);
    expect(graph['warnings'], [
      {
        'place': '$file:9',
        'message': 'node concurrency is not an integer literal',
        'function': null,
      },
    ]);
  });
}
