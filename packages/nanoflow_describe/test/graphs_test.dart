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

Map<String, Object?> _edge(String? from, String? to, [String? label]) => {
  'from': from,
  'to': to,
  'label': label,
};

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

Map<String, Object?> _warning(int line, String message) => {
  'place': 'lib/graph_warnings.dart:$line',
  'message': message,
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
  test(
    'draws graphs of nodes: effects at their first mention, forks for '
    'switch and ?:, edges for sets and null, joins, a graph as a call',
    () async {
      final graph = await describeFixture('graphs');
      expectFile(
        graph,
        await expectedFile(
          'graphs',
          workflows: ['$_file#review', '$_file#reviewed'],
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
                _effect('1', 'fix', 88),
                _effect('2', 'inspect', 90, doc: _inspectDoc),
                _fork('3', 'report.findings == 0', 97),
                _fork('4', 'switch (report.verdict)', 98),
                _effect('5', 'giveUp', 104),
              ],
              [
                _edge(null, '1'),
                _edge('1', '2'),
                _edge('2', '3'),
                _edge('3', null, 'true'),
                _edge('3', '4', 'false'),
                _edge('4', '1', 'Verdict.retry'),
                _edge('4', '5', 'Verdict.fail'),
                _edge('4', null, 'Verdict.pass'),
                _edge('5', null),
              ],
              doc: _polishDoc,
            ),
            '$_file#review': _function(
              'review',
              67,
              [
                _effect('1', 'collect', 68, doc: _collectDoc),
                _fork('2', 'switch (collected)', 69),
                _effect('3', 'discard', 70),
                _effect('4', 'inspect', 74, doc: _inspectDoc),
                _fork('5', 'report.findings == 0', 78),
                _effect('6', 'publish', 79),
                _effect('7', 'notify', 79),
                _call('8', 'polish', 80),
                _effect('9', 'summarize', 83),
              ],
              [
                _edge(null, '1'),
                _edge('1', '2'),
                _edge('2', '3', 'Empty'),
                _edge('2', '3', "Found when change.path.endsWith('.md')"),
                _edge('2', '4', 'Found'),
                _edge('3', null),
                _edge('4', '5'),
                _edge('5', '6', 'true'),
                _edge('5', '7', 'true'),
                _edge('5', '8', 'false'),
                _edge('6', '9'),
                _edge('7', '9'),
                _edge('8', '6'),
                _edge('8', '7'),
                _edge('9', null),
              ],
              doc: _reviewDoc,
            ),
            '$_file#reviewed': _function(
              'reviewed',
              121,
              [_effect('1', 'check', 122), _call('2', 'review', 123)],
              [_edge(null, '1'), _edge('1', '2'), _edge('2', null)],
            ),
          },
        ),
      );
    },
  );

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

  test('warns', () async {
    final graph = await describeFixture('graph_warnings');
    expect(graph['warnings'], [
      _warning(32, 'a node outside a top-level variable is not drawn'),
      _warning(34, 'a graph outside a top-level variable is not drawn'),
      _warning(38, 'node name is not a string literal'),
      _warning(42, 'graph name is not a string literal'),
      _warning(46, 'two nodes are named check in graph twins'),
      _warning(51, 'route not drawn: check'),
      _warning(52, 'route value not drawn: [done(report)]'),
      _warning(57, 'left cannot be reached'),
      _warning(
        63,
        'the route of the join takes (String, String), not the record of its '
        "nodes' outputs",
      ),
      _warning(68, 'side effect outside an effect: DateTime.now()'),
      _warning(
        71,
        'graph fanned is a node and can end in several ends at once',
      ),
      _warning(
        75,
        'graph started is a node and can end in several ends at once',
      ),
      _warning(88, 'graph part not drawn: aPart'),
      _warning(
        94,
        'graph name twin is also the name of lib/graph_warnings.dart#twin',
      ),
      _warning(
        97,
        'route is async or a generator: (change) async => check(change)',
      ),
      _warning(
        98,
        'route is async or a generator: (report) sync* {yield done(report);}',
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
}
