import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_ui/state/step_places.dart';

import 'support.dart';

void main() {
  final file = copiesGraphFile();
  StepPlaces stepPlacesOf(String workflow) => StepPlaces.of(
    file.functions['lib/copies.dart#$workflow'],
    file.functions,
  );
  GraphNode nodeOf(GraphBody body, String id) => body.node(id)!;

  /// The places of [nodes].
  Set<String?> placesOf(Set<StepNode> nodes) => {
    for (final node in nodes) node.place,
  };

  /// A step [name] that ran at [place].
  Step stepAt(String? place, [String name = 'upload']) => Step(
    id: 'step-$name',
    sessionId: 'session',
    name: name,
    key: '$name#1@0000000000000000',
    after: null,
    place: place,
    outputId: null,
    log: logFileName,
  );

  group('isPlaceOf', () {
    test('a step is at the place of a node it equals', () {
      expect(isPlaceOf('lib/copies.dart:7', 'lib/copies.dart:7'), isTrue);
    });

    test('a step is at the place of a node it ends with after a /', () {
      expect(
        isPlaceOf('/Users/me/copies/lib/copies.dart:7', 'lib/copies.dart:7'),
        isTrue,
      );
    });

    test('not at another line, nor at a path that only ends the same', () {
      expect(isPlaceOf('lib/copies.dart:70', 'lib/copies.dart:7'), isFalse);
      expect(isPlaceOf('lib/copies.dart:7', 'lib/copies.dart:70'), isFalse);
      expect(isPlaceOf('mylib/copies.dart:7', 'lib/copies.dart:7'), isFalse);
    });
  });

  group('StepPlaces', () {
    test('has every step node the workflow reaches: its body, the bodies '
        'of its copies, the functions it calls', () {
      expect(placesOf(stepPlacesOf('inPlace').nodes), {
        for (final line in [4, 7, 8, 9, 12]) copiesAt(line),
      });
      expect(placesOf(stepPlacesOf('viaCall').nodes), {
        for (final line in [17, 20, 21, 22]) copiesAt(line),
      });
      expect(placesOf(stepPlacesOf('nested').nodes), {
        for (final line in [27, 30, 31, 34, 37]) copiesAt(line),
      });
    });

    test('no nodes without a workflow', () {
      expect(StepPlaces.of(null, file.functions).nodes, isEmpty);
    });

    test('a step is at the nodes of its place (D13)', () {
      final places = stepPlacesOf('inPlace');
      expect(placesOf(places.of(stepAt(copiesAt(7)))), {copiesAt(7)});
      expect(placesOf(places.of(stepAt('/home/me/copies/${copiesAt(7)}'))), {
        copiesAt(7),
      });
      expect(
        places.of(stepAt(copiesAt(20))),
        isEmpty,
        reason: 'publish is not called',
      );
      expect(places.of(stepAt(null)), isEmpty);
      expect(places.of(null), isEmpty);
    });

    // `dart format` keeps short parallel steps on one line.
    final oneLine = GraphFunction(
      id: 'lib/ci.dart#check',
      name: 'check',
      place: 'lib/ci.dart:1',
      body: const GraphBody(
        nodes: [
          StepNode(id: '1', place: 'lib/ci.dart:2', name: 'lint'),
          StepNode(id: '2', place: 'lib/ci.dart:2', name: 'test'),
          StepNode(id: '3', place: 'lib/ci.dart:3', name: "'deploy-' + env"),
          StepNode(id: '4', place: 'lib/ci.dart:3', name: "'notify-' + env"),
        ],
        edges: [],
      ),
    );
    final ci = StepPlaces.of(oneLine, {oneLine.id: oneLine});

    test('of the nodes at its place, a step is at those of its name', () {
      expect(ci.of(stepAt('lib/ci.dart:2', 'lint')), {oneLine.body.node('1')});
      expect(ci.of(stepAt('lib/ci.dart:2', 'test')), {oneLine.body.node('2')});
      expect(
        ci.isIn(stepAt('lib/ci.dart:2', 'lint'), oneLine.body.node('2')!),
        isFalse,
      );
    });

    test('a step whose name no node at its place has — the nodes name it by '
        'an expression — is at all of them', () {
      expect(ci.of(stepAt('lib/ci.dart:3', 'deploy-prod')), {
        oneLine.body.node('3'),
        oneLine.body.node('4'),
      });
    });

    test('a step is at every node of its place and name: a finally drawn '
        'once for each way out of its try', () {
      final finallyTwice = GraphFunction(
        id: 'lib/f.dart#build',
        name: 'build',
        place: 'lib/f.dart:1',
        body: const GraphBody(
          nodes: [
            StepNode(id: '1', place: 'lib/f.dart:5', name: 'clean'),
            StepNode(id: '2', place: 'lib/f.dart:5', name: 'clean'),
          ],
          edges: [],
        ),
      );
      final places = StepPlaces.of(finallyTwice, {
        finallyTwice.id: finallyTwice,
      });
      expect(places.of(stepAt('lib/f.dart:5', 'clean')), {
        finallyTwice.body.node('1'),
        finallyTwice.body.node('2'),
      });
    });

    test('a step without a place, or at no node, is not on the graph', () {
      final places = stepPlacesOf('inPlace');
      expect(places.onGraph(stepAt(copiesAt(8))), isTrue);
      expect(places.onGraph(stepAt(copiesAt(99))), isFalse);
      expect(places.onGraph(stepAt(null)), isFalse);
      expect(places.onGraph(null), isFalse);
    });

    test('what a node holds: a step itself; copies the step nodes in their '
        'body and deeper; a call those of its functions; a condition '
        'nothing', () {
      final places = stepPlacesOf('nested');
      final nested = file.functions['lib/copies.dart#nested']!.body;
      final outer = nodeOf(nested, '1') as CopiesNode;
      expect(places.within(nodeOf(nested, '2')), {nodeOf(nested, '2')});
      expect(placesOf(places.within(outer)), {
        for (final line in [27, 30, 31, 34]) copiesAt(line),
      });
      expect(placesOf(places.within(nodeOf(outer.body, '2'))), {
        copiesAt(30),
        copiesAt(31),
      });
      final viaCall = file.functions['lib/copies.dart#viaCall']!.body;
      final copies = nodeOf(viaCall, '1') as CopiesNode;
      expect(
        placesOf(stepPlacesOf('viaCall').within(nodeOf(copies.body, '1'))),
        {
          for (final line in [20, 21, 22]) copiesAt(line),
        },
      );
      expect(
        places.within(
          const ConditionNode(id: 'c', place: 'lib/copies.dart:1', label: 'x'),
        ),
        isEmpty,
      );
    });

    test('a function calling itself holds its steps once', () {
      final recursive = GraphFunction(
        id: 'lib/r.dart#crawl',
        name: 'crawl',
        place: 'lib/r.dart:1',
        body: const GraphBody(
          nodes: [
            StepNode(id: '1', place: 'lib/r.dart:2', name: 'visit'),
            CallNode(
              id: '2',
              place: 'lib/r.dart:3',
              functions: ['lib/r.dart#crawl'],
            ),
          ],
          edges: [],
        ),
      );
      final places = StepPlaces.of(recursive, {recursive.id: recursive});
      expect(places.nodes, {recursive.body.node('1')});
      expect(places.within(recursive.body.node('2')!), {
        recursive.body.node('1'),
      });
    });

    test('isIn: whether a step is on a node or inside it', () {
      final places = stepPlacesOf('inPlace');
      final body = file.functions['lib/copies.dart#inPlace']!.body;
      expect(places.isIn(stepAt(copiesAt(8)), nodeOf(body, '2')), isTrue);
      expect(places.isIn(stepAt(copiesAt(8)), nodeOf(body, '1')), isFalse);
      expect(places.isIn(stepAt(copiesAt(4)), nodeOf(body, '1')), isTrue);
      expect(places.isIn(stepAt(null), nodeOf(body, '1')), isFalse);
      expect(places.isIn(null, nodeOf(body, '1')), isFalse);
    });
  });

  test('stepsNotOnGraph: the steps without a place or at no node, in '
      'order', () {
    final journal = Journal('a1b2-session', workflow: 'inPlace')
      ..step('plan', 1, end: 2, place: copiesAt(4))
      ..step('stray', 2, end: 3, place: 'lib/old.dart:3')
      ..step('upload', 3, end: 4, place: copiesAt(7))
      ..step('nowhere', 4);
    final steps = journal.data.stepsInOrder;
    expect(
      [
        for (final step in stepsNotOnGraph(steps, stepPlacesOf('inPlace')))
          step.name,
      ],
      ['stray', 'nowhere'],
    );
  });
}
