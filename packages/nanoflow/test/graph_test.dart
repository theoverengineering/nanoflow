// Declaring a graph of nodes (graph node objects design §3, §4, §6): the
// shape it is built into, what a call of a node or a graph gives, and what is
// not a graph.

import 'package:nanoflow/src/graph.dart';
import 'package:test/test.dart';

final a = node('a', (String s) async => s.length);

final b = node('b', (int n) async => '$n');

final c = node('c', (String s) async => s);

/// Another node named as [a].
final otherA = node('a', (String s) async => 0);

Matcher rejects(String part) => throwsA(
  isA<ArgumentError>().having((e) => '${e.message}', 'message', contains(part)),
);

void main() {
  test('builds the shape: starts, nodes by name, a route on each part', () {
    final g = Graph<String, Object?>('g', [
      Graph.start(a).next((x) => b(x)),
      Graph.part(b).next((x) => null),
    ]);
    final shape = shapeOf(g);
    expect(shape.name, 'g');
    expect([for (final n in shape.starts) n.name], ['a']);
    expect([for (final n in shape.nodes) n.name], ['a', 'b']);
    expect(shape.nodes[0].node, same(a));
    expect(
      shape.nodes[0].route!(3),
      isA<Next>()
          .having((n) => n.target, 'target', same(b))
          .having((n) => n.input, 'input', 3),
    );
    expect(shape.nodes[1].route!('3'), isNull);
  });

  test('a join knows its nodes, in order, and its route', () {
    final g = Graph<String, Object?>('g', [
      Graph.start(c).next((x) => {a(x), c(x)}),
      Graph.join([a, c]).next(((int, String) both) => null),
    ]);
    final [first, second] = shapeOf(g).nodes;
    expect([first.name, second.name], ['c', 'a']);
    final join = first.joins.single;
    expect(second.joins.single, same(join));
    expect([for (final n in join.sources) n.name], ['a', 'c']);
    expect(join.route!((1, 'x')), isNull);
    expect(second.route, isNull);
  });

  test('a node only a route reaches is not declared up front', () {
    final g = Graph<String, Object?>('g', [Graph.start(a).next((x) => b(x))]);
    final shape = shapeOf(g);
    expect([for (final n in shape.nodes) n.name], ['a']);
    final reached = shape.nodeFor(b);
    expect(shape.nodeFor(b), same(reached));
    expect([for (final n in shape.nodes) n.name], ['a', 'b']);
    expect(
      () => shape.nodeFor(otherA),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          'graph "g": two nodes are named a',
        ),
      ),
    );
  });

  test('call gives a Next, it runs nothing', () {
    var ran = 0;
    final counted = node('counted', (String s) {
      ran++;
      return s;
    });
    final next = counted('in');
    expect(next.target, same(counted));
    expect(next.input, 'in');
    final graph = Graph<String, String>('graph', [Graph.start(counted)]);
    final nextGraph = graph('in');
    expect(nextGraph.target, same(graph));
    expect(nextGraph.input, 'in');
    expect(ran, 0);
    expect(counted.body('x'), 'x');
    expect(ran, 1);
  });

  test('a node takes a concurrency of 1 or more, none by default', () {
    expect(node('x', (int n) => n).concurrency, isNull);
    expect(node('x', (int n) => n, concurrency: 1).concurrency, 1);
    expect(() => node('x', (int n) => n, concurrency: 0), throwsArgumentError);
    expect(() => node('x', (int n) => n, concurrency: -1), throwsArgumentError);
  });

  test(
    'slots go to the waiting in the order they asked, one per release',
    () async {
      final slots = Slots(2);
      final granted = <int>[];
      await slots.take();
      await slots.take();
      for (var i = 0; i < 4; i++) {
        slots.take().then((_) => granted.add(i));
      }
      await Future<void>.delayed(Duration.zero);
      expect(granted, isEmpty);
      for (var n = 1; n <= 4; n++) {
        slots.release();
        await Future<void>.delayed(Duration.zero);
        expect(granted, [for (var i = 0; i < n; i++) i]);
      }
      // Two of the slots are still taken: releasing them frees them.
      slots.release();
      slots.release();
      await slots.take();
      await slots.take();
      var third = false;
      slots.take().then((_) => third = true);
      await Future<void>.delayed(Duration.zero);
      expect(third, isFalse);
    },
  );

  group('rejects', () {
    test('a graph without a start', () {
      expect(
        () => Graph<Object?, Object?>('g', []),
        rejects('the graph has no start'),
      );
      expect(
        () => Graph<Object?, Object?>('g', [Graph.part(a)]),
        rejects('the graph has no start'),
      );
    });

    test('arrows of a node declared twice', () {
      expect(
        () => Graph<Object?, Object?>('g', [
          Graph.start(a).next((x) => b(x)),
          Graph.part(a).next((x) => null),
        ]),
        rejects('the arrows of a are declared twice'),
      );
      expect(
        () => Graph<Object?, Object?>('g', [
          Graph.start(a).next((x) => b(x)).next((x) => null),
        ]),
        rejects('the arrows of a are declared twice'),
      );
      expect(
        () => Graph<Object?, Object?>('g', [
          Graph.start(c).next((x) => {a(x), c(x)}),
          Graph.join([a, c]).next((Object? x) => null).next((x) => null),
        ]),
        rejects('the arrows of the join of a, c are declared twice'),
      );
    });

    test('two nodes of one name', () {
      expect(
        () => Graph<Object?, Object?>('g', [
          Graph.start(a).next((x) => b(x)),
          Graph.part(otherA),
        ]),
        rejects('two nodes are named a'),
      );
    });

    test('a join of too few, too many or repeated nodes', () {
      final nodes = [
        for (var i = 0; i < 7; i++) node('n$i', (String s) async => s),
      ];
      for (final join in [
        [c],
        [c, c],
        nodes,
      ]) {
        expect(
          () => Graph<Object?, Object?>('g', [
            Graph.start(c),
            Graph.join(join).next((Object? x) => null),
          ]),
          rejects('a join takes 2 to 6 different nodes'),
        );
      }
      expect(
        Graph<Object?, Object?>('g', [
          Graph.start(c),
          Graph.join(nodes.take(6).toList()),
        ]),
        isA<Graph<Object?, Object?>>(),
      );
    });

    test('several problems at once, each on its line', () {
      expect(
        () => Graph<Object?, Object?>('g', [
          Graph.part(a).next((x) => b(x)).next((x) => null),
          Graph.part(otherA),
          Graph.join([b]),
        ]),
        throwsA(
          isA<ArgumentError>().having(
            (e) => '${e.message}',
            'message',
            allOf(
              startsWith('graph "g":\n- '),
              contains('\n- the arrows of a are declared twice'),
              contains('\n- two nodes are named a'),
              contains('\n- a join takes 2 to 6 different nodes'),
              contains('\n- the graph has no start'),
            ),
          ),
        ),
      );
    });
  });
}
