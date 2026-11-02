import 'dart:convert';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:test/test.dart';

const String _review = 'lib/review.dart#review';
const String _publish = 'lib/release.dart#publish';

/// A graph file with every kind of node, `null` in every place that allows
/// it, and the keys in the order of the spec.
Map<String, Object?> _fileJson() => {
  'format': 3,
  'package': 'review_example',
  'fingerprint': 'sha256:7d3e',
  'sources': {'bin/main.dart': 'sha256:aa11', 'lib/review.dart': 'sha256:9f2c'},
  'builds': {'review': 'sha256:c07e'},
  'workflows': [_review],
  'functions': {
    _review: {
      'name': 'review',
      'place': 'lib/review.dart:21',
      'doc': 'Reviews the change of [branch].\n\nEnds when it is clean.',
      'body': {
        'nodes': [
          {
            'id': '1',
            'kind': 'effect',
            'name': 'collect',
            'place': 'lib/review.dart:22',
            'doc': 'Takes the change of the branch.',
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
        ],
        'edges': [
          {'from': null, 'to': '1', 'label': null},
          {'from': '1', 'to': '2', 'label': null},
          {'from': '2', 'to': '3', 'label': 'true'},
          {'from': '2', 'to': null, 'label': 'false'},
          {'from': '3', 'to': null, 'label': null},
        ],
      },
    },
    _publish: {
      'name': 'publish',
      'place': null,
      'doc': null,
      'body': {'nodes': <Object?>[], 'edges': <Object?>[]},
    },
  },
  'warnings': [
    {
      'place': 'lib/review.dart:40',
      'message': 'effects in a closure passed on are not drawn',
      'function': _review,
    },
    {'place': null, 'message': 'a warning without a place', 'function': null},
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

/// [_fileJson] as format 2 has it, before `doc`: no `doc` on functions and
/// effects.
Map<String, Object?> _format2Json() {
  final json = jsonDecode(jsonEncode(_fileJson())) as Map<String, Object?>;
  json['format'] = 2;
  void strip(Object? value) {
    if (value is Map) {
      value.remove('doc');
      value.values.forEach(strip);
    } else if (value is List) {
      value.forEach(strip);
    }
  }

  strip(json['functions']);
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
    format: 3,
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
    expect(graphFileFormat, 3);
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
        'doc',
        'body',
      ]);
      final body = function['body'] as Map<String, Object?>;
      expect(body.keys, ['nodes', 'edges']);
      final nodes = body['nodes'] as List<Object?>;
      expect(
        [for (final n in nodes) (n as Map<String, Object?>).keys.toList()],
        [
          ['id', 'kind', 'name', 'place', 'doc'],
          ['id', 'kind', 'label', 'place'],
          ['id', 'kind', 'functions', 'place'],
        ],
      );
      final edge = (body['edges'] as List<Object?>).first;
      expect((edge as Map<String, Object?>).keys, ['from', 'to', 'label']);
      final warning = (json['warnings'] as List<Object?>).first;
      expect((warning as Map<String, Object?>).keys, [
        'place',
        'message',
        'function',
      ]);
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
        const EffectNode(
          id: '1',
          place: 'lib/review.dart:22',
          name: 'collect',
          doc: 'Takes the change of the branch.',
        ),
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

    test("reads an edge's each, writes it only when set, and none from an "
        'edge written before edges had one', () {
      const copies = GraphEdge(
        from: '2',
        to: '3',
        label: 'else',
        each: 'for item in items',
      );
      expect(copies.toJson(), {
        'from': '2',
        'to': '3',
        'label': 'else',
        'each': 'for item in items',
      });
      expect(GraphEdge.fromJson(copies.toJson()), copies);
      const once = GraphEdge(from: '2', to: '3', label: 'else');
      expect(once.toJson(), {'from': '2', 'to': '3', 'label': 'else'});
      expect(GraphEdge.fromJson(once.toJson()).each, isNull);
      expect(copies, isNot(once));
      expect(copies.toString(), contains('each: for item in items'));
    });

    test("reads an edge's limit, writes it only when set, and none from an "
        'edge written before edges had one', () {
      const limited = GraphEdge(
        from: '2',
        to: '3',
        label: null,
        each: 'for idea in night.ideas',
        limit: 'night.parallel',
      );
      expect(limited.toJson(), {
        'from': '2',
        'to': '3',
        'label': null,
        'each': 'for idea in night.ideas',
        'limit': 'night.parallel',
      });
      expect(GraphEdge.fromJson(limited.toJson()), limited);
      const once = GraphEdge(from: '2', to: '3', label: null, limit: '2');
      expect(once.toJson(), {
        'from': '2',
        'to': '3',
        'label': null,
        'limit': '2',
      });
      expect(GraphEdge.fromJson(once.toJson()), once);
      const free = GraphEdge(from: '2', to: '3', label: null);
      expect(GraphEdge.fromJson(free.toJson()).limit, isNull);
      expect(once, isNot(free));
      expect(once.hashCode, isNot(free.hashCode));
      expect(limited.toString(), contains('limit: night.parallel'));
      expect(free.toString(), isNot(contains('limit')));
    });

    test('reads whether an edge is of a failure route, writes it only when it '
        'is, and none from an edge written before edges could be', () {
      const failed = GraphEdge(
        from: '2',
        to: '3',
        label: 'failed',
        limit: '2',
        failed: true,
      );
      expect(failed.toJson(), {
        'from': '2',
        'to': '3',
        'label': 'failed',
        'limit': '2',
        'failed': true,
      });
      expect(GraphEdge.fromJson(failed.toJson()), failed);
      // A case of a switch with the same text is another edge.
      const labelled = GraphEdge(
        from: '2',
        to: '3',
        label: 'failed',
        limit: '2',
      );
      expect(labelled.toJson(), isNot(contains('failed')));
      expect(labelled.failed, isFalse);
      expect(GraphEdge.fromJson(labelled.toJson()), labelled);
      expect(failed, isNot(labelled));
      expect(failed.hashCode, isNot(labelled.hashCode));
      expect(failed.toString(), contains('failed: true'));
      expect(labelled.toString(), isNot(contains('failed: ')));
      expect(
        GraphEdge.fromJson(const {'from': '2', 'to': '3', 'label': null})
            .failed,
        isFalse,
      );
    });

    test('reads the function of a warning, and none from a warning written '
        'before warnings had one', () {
      final file = GraphFile.fromJson(_fileJson());
      expect(file.warnings.first.function, _review);
      expect(file.warnings.last.function, isNull);
      final before = GraphFile.fromJson(
        _edited(['warnings', 0, 'function'], remove: true),
      );
      expect(before.warnings.first.function, isNull);
      expect(before.warnings.first.message, file.warnings.first.message);
    });

    test('reads the doc of a function and of an effect', () {
      final file = GraphFile.fromJson(_fileJson());
      final review = file.functions[_review]!;
      expect(
        review.doc,
        'Reviews the change of [branch].\n\nEnds when it is clean.',
      );
      expect(file.functions[_publish]!.doc, isNull);
      expect((review.body.node('1')! as EffectNode).doc, startsWith('Takes'));
      expect(review.toString(), contains('Reviews the change'));
      expect(review.body.node('1').toString(), contains('Takes the change'));
    });

    test('reads and writes an effect concurrency, absent when not set', () {
      const limited = EffectNode(
        id: '1',
        place: null,
        name: 'x',
        concurrency: 4,
      );
      expect(limited.toJson()['concurrency'], 4);
      expect(GraphNode.fromJson(limited.toJson()), limited);
      const free = EffectNode(id: '1', place: null, name: 'x');
      expect(free.toJson().containsKey('concurrency'), isFalse);
      expect(
        GraphNode.fromJson({
          'id': '1',
          'kind': 'effect',
          'name': 'x',
          'place': null,
          'doc': null,
        }),
        free,
      );
      expect(limited, isNot(free));
      expect('$limited', contains('concurrency: 4'));
    });

    test('names a concurrency that is not an integer', () {
      expect(
        () => GraphNode.fromJson({
          'id': '1',
          'kind': 'effect',
          'name': 'x',
          'place': null,
          'doc': null,
          'concurrency': '4',
        }),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('concurrency'),
          ),
        ),
      );
    });

    test('reads format 2, from before docs, with no docs', () {
      final file = GraphFile.fromJson(_format2Json());
      final docless = GraphFile.fromJson(
        _edited(['functions', _review, 'doc'], value: null),
      );
      expect(file.format, 3);
      expect(file.functions[_review]!.doc, isNull);
      final body = file.functions[_review]!.body;
      expect((body.node('1')! as EffectNode).doc, isNull);
      expect(
        file.functions[_review]!.body.nodes.skip(1),
        docless.functions[_review]!.body.nodes.skip(1),
      );
      expect(file.warnings, docless.warnings);
    });

    test('writes format 2 back as format 3, with doc null', () {
      final json = GraphFile.fromJson(_format2Json()).toJson();
      expect(json['format'], 3);
      final function = (json['functions']! as Map)[_review] as Map;
      expect(function.containsKey('doc'), isTrue);
      expect(function['doc'], isNull);
    });

    test('finds a node of a body by its id', () {
      final body = GraphFile.fromJson(_fileJson()).functions[_review]!.body;
      expect(body.node('2'), isA<ConditionNode>());
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
        _edited([..._body, 'nodes', 0, 'doc'], value: 'other'),
        _edited(['functions', _review, 'doc'], value: null),
        _edited([..._body, 'nodes', 1, 'label'], value: 'other'),
        _edited([..._body, 'nodes', 2, 'functions', 0], value: 'other'),
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
    test('rejects a format other than 2 and 3', () {
      expect(
        _problem(_edited(['format'], value: 4)),
        'format: expected 3, the file is 4',
      );
      expect(
        _problem(_edited(['format'], value: 0)),
        'format: expected 3, the file is 0',
      );
    });

    test('refuses a graph file of format 1, from before effects', () {
      expect(
        _problem(_edited(['format'], value: 1)),
        'format: expected 3, the file is 1',
      );
    });

    test('names the doc of format 3 that is missing or mistyped', () {
      expect(
        _problem(_edited([..._body, 'nodes', 0, 'doc'], remove: true)),
        'functions.$_review.body.nodes[0].doc: missing',
      );
      expect(
        _problem(_edited(['functions', _review, 'doc'], value: 1)),
        'functions.$_review.doc: expected a string or null',
      );
    });

    test('names the path of a problem in a format-2 file', () {
      final json = _format2Json();
      ((json['functions']! as Map)[_review] as Map).remove('name');
      expect(_problem(json), 'functions.$_review.name: missing');
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
      expect(
        _problem(_edited(['warnings', 0, 'function'], value: 1)),
        'warnings[0].function: expected a string or null',
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

    test('finds a graph by its name, which need not end its id', () {
      final file = GraphFile(
        format: 2,
        package: 'p',
        fingerprint: 'sha256:00',
        sources: const {},
        builds: const {},
        workflows: const ['lib/g.dart#reviewGraph'],
        functions: const {
          'lib/g.dart#reviewGraph': GraphFunction(
            id: 'lib/g.dart#reviewGraph',
            name: 'review',
            place: 'lib/g.dart:3',
            body: GraphBody(nodes: [], edges: []),
          ),
        },
        warnings: const [],
      );
      expect(file.workflowNamed('review')!.id, 'lib/g.dart#reviewGraph');
    });

    test('is null when a workflow has no function', () {
      final file = GraphFile(
        format: 3,
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
