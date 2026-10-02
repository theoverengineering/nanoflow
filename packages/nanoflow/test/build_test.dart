import 'dart:convert';
import 'dart:io';

import 'package:nanoflow/nanoflow.dart';
import 'package:nanoflow/src/build.dart';
import 'package:nanoflow/src/vertex.dart' show callVertex;
import 'package:nanoflow_model/nanoflow_model.dart' as model;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'fixtures/build_errors.dart' as errors;
import 'fixtures/review_graph.dart' as review;
import 'fixtures/shapes.dart' as shapes;

final String fixtures = p.absolute('test', 'fixtures');
final String reviewFile = p.join(fixtures, 'review_graph.dart');
final String shapesFile = p.join(fixtures, 'shapes.dart');

/// The line of `final <name> =` in [file], as the description writes it.
int lineOf(String file, String name) {
  final lines = File(file).readAsLinesSync();
  final index = lines.indexWhere((l) => l.startsWith('final $name ='));
  if (index < 0) throw StateError('no "final $name =" in $file');
  return index + 1;
}

String rg(String name) => 'review_graph.dart:${lineOf(reviewFile, name)}';
String sh(String name) => 'shapes.dart:${lineOf(shapesFile, name)}';
Map<String, Object?> ref(String type) => {r'$ref': '#/$type'};

/// The description's graph for [graph], as a program file next to the
/// fixtures would print it.
Map<String, Object?> graphOf(Graph<Object?> graph) =>
    describe(buildGraph(graph), p.join(fixtures, 'graph.dart'))['graph']!
        as Map<String, Object?>;

/// Compares JSON with key order, so a failure shows a readable diff.
void expectJson(Object? actual, Object? expected) {
  const encoder = JsonEncoder.withIndent('  ');
  expect(encoder.convert(actual), encoder.convert(expected));
}

List<String> buildErrors(Graph<Object?> graph) {
  try {
    buildGraph(graph);
  } on GraphBuildException catch (e) {
    return e.errors;
  }
  fail('the graph built');
}

void main() {
  group('the README graph', () {
    late BuiltGraph built;
    late Map<String, Object?> description;

    setUp(() {
      built = buildGraph(review.graph);
      description = describe(built, reviewFile);
    });

    test('is described in the README format', () {
      expectJson(description, {
        'file': reviewFile,
        'graph': {
          'start': 'collect',
          'types': {
            'Request': {'title': 'Request'},
            'Change': {'title': 'Change'},
            'Report': {'title': 'Report'},
          },
          'nodes': {
            'collect': {
              'command': rg('collect'),
              'in': ref('Request'),
              'out': ref('Change'),
              'then': 'isEmpty',
            },
            'isEmpty': {
              'decide': rg('isEmpty'),
              'in': ref('Change'),
              'then': 'discard',
              'else': 'inspect',
            },
            'inspect': {
              'command': rg('inspect'),
              'in': ref('Change'),
              'out': ref('Report'),
              'then': 'verdict',
            },
            'verdict': {
              'decide': rg('verdict'),
              'in': ref('Report'),
              'then': {
                'accepted': ['publish', 'notify'],
                'returned': 'fix',
              },
            },
            'fix': {
              'command': rg('fix'),
              'in': ref('Report'),
              'out': ref('Change'),
              'then': 'inspect',
            },
            'publish': {'command': rg('publish'), 'in': ref('Report')},
            'notify': {'command': rg('notify'), 'in': ref('Report')},
            'discard': {'command': rg('discard'), 'in': ref('Change')},
          },
        },
      });
    });

    test('is a description the model reads', () {
      final parsed = model.GraphDescription.fromJson(
        jsonDecode(jsonEncode(description)),
      );
      final graph = parsed.graph;
      expect(parsed.file, reviewFile);
      expect(graph.start, const model.Target.node('collect'));
      expect(graph['collect'], isA<model.WorkerNode>());
      expect((graph['isEmpty']! as model.ForkNode).isIf, isTrue);
      expect((graph['verdict']! as model.ForkNode).isIf, isFalse);
      expect(
        (graph['verdict']! as model.ForkNode).route('accepted'),
        isA<model.RouteTo>().having(
          (r) => r.target,
          'target',
          const model.Target.list(['publish', 'notify']),
        ),
      );
      for (final node in graph.nodes.values) {
        for (final exit in node.exits) {
          expect(graph.nodes.keys, containsAll(exit.target.names));
        }
      }
    });

    test('keeps the nodes by name in declaration order', () {
      expect(built.nodes.keys, [
        'collect',
        'isEmpty',
        'inspect',
        'verdict',
        'fix',
        'publish',
        'notify',
        'discard',
      ]);
      expect(built.nodes['collect'], same(review.collect));
      expect(built.nodes['verdict'], same(review.verdict));
    });

    test('keeps the function of each node to call', () async {
      final change = await callVertex(
        built.nodes['collect']!,
        review.Request(branch: 'main'),
      );
      expect(
        change,
        isA<review.Change>().having((c) => c.path, 'path', 'lib/main.dart'),
      );
      expect(await callVertex(built.nodes['isEmpty']!, change), isFalse);
    });

    test('knows that the start node takes the launch input', () {
      expect(built.startTakesInput, isTrue);
    });

    test('holds commands as absolute declaration places until described', () {
      final nodes = built.graphJson['nodes']! as Map<String, Object?>;
      final collect = nodes['collect']! as Map<String, Object?>;
      expect(
        collect['command'],
        '$reviewFile:${lineOf(reviewFile, 'collect')}',
      );
    });

    test('places commands relative to the directory of the program file', () {
      final elsewhere = describe(built, p.absolute('bin', 'graph.dart'));
      final nodes =
          (elsewhere['graph']! as Map<String, Object?>)['nodes']!
              as Map<String, Object?>;
      expect(
        (nodes['isEmpty']! as Map<String, Object?>)['decide'],
        '../test/fixtures/review_graph.dart:${lineOf(reviewFile, 'isEmpty')}',
      );
    });

    test('takes a relative program file as it is given', () {
      final relative = describe(built, 'test/fixtures/review_graph.dart');
      expect(relative['file'], 'test/fixtures/review_graph.dart');
      final nodes =
          (relative['graph']! as Map<String, Object?>)['nodes']!
              as Map<String, Object?>;
      expect(
        (nodes['collect']! as Map<String, Object?>)['command'],
        rg('collect'),
      );
    });
  });

  group('describes', () {
    test('one part that is not wrapped in Graph([…])', () {
      expectJson(graphOf(shapes.single), {
        'start': 'inspect',
        'types': {
          'Change': {'title': 'Change'},
          'Report': {'title': 'Report'},
        },
        'nodes': {
          'inspect': {
            'command': rg('inspect'),
            'in': ref('Change'),
            'out': ref('Report'),
            'then': 'verdict',
          },
          'verdict': {
            'decide': rg('verdict'),
            'in': ref('Report'),
            'then': {'accepted': 'publish'},
          },
          'publish': {'command': rg('publish'), 'in': ref('Report')},
        },
      });
    });

    test('several starts as a list, nodes by library and line', () {
      final graph = graphOf(shapes.twoStarts);
      expect(graph['start'], ['tally', 'collect']);
      expect((graph['nodes']! as Map<String, Object?>).keys, [
        'collect',
        'anything',
        'tally',
      ]);
    });

    test('a start node without in, which needs no launch input', () {
      expectJson(graphOf(shapes.noInput), {
        'start': 'anything',
        'types': <String, Object?>{},
        'nodes': {
          'anything': {'command': sh('anything')},
        },
      });
      expect(buildGraph(shapes.noInput).startTakesInput, isFalse);
    });

    test('sets in set order, empty sets, and a switch spread over parts', () {
      expectJson(graphOf(shapes.sets), {
        'start': 'inspect',
        'types': {
          'Change': {'title': 'Change'},
          'Report': {'title': 'Report'},
        },
        'nodes': {
          'inspect': {
            'command': rg('inspect'),
            'in': ref('Change'),
            'out': ref('Report'),
            'then': 'grade',
          },
          'publish': {
            'command': rg('publish'),
            'in': ref('Report'),
            'then': <String>[],
          },
          'notify': {'command': rg('notify'), 'in': ref('Report')},
          'grade': {
            'decide': sh('grade'),
            'in': ref('Report'),
            'then': {
              'accepted': 'publish',
              'returned': ['notify', 'publish'],
            },
            'else': <String>[],
          },
        },
      });
    });

    test('switch keys that are not strings by their toString()', () {
      expectJson(graphOf(shapes.numbers), {
        'start': 'size',
        'types': {
          'Report': {'title': 'Report'},
          'Change': {'title': 'Change'},
        },
        'nodes': {
          'fix': {
            'command': rg('fix'),
            'in': ref('Report'),
            'out': ref('Change'),
          },
          'publish': {'command': rg('publish'), 'in': ref('Report')},
          'notify': {'command': rg('notify'), 'in': ref('Report')},
          'size': {
            'decide': sh('size'),
            'in': ref('Report'),
            'then': {'0': 'publish', '2': 'notify'},
            'else': 'fix',
          },
        },
      });
    });

    test('an if without then as one that leads nowhere', () {
      final nodes =
          graphOf(shapes.onlyOtherwise)['nodes']! as Map<String, Object?>;
      expectJson(nodes['empty'], {
        'decide': sh('empty'),
        'in': ref('Change'),
        'then': <String>[],
        'else': 'discard',
      });
    });

    test('every kind of data type', () {
      const integer = {'type': 'integer'};
      expectJson(graphOf(shapes.typed), {
        'start': ['batch', 'weigh'],
        'types': {
          'Change': {'title': 'Change'},
          'Verdict': {
            'enum': ['accepted', 'returned'],
          },
        },
        'nodes': {
          'anything': {'command': sh('anything'), 'then': 'whatever'},
          'whatever': {'command': sh('whatever')},
          'batch': {
            'command': sh('batch'),
            'in': {'type': 'array', 'items': ref('Change')},
            'out': {'type': 'object', 'additionalProperties': integer},
            'then': 'tally',
          },
          'tally': {
            'command': sh('tally'),
            'in': {'type': 'object', 'additionalProperties': integer},
            'out': {'type': 'array', 'items': integer},
            'then': 'anything',
          },
          'weigh': {
            'command': sh('weigh'),
            'in': {'type': 'number'},
            'out': {'type': 'boolean'},
            'then': 'label',
          },
          'label': {
            'command': sh('label'),
            'in': {'type': 'boolean'},
            'out': {'type': 'string'},
            'then': 'measure',
          },
          'measure': {
            'command': sh('measure'),
            'in': {'type': 'string'},
            'out': integer,
            'then': 'scale',
          },
          'scale': {
            'command': sh('scale'),
            'in': {'type': 'number'},
            'out': ref('Verdict'),
            'then': 'announce',
          },
          'announce': {'command': sh('announce'), 'in': ref('Verdict')},
        },
      });
    });

    test('enum switch keys by name', () {
      final nodes = graphOf(shapes.sets)['nodes']! as Map<String, Object?>;
      final grade = nodes['grade']! as Map<String, Object?>;
      expect((grade['then']! as Map<String, Object?>).keys, [
        'accepted',
        'returned',
      ]);
    });
  });

  group('does not build', () {
    test('without Graph.start', () {
      expect(buildErrors(errors.noStart), ['graph has no Graph.start']);
    });

    test('a worker with two nexts, also across parts', () {
      expect(buildErrors(errors.nextTwice), ['first: next is declared twice']);
    });

    test('an if with two thens', () {
      expect(buildErrors(errors.thenTwice), [
        'check: outcome "true" is declared twice',
      ]);
    });

    test('a fork with two otherwises', () {
      expect(buildErrors(errors.otherwiseTwice), [
        'check: otherwise is declared twice',
      ]);
    });

    test('a switch with an outcome declared in two parts', () {
      expect(buildErrors(errors.outcomeTwice), [
        'choose: outcome "left" is declared twice',
      ]);
    });

    test('a node that is not a top-level variable', () {
      expect(buildErrors(errors.notTopLevel), [
        'a node in the graph is not a top-level variable',
      ]);
    });

    test('a node held by two variables', () {
      expect(buildErrors(errors.heldTwice), [
        'node is held by two variables: held, alsoHeld',
      ]);
    });

    test('two nodes of the same name from two libraries', () {
      expect(buildErrors(errors.sameName), ['node name "twin" is not unique']);
    });

    test('and reports every error at once', () {
      expect(buildErrors(errors.severalErrors), [
        'graph has no Graph.start',
        'first: next is declared twice',
      ]);
    });

    test('data types that are not JSON types', () {
      expect(buildErrors(errors.unsupported), [
        'takesSet: in: Set<int> is not a JSON type',
        'givesOpaque: out: Opaque needs a fromJson constructor and a toJson '
            'method',
        'takesOnlyFromJson: in: OnlyFromJson needs a fromJson constructor '
            'and a toJson method',
        'takesIntKeys: in: Map<int, String> has keys that are not String',
        'takesAnyList: in: List<dynamic>: dynamic is not a JSON type',
      ]);
    });

    test('data that may be null, and Object for a node without data', () {
      const nullHint =
          'data cannot be null; use a class or Object? for a node without '
          'in/out';
      const objectHint = 'use Object? for a node without in/out';
      expect(buildErrors(errors.nullable), [
        'takesNullable: in: Report? — $nullHint',
        'givesNullable: out: String? — $nullHint',
        'decidesOnNullable: in: String? — $nullHint',
        'takesNullableItems: in: List<String?> — $nullHint',
        'givesNullableValues: out: Map<String, List<int?>> — $nullHint',
        'takesObject: in: Object — $objectHint',
        'givesObject: out: Object — $objectHint',
      ]);
    });
  });
}
