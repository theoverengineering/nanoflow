// Graphs of nodes in the graph file (graph design §9): each a function whose
// body is drawn with the nodes a workflow function's is.

import 'package:test/test.dart';

import 'support.dart';

const _file = 'lib/graphs.dart';

Map<String, Object?> _effect(String id, String name, int line) => {
  'id': id,
  'kind': 'effect',
  'name': name,
  'place': '$_file:$line',
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

void main() {
  test('draws graphs with the nodes of functions: effects, forks for maps, '
      'calls of graphs and workflow functions', () async {
    final graph = await describeFixture('graphs');
    expectFile(
      graph,
      await expectedFile(
        'graphs',
        workflows: ['$_file#callsGraph', '$_file#review'],
        functions: {
          '$_file#callsGraph': _function(
            'callsGraph',
            105,
            [_effect('1', 'check', 106), _call('2', 'nested', 107)],
            [_edge(null, '1'), _edge('1', '2'), _edge('2', null)],
          ),
          '$_file#judged': _function(
            'judged',
            88,
            [
              _call('1', 'prepare', 88),
              _effect('2', 'judge', 88),
              _fork('3', 'switch (judge)', 90),
              _effect('4', 'accept', 88),
            ],
            [
              _edge(null, '1'),
              _edge('1', '2'),
              _edge('2', '3'),
              _edge('3', '4', 'Verdict.pass'),
              _edge('3', null, 'otherwise'),
              _edge('4', null),
            ],
          ),
          '$_file#measured': _function(
            'measured',
            93,
            [
              _effect('1', 'isLong', 93),
              _fork('2', 'switch (isLong)', 94),
              _effect('3', 'long', 93),
              _effect('4', 'retry', 93),
            ],
            [
              _edge(null, '1'),
              _edge('1', '2'),
              _edge('2', '3', 'true'),
              _edge('2', '4', 'otherwise'),
              _edge('3', null),
              _edge('4', null),
            ],
          ),
          '$_file#nested': _function(
            'nested',
            97,
            [_call('1', 'judged', 97), _call('2', 'measured', 97)],
            [_edge(null, '1'), _edge('1', '2'), _edge('2', null)],
          ),
          '$_file#plain': _function('plain', 75, [], [
            _edge(null, null),
          ], doc: 'A workflow function without effects as a node.'),
          '$_file#plainly': _function(
            'plainly',
            101,
            [_call('1', 'prepare', 101), _call('2', 'plain', 101)],
            [_edge(null, '1'), _edge('1', '2'), _edge('2', null)],
          ),
          '$_file#prepare': _function(
            'prepare',
            69,
            [_effect('1', 'locate', 70)],
            [_edge(null, '1'), _edge('1', null)],
            doc: 'A workflow function as a node.',
          ),
          '$_file#review': _function(
            'review',
            58,
            [
              _effect('1', 'collect', 58),
              _fork('2', 'switch (collect)', 59),
              _effect('3', 'discard', 58),
              _effect('4', 'inspect', 58),
              _fork('5', 'switch (inspect)', 60),
              _effect('6', 'publish', 58),
              _effect('7', 'notify', 58),
              _effect('8', 'fix', 58),
              _effect('9', 'report', 58),
            ],
            [
              _edge(null, '1'),
              _edge('1', '2'),
              _edge('2', '3', 'Empty'),
              _edge('2', '4', 'Found'),
              _edge('4', '5'),
              _edge('5', '6', 'Clean'),
              _edge('5', '7', 'Clean'),
              _edge('5', '8', 'Findings'),
              _edge('8', '4'),
              _edge('6', '9'),
              _edge('7', '9'),
              _edge('3', null),
              _edge('9', null),
            ],
          ),
        },
      ),
    );
  });
}
