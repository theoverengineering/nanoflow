// Declaring a graph of nodes (graph node objects design §3, §4, §6): the
// shape it is built into, what a call of a node or a graph gives, and what is
// not a graph.

import 'dart:async' show unawaited;

import 'package:nanoflow/src/call_limit.dart';
import 'package:nanoflow/src/failure.dart';
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

  test('a failure route takes the input of the node and the failure, typed, '
      'and is the node\'s own, apart from its arrows', () {
    final g = Graph<String, Object?>('g', [
      Graph.start(a)
          .failed((String s, CallFailure f) => c('$s ${f.error} ${f.type}'))
          .next((n) => b(n)),
      Graph.part(b).next((x) => null),
      Graph.part(c).failed((s, f) => null),
    ]);
    final [first, second, third] = shapeOf(g).nodes;
    expect(
      first.failed!('in', const CallFailure('boom', type: 'StateError')),
      isA<Next>()
          .having((n) => n.target, 'target', same(c))
          .having((n) => n.input, 'input', 'in boom StateError'),
    );
    expect(first.route!(3), isA<Next>().having((n) => n.input, 'input', 3));
    expect(second.failed, isNull);
    expect(third.route, isNull);
    expect(third.failed!('x', const CallFailure('no')), isNull);
  });

  test('a failure route of a start is declared as of any part', () {
    final g = Graph<String, Object?>('g', [
      Graph.start(a).failed((s, f) => c(s)),
    ]);
    expect(shapeOf(g).starts.single.failed, isNotNull);
    expect(shapeOf(g).starts.single.route, isNull);
  });

  test('a failure tells its error and the name of its type, and compares by '
      'them', () {
    const failure = CallFailure('StateError: no', type: 'StateError');
    expect(failure.error, 'StateError: no');
    expect(failure.type, 'StateError');
    expect(const CallFailure('x'), const CallFailure('x'));
    expect(
      const CallFailure('x', type: 'A'),
      isNot(const CallFailure('x', type: 'B')),
    );
    expect(
      const CallFailure('x', type: 'A').hashCode,
      const CallFailure('x', type: 'A').hashCode,
    );
    expect('$failure', 'CallFailure(StateError: StateError: no)');
    expect('${const CallFailure('x')}', 'CallFailure(x)');
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

  test('a call of a node or a graph takes a limit of 1 or more, none by '
      'default', () {
    final graph = Graph<String, int>('graph', [Graph.start(a)]);
    expect(a('x').limit, isNull);
    expect(a('x', limit: 2).limit, 2);
    expect(a.call('x', limit: 1).limit, 1);
    expect(graph('x').limit, isNull);
    expect(graph('x', limit: 3).limit, 3);
    expect(() => a('x', limit: 0), throwsArgumentError);
    expect(() => graph('x', limit: -1), throwsArgumentError);
  });

  group('the copies of a call site', () {
    /// The copies of [copies] that hold a slot, by their index, once the
    /// slots given have been taken up.
    Future<List<int>> running(List<CallCopy> copies, List<int> asked) async {
      final granted = <int>[];
      for (final i in asked) {
        unawaited(copies[i].take().then((_) => granted.add(i)));
      }
      await Future<void>.delayed(Duration.zero);
      return granted;
    }

    test('go in the order they were called, no more at once than the '
        'limit', () async {
      final site = CallSite();
      final copies = [for (var i = 0; i < 5; i++) site.copy(2)];
      final granted = <int>[];
      for (final i in [4, 3, 2, 1, 0]) {
        unawaited(copies[i].take().then((_) => granted.add(i)));
      }
      await Future<void>.delayed(Duration.zero);
      expect(granted, [0, 1]);
      copies[1].end();
      await Future<void>.delayed(Duration.zero);
      expect(granted, [0, 1, 2]);
      copies[0].end();
      copies[2].end();
      await Future<void>.delayed(Duration.zero);
      expect(granted, [0, 1, 2, 3, 4]);
    });

    test('a copy called but not asking yet holds back those called after '
        'it, until it asks or ends', () async {
      final site = CallSite();
      final copies = [for (var i = 0; i < 4; i++) site.copy(2)];
      expect(await running(copies, [1, 2, 3]), isEmpty);
      // 0 ends without asking, as a copy whose effects are all journaled.
      copies[0].end();
      await Future<void>.delayed(Duration.zero);
      final late = <int>[];
      unawaited(copies[3].take().then((_) => late.add(3)));
      await Future<void>.delayed(Duration.zero);
      expect(late, isEmpty);
      copies[1].end();
      await Future<void>.delayed(Duration.zero);
      expect(late, [3]);
    });

    test('the effects of one copy share its slot', () async {
      final site = CallSite();
      final copy = site.copy(1);
      final other = site.copy(1);
      await copy.take();
      await copy.take();
      var started = false;
      unawaited(other.take().then((_) => started = true));
      await Future<void>.delayed(Duration.zero);
      expect(started, isFalse);
      copy.end();
      await Future<void>.delayed(Duration.zero);
      expect(started, isTrue);
    });

    test('a copy waits until fewer than its own limit run', () async {
      final site = CallSite();
      final wide = site.copy(3);
      final narrow = site.copy(1);
      final last = site.copy(3);
      await wide.take();
      expect(await running([narrow, last], [0, 1]), isEmpty);
      wide.end();
      await Future<void>.delayed(Duration.zero);
      await narrow.take();
      await last.take();
    });

    test('those that ran before the process ended go before the new ones, '
        'wherever they were called, a copy not asking yet holding back none '
        'of them', () async {
      final site = CallSite();
      final holder = site.copy(1);
      await holder.take();
      final notAsking = site.copy(1);
      final fresh = site.copy(1);
      final started = site.copy(1);
      final replayed = site.copy(1);
      final granted = <String>[];
      unawaited(fresh.take().then((_) => granted.add('fresh')));
      unawaited(
        started.take(started: true).then((_) => granted.add('started')),
      );
      unawaited(replayed.take().then((_) => granted.add('replayed')));
      replayed.replayed();
      await Future<void>.delayed(Duration.zero);
      expect(granted, isEmpty);
      holder.end();
      await Future<void>.delayed(Duration.zero);
      expect(granted, ['started']);
      started.end();
      await Future<void>.delayed(Duration.zero);
      expect(granted, ['started', 'replayed']);
      replayed.end();
      await Future<void>.delayed(Duration.zero);
      // The new one waits behind the copy called before it, not asking yet.
      expect(granted, ['started', 'replayed']);
      notAsking.end();
      await Future<void>.delayed(Duration.zero);
      expect(granted, ['started', 'replayed', 'fresh']);
    });

    test('resuming, a new copy asks a turn of the event loop late: one that '
        'ran before and asks in the meantime goes first', () async {
      final site = CallSite();
      final fresh = site.copy(1);
      final started = site.copy(1);
      final granted = <String>[];
      unawaited(fresh.take(resuming: true).then((_) => granted.add('fresh')));
      await Future<void>.value();
      unawaited(
        started
            .take(started: true, resuming: true)
            .then((_) => granted.add('started')),
      );
      await Future<void>.delayed(Duration.zero);
      expect(granted, ['started']);
      started.end();
      await Future<void>.delayed(Duration.zero);
      expect(granted, ['started', 'fresh']);
    });

    for (final how in ['started', 'replayed']) {
      test('a copy found to have run before once it has asked late, by an '
          'effect $how, asks at once and goes first', () async {
        final site = CallSite();
        final fresh = site.copy(1);
        final ranBefore = site.copy(1);
        final granted = <String>[];
        unawaited(fresh.take(resuming: true).then((_) => granted.add('fresh')));
        unawaited(
          ranBefore.take(resuming: true).then((_) => granted.add('ranBefore')),
        );
        if (how == 'started') {
          unawaited(ranBefore.take(started: true, resuming: true));
        } else {
          ranBefore.replayed();
        }
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        expect(granted, ['ranBefore']);
        ranBefore.end();
        await Future<void>.delayed(Duration.zero);
        expect(granted, ['ranBefore', 'fresh']);
      });
    }

    test('a copy that ends while it waits to ask fails its wait', () async {
      final site = CallSite();
      final copy = site.copy(1);
      final wait = copy.take(resuming: true);
      copy.end();
      await expectLater(wait, throwsStateError);
      // Nor does its late ask take a slot from the next.
      final next = site.copy(1);
      await next.take().timeout(const Duration(seconds: 1));
    });

    test('a copy that has ended takes no slot and does not end again', () {
      final site = CallSite();
      final copy = site.copy(1)..end();
      expect(copy.take, throwsStateError);
      expect(copy.end, throwsStateError);
      final running = site.copy(1);
      unawaited(running.take());
      running.end();
      expect(running.end, throwsStateError);
    });
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
        unawaited(slots.take().then((_) => granted.add(i)));
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
      unawaited(slots.take().then((_) => third = true));
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

    test('a failure route of a node declared twice', () {
      expect(
        () => Graph<Object?, Object?>('g', [
          Graph.start(a).failed((s, f) => null),
          Graph.part(a).failed((s, f) => null),
        ]),
        rejects('the failure route of a is declared twice'),
      );
      expect(
        () => Graph<Object?, Object?>('g', [
          Graph.start(a).failed((s, f) => null).failed((s, f) => null),
        ]),
        rejects('the failure route of a is declared twice'),
      );
      // Its arrows and its failure route on two parts are each declared
      // once.
      expect(
        Graph<Object?, Object?>('g', [
          Graph.start(a).next((x) => null),
          Graph.part(a).failed((s, f) => null),
        ]),
        isA<Graph<Object?, Object?>>(),
      );
    });

    test('a failure route of a join, which calls nothing', () {
      expect(
        () => Graph<Object?, Object?>('g', [
          Graph.start(c).next((x) => {a(x), c(x)}),
          Graph.join([a, c]).failed((Object? x, f) => null),
        ]),
        rejects('the join of a, c has a failure route: a join calls nothing'),
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
