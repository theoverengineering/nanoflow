import 'dart:convert';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:test/test.dart';

const String _review = 'lib/review.dart#review';
const String _publish = 'lib/release.dart#publish';

/// A graph file with every kind of node, `null` in every place that allows
/// it, and the keys in the order of the spec.
Map<String, Object?> _fileJson() => {
  'format': 1,
  'package': 'review_example',
  'fingerprint': 'sha256:7d3e',
  'sources': {'bin/main.dart': 'sha256:aa11', 'lib/review.dart': 'sha256:9f2c'},
  'builds': {'review': 'sha256:c07e'},
  'workflows': [_review],
  'functions': {
    _review: {
      'name': 'review',
      'place': 'lib/review.dart:21',
      'body': {
        'nodes': [
          {
            'id': '1',
            'kind': 'step',
            'name': 'collect',
            'place': 'lib/review.dart:22',
          },
          {
            'id': '2',
            'kind': 'fork',
            'label': 'change.path.isEmpty',
            'place': 'lib/review.dart:23',
          },
          {
            'id': '3',
            'kind': 'call',
            'functions': [_publish],
            'place': 'lib/review.dart:24',
          },
          {
            'id': '4',
            'kind': 'copies',
            'label': 'pkg in packages',
            'place': 'lib/review.dart:25',
            'body': {
              'nodes': [
                {'id': '1', 'kind': 'step', 'name': 'lint', 'place': null},
              ],
              'edges': [
                {'from': null, 'to': '1', 'label': null},
                {'from': '1', 'to': null, 'label': null},
              ],
            },
          },
        ],
        'edges': [
          {'from': null, 'to': '1', 'label': null},
          {'from': '1', 'to': '2', 'label': null},
          {'from': '2', 'to': '3', 'label': 'true'},
          {'from': '2', 'to': null, 'label': 'false'},
          {'from': '3', 'to': '4', 'label': null},
        ],
      },
    },
    _publish: {
      'name': 'publish',
      'place': null,
      'body': {'nodes': <Object?>[], 'edges': <Object?>[]},
    },
  },
  'warnings': [
    {
      'place': 'lib/review.dart:40',
      'message': 'steps in a closure passed on are not drawn',
    },
    {'place': null, 'message': 'a warning without a place'},
  ],
};

/// A deep copy of [_fileJson] with the value at [path] (map keys and list
/// indexes) replaced by [value], or removed when [remove] is set.
Map<String, Object?> _edited(
  List<Object> path, {
  Object? value,
  bool remove = false,
}) {
  final json = jsonDecode(jsonEncode(_fileJson())) as Map<String, Object?>;
  Object? parent = json;
  for (final step in path.take(path.length - 1)) {
    parent = parent is List ? parent[step as int] : (parent as Map)[step];
  }
  final last = path.last;
  if (parent is List) {
    parent[last as int] = value;
  } else if (remove) {
    (parent as Map).remove(last);
  } else {
    (parent as Map)[last] = value;
  }
  return json;
}

/// The message of the [FormatException] thrown by reading [json].
String _problem(Map<String, Object?> json) {
  try {
    GraphFile.fromJson(json);
  } on FormatException catch (e) {
    return e.message;
  }
  throw StateError('Expected a FormatException');
}

const List<Object> _body = ['functions', _review, 'body'];

/// A graph file whose workflows are [workflows], each with an empty graph.
GraphFile _fileWithWorkflows(List<String> workflows, [List<String>? others]) {
  GraphFunction function(String id) => GraphFunction(
    id: id,
    name: id.split(RegExp('[#.]')).last,
    place: null,
    body: const GraphBody(nodes: [], edges: []),
  );
  return GraphFile(
    format: 1,
    package: 'p',
    fingerprint: 'sha256:00',
    sources: const {},
    builds: const {},
    workflows: workflows,
    functions: {
      for (final id in [...workflows, ...?others]) id: function(id),
    },
    warnings: const [],
  );
}

void main() {
  test('names the file and its format', () {
    expect(graphFileName, 'nanoflow.graph.json');
    expect(graphFileFormat, 1);
  });

  group('GraphFile', () {
    test('round trips through JSON', () {
      final file = GraphFile.fromJson(_fileJson());
      expect(GraphFile.fromJson(file.toJson()), file);
      expect(jsonEncode(file.toJson()), jsonEncode(_fileJson()));
    });

    test('writes the keys in the order of the spec', () {
      final json = GraphFile.fromJson(_fileJson()).toJson();
      expect(json.keys, [
        'format',
        'package',
        'fingerprint',
        'sources',
        'builds',
        'workflows',
        'functions',
        'warnings',
      ]);
      final function = (json['functions'] as Map<String, Object?>)[_review];
      expect((function as Map<String, Object?>).keys, [
        'name',
        'place',
        'body',
      ]);
      final body = function['body'] as Map<String, Object?>;
      expect(body.keys, ['nodes', 'edges']);
      final nodes = body['nodes'] as List<Object?>;
      expect(
        [for (final n in nodes) (n as Map<String, Object?>).keys.toList()],
        [
          ['id', 'kind', 'name', 'place'],
          ['id', 'kind', 'label', 'place'],
          ['id', 'kind', 'functions', 'place'],
          ['id', 'kind', 'label', 'place', 'body'],
        ],
      );
      final edge = (body['edges'] as List<Object?>).first;
      expect((edge as Map<String, Object?>).keys, ['from', 'to', 'label']);
      final warning = (json['warnings'] as List<Object?>).first;
      expect((warning as Map<String, Object?>).keys, ['place', 'message']);
    });

    test('does not repeat the id inside a function', () {
      final file = GraphFile.fromJson(_fileJson());
      expect(file.functions[_review]!.id, _review);
      final json = file.toJson()['functions'] as Map<String, Object?>;
      expect(json.keys, [_review, _publish]);
      expect((json[_review] as Map<String, Object?>).containsKey('id'), false);
    });

    test('reads every kind of node', () {
      final body = GraphFile.fromJson(_fileJson()).functions[_review]!.body;
      expect(body.nodes, [
        const StepNode(id: '1', place: 'lib/review.dart:22', name: 'collect'),
        const ConditionNode(
          id: '2',
          place: 'lib/review.dart:23',
          label: 'change.path.isEmpty',
        ),
        const CallNode(
          id: '3',
          place: 'lib/review.dart:24',
          functions: [_publish],
        ),
        const CopiesNode(
          id: '4',
          place: 'lib/review.dart:25',
          label: 'pkg in packages',
          body: GraphBody(
            nodes: [StepNode(id: '1', place: null, name: 'lint')],
            edges: [
              GraphEdge(from: null, to: '1', label: null),
              GraphEdge(from: '1', to: null, label: null),
            ],
          ),
        ),
      ]);
    });

    test('keeps null in from, to, label and place', () {
      final file = GraphFile.fromJson(_fileJson());
      final edges = file.functions[_review]!.body.edges;
      expect(edges.first, const GraphEdge(from: null, to: '1', label: null));
      expect(edges[3], const GraphEdge(from: '2', to: null, label: 'false'));
      expect(file.functions[_publish]!.place, isNull);
      expect(file.warnings.last.place, isNull);
    });

    test('finds a node of a body by its id', () {
      final body = GraphFile.fromJson(_fileJson()).functions[_review]!.body;
      expect(body.node('2'), isA<ConditionNode>());
      expect((body.node('4') as CopiesNode).body.node('1'), isA<StepNode>());
      expect(body.node('9'), isNull);
    });

    test('compares by value, deeply', () {
      final file = GraphFile.fromJson(_fileJson());
      final same = GraphFile.fromJson(_fileJson());
      expect(same, file);
      expect(same.hashCode, file.hashCode);
      for (final changed in [
        _edited(['package'], value: 'other'),
        _edited(['fingerprint'], value: 'sha256:00'),
        _edited(['sources', 'bin/main.dart'], value: 'sha256:00'),
        _edited(['builds', 'review'], value: 'sha256:00'),
        _edited(['workflows', 0], value: _publish),
        _edited([..._body, 'nodes', 0, 'name'], value: 'other'),
        _edited([..._body, 'nodes', 1, 'label'], value: 'other'),
        _edited([..._body, 'nodes', 2, 'functions', 0], value: 'other'),
        _edited([..._body, 'nodes', 3, 'body', 'edges', 0, 'to'], value: '2'),
        _edited([..._body, 'nodes', 3, 'body', 'nodes', 0, 'name'], value: 'x'),
        _edited(['warnings', 0, 'message'], value: 'other'),
      ]) {
        expect(GraphFile.fromJson(changed), isNot(file), reason: '$changed');
      }
    });

    test('has a readable toString', () {
      final file = GraphFile.fromJson(_fileJson());
      expect(file.toString(), startsWith('GraphFile('));
      expect(file.toString(), contains('review_example'));
      expect(file.functions[_review]!.toString(), contains(_review));
      for (final node in file.functions[_review]!.body.nodes) {
        expect(node.toString(), contains(node.id));
      }
    });
  });

  group('GraphFile.fromJson problems', () {
    test('rejects a format other than 1', () {
      expect(_problem(_edited(['format'], value: 2)), startsWith('format:'));
      expect(_problem(_edited(['format'], value: 0)), startsWith('format:'));
    });

    test('names the top-level field that is missing or mistyped', () {
      expect(_problem(_edited(['format'], remove: true)), 'format: missing');
      expect(
        _problem(_edited(['format'], value: '1')),
        'format: expected an integer',
      );
      expect(
        _problem(_edited(['package'], value: 3)),
        'package: expected a string',
      );
      expect(
        _problem(_edited(['fingerprint'], remove: true)),
        'fingerprint: missing',
      );
      expect(
        _problem(_edited(['sources'], value: <Object?>[])),
        'sources: expected an object',
      );
      expect(_problem(_edited(['builds'], remove: true)), 'builds: missing');
      expect(
        _problem(_edited(['workflows'], value: <String, Object?>{})),
        'workflows: expected a list',
      );
      expect(
        _problem(_edited(['functions'], remove: true)),
        'functions: missing',
      );
      expect(
        _problem(_edited(['warnings'], value: 'none')),
        'warnings: expected a list',
      );
    });

    test('names the path of a bad entry of sources, builds and workflows', () {
      expect(
        _problem(_edited(['sources', 'lib/review.dart'], value: 1)),
        'sources.lib/review.dart: expected a string',
      );
      expect(
        _problem(_edited(['builds', 'review'], value: null)),
        'builds.review: expected a string',
      );
      expect(
        _problem(_edited(['workflows', 0], value: 7)),
        'workflows[0]: expected a string',
      );
    });

    test('names the path of an unknown kind of node', () {
      expect(
        _problem(_edited([..._body, 'nodes', 2, 'kind'], value: 'loop')),
        startsWith('functions.$_review.body.nodes[2].kind:'),
      );
      expect(
        _problem(_edited([..._body, 'nodes', 2, 'kind'], value: 'loop')),
        contains('loop'),
      );
      expect(
        _problem(_edited([..._body, 'nodes', 2, 'kind'], value: null)),
        'functions.$_review.body.nodes[2].kind: expected a string',
      );
    });

    test('names the path of a problem in a nested body', () {
      expect(
        _problem(
          _edited([
            ..._body,
            'nodes',
            3,
            'body',
            'nodes',
            0,
            'kind',
          ], value: 'loop'),
        ),
        startsWith('functions.$_review.body.nodes[3].body.nodes[0].kind:'),
      );
      expect(
        _problem(
          _edited([..._body, 'nodes', 3, 'body', 'edges', 1, 'to'], value: 1),
        ),
        'functions.$_review.body.nodes[3].body.edges[1].to: '
        'expected a string or null',
      );
      expect(
        _problem(_edited([..._body, 'nodes', 3, 'body'], value: 'none')),
        'functions.$_review.body.nodes[3].body: expected an object',
      );
    });

    test('names the field of a node that is missing or mistyped', () {
      const node = 'functions.$_review.body.nodes';
      expect(
        _problem(_edited([..._body, 'nodes', 0, 'name'], remove: true)),
        '$node[0].name: missing',
      );
      expect(
        _problem(_edited([..._body, 'nodes', 0, 'id'], value: 1)),
        '$node[0].id: expected a string',
      );
      expect(
        _problem(_edited([..._body, 'nodes', 1, 'place'], value: 1)),
        '$node[1].place: expected a string or null',
      );
      expect(
        _problem(_edited([..._body, 'nodes', 1, 'label'], remove: true)),
        '$node[1].label: missing',
      );
      expect(
        _problem(_edited([..._body, 'nodes', 2, 'functions'], value: 'f')),
        '$node[2].functions: expected a list',
      );
      expect(
        _problem(_edited([..._body, 'nodes', 2, 'functions', 0], value: 1)),
        '$node[2].functions[0]: expected a string',
      );
      expect(
        _problem(_edited([..._body, 'nodes', 3, 'body'], remove: true)),
        '$node[3].body: missing',
      );
      expect(
        _problem(_edited([..._body, 'nodes', 1], value: 'fork')),
        '$node[1]: expected an object',
      );
    });

    test('names the path of a function, an edge and a warning', () {
      expect(
        _problem(_edited(['functions', _review], value: 1)),
        'functions.$_review: expected an object',
      );
      expect(
        _problem(_edited(['functions', _review, 'name'], remove: true)),
        'functions.$_review.name: missing',
      );
      expect(
        _problem(_edited(['functions', _review, 'place'], value: 1)),
        'functions.$_review.place: expected a string or null',
      );
      expect(
        _problem(_edited([..._body, 'edges', 0, 'from'], value: 1)),
        'functions.$_review.body.edges[0].from: expected a string or null',
      );
      expect(
        _problem(_edited([..._body, 'edges', 0, 'label'], remove: true)),
        'functions.$_review.body.edges[0].label: missing',
      );
      expect(
        _problem(_edited(['warnings', 1, 'message'], remove: true)),
        'warnings[1].message: missing',
      );
      expect(
        _problem(_edited(['warnings', 0, 'place'], value: 1)),
        'warnings[0].place: expected a string or null',
      );
    });
  });

  group('GraphFile.workflowNamed', () {
    test('finds a function by the name after # or .', () {
      final file = _fileWithWorkflows(['lib/review.dart#review']);
      expect(file.workflowNamed('review')!.id, 'lib/review.dart#review');

      final method = _fileWithWorkflows(['lib/x.dart#Flows.review']);
      expect(method.workflowNamed('review')!.id, 'lib/x.dart#Flows.review');
      expect(
        method.workflowNamed('Flows.review')!.id,
        'lib/x.dart#Flows.review',
      );
    });

    test('does not match a name that only ends the same way', () {
      final file = _fileWithWorkflows([
        'lib/x.dart#reviewer',
        'lib/x.dart#prereview',
      ]);
      expect(file.workflowNamed('review'), isNull);
      expect(file.workflowNamed('view'), isNull);
      expect(file.workflowNamed('reviewer')!.id, 'lib/x.dart#reviewer');
    });

    test('picks the right one among several workflows', () {
      final file = _fileWithWorkflows([
        'lib/x.dart#reviewer',
        'lib/x.dart#Flows.review',
        'lib/review.dart#publish',
      ]);
      expect(file.workflowNamed('review')!.id, 'lib/x.dart#Flows.review');
    });

    test('looks only at the workflows, not at every function', () {
      final file = _fileWithWorkflows(
        ['lib/x.dart#review'],
        ['lib/y.dart#helper'],
      );
      expect(file.workflowNamed('helper'), isNull);
    });

    test('is null when a workflow has no function', () {
      final file = GraphFile(
        format: 1,
        package: 'p',
        fingerprint: 'sha256:00',
        sources: const {},
        builds: const {},
        workflows: const ['lib/x.dart#review'],
        functions: const {},
        warnings: const [],
      );
      expect(file.workflowNamed('review'), isNull);
    });
  });
}
