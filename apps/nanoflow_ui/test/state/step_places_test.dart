import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_ui/state/step_places.dart';

import 'support.dart';

void main() {
  final file = copiesGraphFile();
  StepPlaces placesOf(String workflow) => StepPlaces.of(
    file.functions['lib/copies.dart#$workflow'],
    file.functions,
  );
  GraphNode nodeOf(GraphBody body, String id) => body.node(id)!;

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
    test('has the places of every step node the workflow reaches: its '
        'body, the bodies of its copies, the functions it calls', () {
      expect(placesOf('inPlace').nodePlaces, {
        for (final line in [4, 7, 8, 9, 12]) copiesAt(line),
      });
      expect(placesOf('viaCall').nodePlaces, {
        for (final line in [17, 20, 21, 22]) copiesAt(line),
      });
      expect(placesOf('nested').nodePlaces, {
        for (final line in [27, 30, 31, 34, 37]) copiesAt(line),
      });
    });

    test('no places without a workflow', () {
      expect(StepPlaces.of(null, file.functions).nodePlaces, isEmpty);
    });

    test('a step is at the node places its place is (D13)', () {
      final places = placesOf('inPlace');
      expect(places.of(copiesAt(7)), {copiesAt(7)});
      expect(places.of('/home/me/copies/${copiesAt(7)}'), {copiesAt(7)});
      expect(places.of(copiesAt(20)), isEmpty, reason: 'publish is not called');
      expect(places.of(null), isEmpty);
    });

    test('a step without a place, or at no node, is not on the graph', () {
      final places = placesOf('inPlace');
      expect(places.onGraph(copiesAt(8)), isTrue);
      expect(places.onGraph(copiesAt(99)), isFalse);
      expect(places.onGraph(null), isFalse);
    });

    test('what a node holds: a step its place; copies the places in their '
        'body and deeper; a call those of its functions; a condition '
        'nothing', () {
      final places = placesOf('nested');
      final nested = file.functions['lib/copies.dart#nested']!.body;
      final outer = nodeOf(nested, '1') as CopiesNode;
      expect(places.within(nodeOf(nested, '2')), {copiesAt(37)});
      expect(places.within(outer), {
        for (final line in [27, 30, 31, 34]) copiesAt(line),
      });
      expect(places.within(nodeOf(outer.body, '2')), {
        copiesAt(30),
        copiesAt(31),
      });
      final viaCall = file.functions['lib/copies.dart#viaCall']!.body;
      final copies = nodeOf(viaCall, '1') as CopiesNode;
      expect(placesOf('viaCall').within(nodeOf(copies.body, '1')), {
        for (final line in [20, 21, 22]) copiesAt(line),
      });
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
      expect(places.nodePlaces, {'lib/r.dart:2'});
      expect(places.within(recursive.body.node('2')!), {'lib/r.dart:2'});
    });

    test('isIn: whether a step at a place is on a node or inside it', () {
      final places = placesOf('inPlace');
      final body = file.functions['lib/copies.dart#inPlace']!.body;
      expect(places.isIn(copiesAt(8), nodeOf(body, '2')), isTrue);
      expect(places.isIn(copiesAt(8), nodeOf(body, '1')), isFalse);
      expect(places.isIn(copiesAt(4), nodeOf(body, '1')), isTrue);
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
        for (final step in stepsNotOnGraph(steps, placesOf('inPlace')))
          step.name,
      ],
      ['stray', 'nowhere'],
    );
  });
}
