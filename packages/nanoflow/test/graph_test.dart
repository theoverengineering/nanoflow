// Declaring a graph of nodes (graph design §3, §4, §7): the shape it is
// built into, and what is not a graph.

import 'package:nanoflow/nanoflow.dart';
import 'package:nanoflow/src/graph.dart';
import 'package:test/test.dart';

Future<int> one(String s) async => 1;

Future<int> two(int n) async => n + 1;

Future<String> three(int n) async => '$n';

Future<int> wf(Flow f, int n) async => n;

Future<String> both((String, int) pair) async => '${pair.$1}${pair.$2}';

int four(int n) => n;

abstract final class Other {
  static Future<int> one(String s) async => 2;
}

final sub = Graph<int, String>('sub', [Graph.start(three)]);

Matcher rejects(String part) => throwsA(
  isA<ArgumentError>().having((e) => '${e.message}', 'message', contains(part)),
);

void main() {
  test('builds the shape: nodes by their names and kinds, starts, routes and '
      'joins', () {
    final g = Graph<String, String>('g', [
      Graph.start(one).next({1: two}, otherwise: three),
      Graph.part(two).next({three, wf}),
      Graph.join([three, wf]).next(both),
    ]);
    final shape = shapeOf(g);
    expect(shape.name, 'g');
    expect(
      [for (final n in shape.nodes) n.name],
      ['one', 'two', 'three', 'wf', 'both'],
    );
    expect(
      [for (final n in shape.nodes) n.kind],
      [
        NodeKind.function,
        NodeKind.function,
        NodeKind.function,
        NodeKind.workflow,
        NodeKind.function,
      ],
    );
    expect(shape.starts.single.name, 'one');
    final routes = shape.nodes[0].routes! as CaseRoutes;
    expect(routes.cases.single.key, 1);
    expect(routes.cases.single.targets.single.name, 'two');
    expect(routes.otherwise.single.name, 'three');
    final parallel = shape.nodes[1].routes! as AllRoutes;
    expect([for (final n in parallel.targets) n.name], ['three', 'wf']);
    expect(shape.nodes[2].routes, isNull);
    final join = shape.nodes[2].joins.single;
    expect(shape.nodes[3].joins.single, same(join));
    expect([for (final n in join.sources) n.name], ['three', 'wf']);
    expect(join.targets.single.name, 'both');
  });

  test('a chain goes on from each single node; the same function is one node, '
      'which makes a loop', () {
    final g = Graph<int, int>('g', [
      Graph.start(two).next(four).next({1: two}),
    ]);
    final shape = shapeOf(g);
    expect([for (final n in shape.nodes) n.name], ['two', 'four']);
    expect((shape.nodes[0].routes! as AllRoutes).targets.single.name, 'four');
    expect(
      (shape.nodes[1].routes! as CaseRoutes).cases.single.targets.single,
      same(shape.nodes[0]),
    );
  });

  test('a graph is a node, named by its name', () {
    final g = Graph<int, String>('g', [Graph.start(two).next(sub)]);
    final node = shapeOf(g).nodes[1];
    expect(node.name, 'sub');
    expect(node.kind, NodeKind.graph);
    expect(node.node, same(sub));
  });

  test('a graph is found by its call, which flow.start takes for it', () {
    final g = Graph<String, int>('found', [Graph.start(one)]);
    final Future<int> Function(Flow, String) call = g.call;
    expect(graphOfCall(call), same(g));
    expect(graphOfCall(one), isNull);
  });

  group('rejects', () {
    test('a closure', () {
      expect(
        () => Graph<String, int>('g', [Graph.start((String s) => 1)]),
        rejects('a node is a top-level function or a static method'),
      );
    });

    test('what is not a node', () {
      expect(
        () => Graph<Object?, Object?>('g', [Graph.start(42)]),
        rejects('42 is not a node'),
      );
      expect(
        () => Graph<Object?, Object?>('g', [
          Graph.start(one).next({1: 'x'}),
        ]),
        rejects('x is not a node'),
      );
    });

    test('two nodes of one name', () {
      expect(
        () => Graph<Object?, Object?>('g', [
          Graph.start(one).next({1: Other.one}),
        ]),
        rejects('two nodes are named one'),
      );
    });

    test('a graph without a start', () {
      expect(
        () => Graph<Object?, Object?>('g', []),
        rejects('the graph has no start'),
      );
    });

    test('arrows of a node declared twice', () {
      expect(
        () => Graph<Object?, Object?>('g', [
          Graph.start(one).next(two),
          Graph.part(one).next(three),
        ]),
        rejects('the arrows of one are declared twice'),
      );
    });

    test('a node that cannot be reached', () {
      expect(
        () => Graph<Object?, Object?>('g', [
          Graph.start(one),
          Graph.part(two).next(three),
        ]),
        rejects('two cannot be reached'),
      );
      expect(
        () => Graph<Object?, Object?>('g', [
          Graph.start(one).next(two),
          Graph.join([two, three]).next(four),
        ]),
        rejects('four cannot be reached'),
      );
    });

    test('a join of too few, too many or repeated nodes', () {
      expect(
        () => Graph<Object?, Object?>('g', [
          Graph.start(one).next(two),
          Graph.join([two]).next(three),
        ]),
        rejects('a join takes 2 to 6 different nodes'),
      );
      expect(
        () => Graph<Object?, Object?>('g', [
          Graph.start(one).next(two),
          Graph.join([two, two]).next(three),
        ]),
        rejects('a join takes 2 to 6 different nodes'),
      );
    });

    test('a map after a join', () {
      expect(
        () => Graph<Object?, Object?>('g', [
          Graph.start(two).next({three, four}),
          Graph.join([three, four]).next({1: two}),
        ]),
        rejects('a join leads to a node or a set'),
      );
    });

    test('otherwise without a map', () {
      expect(
        () => Graph<Object?, Object?>('g', [
          Graph.start(one).next(two, otherwise: three),
        ]),
        rejects('otherwise goes with a map'),
      );
    });

    test('next after a set or a map', () {
      expect(
        () => Graph<Object?, Object?>('g', [
          Graph.start(one).next({two}).next(three),
        ]),
        rejects('next after a set or a map'),
      );
    });

    test('an empty set of targets', () {
      expect(
        () => Graph<Object?, Object?>('g', [Graph.start(one).next(<Object>{})]),
        rejects('a set of targets is empty'),
      );
    });

    test('several problems at once, each on its line', () {
      expect(
        () => Graph<Object?, Object?>('g', [
          Graph.start(one).next(two, otherwise: three),
          Graph.part(four),
        ]),
        throwsA(
          isA<ArgumentError>().having(
            (e) => '${e.message}',
            'message',
            allOf(
              startsWith('graph "g":\n- '),
              contains('\n- otherwise goes with a map'),
              contains('\n- four cannot be reached'),
            ),
          ),
        ),
      );
    });
  });
}
