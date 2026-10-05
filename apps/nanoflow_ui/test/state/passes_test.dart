// What the forks passed and the edges taken are (effects design §5): for
// journals over small bodies drawn for each test, over the review example's
// graph, and over the session the real library wrote for it.
//
// A body is written as its nodes and its edges `from>to`, an empty side being
// the body's start or end, and `from>to:label` for an edge with a label. Each
// effect node is named by its id and is at a place of its name,
// `lib/flow.dart:<name>`. A journal's effects follow one another, each after
// the one before it, unless the test says otherwise — which is how the
// library keys them only when each effect is awaited where the one before it
// was: after an awaited call, a closure called in place or a wait the library
// keys the next effect after the effect before them (spec §4.3), and the tests
// of those shapes say so.
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_ui/state/copies.dart';
import 'package:nanoflow_ui/state/effect_places.dart';
import 'package:nanoflow_ui/state/passes.dart';
import 'package:nanoflow_ui/state/session_feed.dart';

import '../layout/support.dart' show loadGraphFile;
import 'support.dart';

/// The place of the effects named [name] in the bodies below.
String flowAt(String name) => 'lib/flow.dart:$name';

/// An effect node [id] named [name], by default its id, at the place of its
/// name.
EffectNode effectAt(String id, {String? name}) =>
    EffectNode(id: id, place: flowAt(name ?? id), name: name ?? id);

ConditionNode forkAt(String id) =>
    ConditionNode(id: id, place: null, label: id);

/// A call [id] of [function].
CallNode callAt(String id, GraphFunction function) =>
    CallNode(id: id, place: null, functions: [function.id]);

/// Copies [id] of [body], side by side.
CopiesNode copiesNode(String id, GraphBody body) =>
    CopiesNode(id: id, place: null, label: 'x in xs', body: body);

GraphEdge _edge(String text) {
  final [from, rest] = text.split('>');
  final [to, ...label] = rest.split(':');
  return GraphEdge(
    from: from.isEmpty ? null : from,
    to: to.isEmpty ? null : to,
    label: label.firstOrNull,
  );
}

/// A function [name] of [nodes] and [edges].
GraphFunction graphFunction(
  String name,
  List<GraphNode> nodes,
  List<String> edges,
) => GraphFunction(
  id: 'lib/flow.dart#$name',
  name: name,
  place: null,
  body: GraphBody(nodes: nodes, edges: [for (final e in edges) _edge(e)]),
);

/// A body drawn from nodes and edges as the workflow `flow`, which calls
/// [called]; its passes are read as texts of its edges.
final class Shape {
  factory Shape(
    List<GraphNode> nodes,
    List<String> edges, {
    List<GraphFunction> called = const [],
  }) {
    final flow = graphFunction('flow', nodes, edges);
    return Shape.of(
      flow.body,
      places: EffectPlaces.of(flow, {
        flow.id: flow,
        for (final function in called) function.id: function,
      }),
    );
  }

  /// [body], the effects found by [places].
  Shape.of(this.body, {required this.places})
    : edges = [
        for (final edge in body.edges) '${edge.from ?? ''}>${edge.to ?? ''}',
      ];

  final GraphBody body;

  /// The edges as texts, in the order of `body.edges`.
  final List<String> edges;

  final EffectPlaces places;

  /// The passes of [effects] of [session], by default all its effects, on
  /// [body].
  Passes passes(SessionData session, {Iterable<EffectState>? effects}) =>
      Passes.of(
        body,
        places: places,
        session: session,
        effects: effects ?? session.state.effects,
      );

  /// The forks passed, with how many times.
  Map<String, int> forksOf(Passes passes) => {
    for (final node in body.nodes)
      if (passes.of(node.id) > 0) node.id: passes.of(node.id),
  };

  Set<String> takenBy(Passes passes) => {
    for (final (i, edge) in edges.indexed)
      if (passes.taken(i)) edge,
  };

  Set<String> untakenBy(Passes passes) => {
    for (final (i, edge) in edges.indexed)
      if (passes.untaken(i)) edge,
  };
}

/// A session of the effects [names] one after the other, each at the place
/// of its name and after the one before it; finished after them when
/// [finished].
Journal ran(List<String> names, {bool finished = false}) {
  final j = Journal('a1b2-session', workflow: 'flow', snapshot: false);
  for (final (i, name) in names.indexed) {
    j.effect(name, i + 1, end: i + 1.5, place: flowAt(name));
  }
  if (finished) j.finish(names.length + 1);
  return j;
}

void main() {
  test('none: no fork passed, no edge taken or untaken', () {
    expect(Passes.none.of('1'), 0);
    expect(Passes.none.taken(0), isFalse);
    expect(Passes.none.untaken(0), isFalse);
  });

  group('forks', () {
    // a → (c ? b : d)
    final s = Shape(
      [effectAt('a'), forkAt('c'), effectAt('b'), effectAt('d')],
      ['>a', 'a>c', 'c>b', 'c>d', 'b>', 'd>'],
    );

    test('if: the fork is passed once, its exit to the effect after it is '
        'taken, the other untaken', () {
      final p = s.passes(ran(['a', 'b']).data);
      expect(s.forksOf(p), {'c': 1});
      expect(s.takenBy(p), {'>a', 'a>c', 'c>b'});
      expect(s.untakenBy(p), {'c>d'});

      final q = s.passes(ran(['a', 'd']).data);
      expect(s.forksOf(q), {'c': 1});
      expect(s.takenBy(q), {'>a', 'a>c', 'c>d'});
      expect(s.untakenBy(q), {'c>b'});
    });

    test('a fork is not passed before the effect after it runs', () {
      final p = s.passes(ran(['a']).data);

      expect(s.forksOf(p), isEmpty);
      expect(s.takenBy(p), {'>a'});
      expect(s.untakenBy(p), isEmpty);
    });

    test('switch with three cases: only the case taken has its edge taken', () {
      final t = Shape(
        [
          effectAt('a'),
          forkAt('s'),
          effectAt('x'),
          effectAt('y'),
          effectAt('z'),
        ],
        ['>a', 'a>s', 's>x', 's>y', 's>z', 'x>', 'y>', 'z>'],
      );
      final p = t.passes(ran(['a', 'y']).data);

      expect(t.forksOf(p), {'s': 1});
      expect(t.takenBy(p), {'>a', 'a>s', 's>y'});
      expect(t.untakenBy(p), {'s>x', 's>z'});
    });

    test('two forks that merge before the next effect: the fork on every '
        'path is passed, the one on some is not, and an exit on some paths '
        'is neither taken nor untaken', () {
      // a → f1 → (g | f2 → (h | g))
      final t = Shape(
        [
          effectAt('a'),
          forkAt('f1'),
          forkAt('f2'),
          effectAt('g'),
          effectAt('h'),
        ],
        ['>a', 'a>f1', 'f1>g', 'f1>f2', 'f2>h', 'f2>g', 'g>', 'h>'],
      );
      final p = t.passes(ran(['a', 'g']).data);

      expect(t.forksOf(p), {'f1': 1});
      expect(t.takenBy(p), {'>a', 'a>f1'});
      // One of f1's exits was taken, which one the journal does not tell.
      expect(t.untakenBy(p), isEmpty);
    });

    test('a call that ran no effects on the way does not stop the path', () {
      // a → helper() → (f ? b : d); helper holds no effects.
      final helper = graphFunction('helper', [], ['>']);
      final t = Shape(
        [
          effectAt('a'),
          callAt('h', helper),
          forkAt('f'),
          effectAt('b'),
          effectAt('d'),
        ],
        ['>a', 'a>h', 'h>f', 'f>b', 'f>d', 'b>', 'd>'],
        called: [helper],
      );
      final p = t.passes(ran(['a', 'b']).data);

      expect(t.forksOf(p), {'f': 1});
      expect(t.takenBy(p), {'>a', 'a>h', 'h>f', 'f>b'});
      expect(t.untakenBy(p), {'f>d'});
    });

    test('a loop of one effect goes round from the effect to itself', () {
      // while (…) a
      final t = Shape([forkAt('w'), effectAt('a')], ['>w', 'w>a', 'a>w', 'w>']);
      final p = t.passes(ran(['a', 'a', 'a']).data);

      expect(t.forksOf(p), {'w': 3});
      expect(t.takenBy(p), {'>w', 'w>a', 'a>w'});
      // The session runs, and the third a has finished: the code may have
      // left the loop since.
      expect(t.untakenBy(p), isEmpty);

      // While the third a runs, the code has gone nowhere from it.
      final j = ran(['a', 'a'])..effect('a', 3, place: flowAt('a'));
      final running = t.passes(j.data);
      expect(t.forksOf(running), {'w': 3});
      expect(t.untakenBy(running), {'w>'});
    });

    test('a loop whose rounds run no effect: no exit the code may have taken '
        'round it is untaken', () {
      // describe's sendParts: for (…) { if (part.isEmpty) continue; send;
      // if (!sent) break; } close. 1 is the loop, 2 `isEmpty`, 3 send, 4
      // `!sent`, 5 close.
      final file = loadGraphFile('control');
      final sendParts = file.functions['lib/backup.dart#sendParts']!;
      final t = Shape.of(
        sendParts.body,
        places: EffectPlaces.of(sendParts, file.functions),
      );
      String placeOf(String name) => sendParts.body.nodes
          .whereType<EffectNode>()
          .singleWhere((node) => node.name == name)
          .place!;
      Passes sent(List<String> parts) {
        final j = Journal(
          'a1b2-session',
          workflow: 'sendParts',
          snapshot: false,
        );
        for (final (i, part) in parts.indexed) {
          if (part.isEmpty) continue;
          j.effect('send', i + 1, end: i + 1.5, place: placeOf('send'));
        }
        j
          ..effect(
            'close',
            parts.length + 1,
            end: parts.length + 2,
            place: placeOf('close'),
          )
          ..finish(parts.length + 3);
        return t.passes(j.data);
      }

      // An empty part first: the `continue` (2>1) and the next round (1>2),
      // then send, the next round (4>1) and the loop's end (1>5).
      final skipped = sent(['', 'x']);
      expect(t.forksOf(skipped), {'1': 1, '2': 1, '4': 1});
      expect(t.takenBy(skipped), {'>1', '1>2', '2>3', '3>4', '5>'});
      expect(t.untakenBy(skipped), isEmpty);

      // Two parts sent: round and round, then the loop's end (1>5).
      final both = sent(['x', 'y']);
      expect(t.forksOf(both), {'1': 2, '2': 2, '4': 2});
      expect(t.takenBy(both), {'>1', '1>2', '2>3', '3>4', '4>1', '5>'});
      expect(t.untakenBy(both), isEmpty);
    });

    test('effects side by side after one effect passed the forks before them '
        'once: the code after an effect ran once', () {
      // a → f → (b ‖ c)
      final t = Shape(
        [effectAt('a'), forkAt('f'), effectAt('b'), effectAt('c')],
        ['>a', 'a>f', 'f>b', 'f>c', 'b>', 'c>'],
      );
      final j = ran(['a']);
      final a = j.effects.single.key;
      j
        ..effect('b', 2, end: 3, place: flowAt('b'), after: a)
        ..effect('c', 2, end: 3, place: flowAt('c'), after: a);
      final p = t.passes(j.data);

      expect(t.forksOf(p), {'f': 1});
      expect(t.takenBy(p), {'>a', 'a>f', 'f>b', 'f>c'});
      expect(t.untakenBy(p), isEmpty);
    });
  });

  group('the review loop', () {
    // collect → (change.path.isEmpty ? discard : loop { inspect →
    // (report.findings.isEmpty ? publish ‖ notify : fix) }), as the example's
    // graph file draws it.
    final file = loadGraphFile('review');
    final review = file.functions['lib/review.dart#review']!;
    final s = Shape.of(
      review.body,
      places: EffectPlaces.of(review, file.functions),
    );
    String placeOf(String name) => review.body.nodes
        .whereType<EffectNode>()
        .singleWhere((node) => node.name == name)
        .place!;

    test('collect, inspect, fix, inspect, then publish and notify side by '
        'side: the empty change fork once by its false edge, the findings '
        'fork twice by all its edges, the back edge', () {
      const loop = ['collect', 'inspect', 'fix', 'inspect'];
      final j = Journal('a1b2-session', snapshot: false);
      for (final (i, name) in loop.indexed) {
        j.effect(name, i + 1, end: i + 1.5, place: placeOf(name));
      }
      // Both after the second inspect, as the library keys them.
      final inspected = j.effects.last.key;
      j
        ..effect(
          'publish',
          5,
          end: 6,
          place: placeOf('publish'),
          after: inspected,
        )
        ..effect(
          'notify',
          5,
          end: 6,
          place: placeOf('notify'),
          after: inspected,
        );
      final p = s.passes(j.data);

      // 2 is `change.path.isEmpty`, 5 is `report.findings.isEmpty`; 3 is
      // discard, 4 inspect, 6 publish, 7 notify, 8 fix.
      expect(s.forksOf(p), {'2': 1, '5': 2});
      expect(s.takenBy(p), {
        '>1',
        '1>2',
        '2>4', // false
        '4>5',
        '5>6', // true
        '5>7', // true
        '5>8', // false
        '8>4', // the back edge
      });
      expect(s.untakenBy(p), {'2>3'});
    });

    test('a branch that changes nothing: collect, discard', () {
      final j = Journal('a1b2-session', snapshot: false)
        ..effect('collect', 1, end: 2, place: placeOf('collect'))
        ..effect('discard', 3, end: 4, place: placeOf('discard'));
      final p = s.passes(j.data);

      expect(s.forksOf(p), {'2': 1});
      expect(s.takenBy(p), {'>1', '1>2', '2>3'});
      expect(s.untakenBy(p), {'2>4'});
    });
  });

  group('the level of a function', () {
    // release: plan → publish() → announce; publish: (f ? x : y) → (g ?
    // z : end).
    final publish = graphFunction(
      'publish',
      [forkAt('f'), effectAt('x'), effectAt('y'), forkAt('g'), effectAt('z')],
      ['>f', 'f>x', 'f>y', 'x>g', 'y>g', 'g>z', 'g>', 'z>'],
    );
    final release = graphFunction(
      'release',
      [effectAt('plan'), callAt('c', publish), effectAt('announce')],
      ['>plan', 'plan>c', 'c>announce', 'announce>'],
    );
    final s = Shape.of(
      publish.body,
      places: EffectPlaces.of(release, {
        release.id: release,
        publish.id: publish,
      }),
    );

    test("an effect entered from outside comes along the path from the body's "
        'start', () {
      final p = s.passes(ran(['plan', 'x']).data);

      expect(s.forksOf(p), {'f': 1});
      expect(s.takenBy(p), {'>f', 'f>x'});
      // While the session runs, another call may have begun since and gone
      // by f>y, its effect not started yet.
      expect(s.untakenBy(p), isEmpty);

      final finished = s.passes(ran(['plan', 'x'], finished: true).data);
      expect(s.untakenBy(finished), contains('f>y'));
    });

    test("an effect followed by one outside goes along the path to the body's "
        'end', () {
      // announce after y, as `return f.effect('y', …)` in publish would key
      // it.
      final p = s.passes(ran(['plan', 'y', 'announce']).data);

      expect(s.forksOf(p), {'f': 1, 'g': 1});
      expect(s.takenBy(p), {'>f', 'f>y', 'y>g', 'g>'});
      // While the session runs, another call may have begun by f>x.
      expect(s.untakenBy(p), {'g>z'});

      final finished = s.passes(
        ran(['plan', 'y', 'announce'], finished: true).data,
      );
      expect(s.untakenBy(finished), {'f>x', 'g>z'});
    });

    test('effects outside the level, one after the other, are no transition '
        'on it', () {
      final p = s.passes(ran(['plan', 'announce']).data);

      expect(s.forksOf(p), isEmpty);
      expect(s.takenBy(p), isEmpty);
    });
  });

  group('calls one after the other with no effect between them', () {
    /// The places of [helper]'s effects, called from a loop of `flow`:
    /// `for (t in ts) helper(t)`.
    EffectPlaces calledInALoop(GraphFunction helper) {
      final flow = graphFunction(
        'flow',
        [forkAt('for'), callAt('h', helper)],
        ['>for', 'for>h', 'h>for', 'for>'],
      );
      return EffectPlaces.of(flow, {flow.id: flow, helper.id: helper});
    }

    // helper: e1 → (c ? e2 : end).
    final helper = graphFunction(
      'helper',
      [effectAt('e1'), forkAt('c'), effectAt('e2')],
      ['>e1', 'e1>c', 'c>e2', 'c>', 'e2>'],
    );
    final s = Shape.of(helper.body, places: calledInALoop(helper));

    test('the code left the body after the first call and came into it '
        'again: c passed by both calls, by false then by true, and neither '
        'exit is darker', () {
      final p = s.passes(ran(['e1', 'e1', 'e2'], finished: true).data);

      expect(s.forksOf(p), {'c': 2});
      expect(s.takenBy(p), {'>e1', 'e1>c', 'c>', 'c>e2', 'e2>'});
      expect(s.untakenBy(p), isEmpty);
    });

    test('only when there is a way out of the body and a way back in: e2 '
        'again after e2 marks nothing, not even the way out', () {
      final p = s.passes(ran(['e1', 'e2', 'e2']).data);

      expect(s.forksOf(p), {'c': 1});
      expect(s.takenBy(p), {'>e1', 'e1>c', 'c>e2'});
      // e2 holds two effects: the function may have run more than once, so
      // no exit of its body is darker.
      expect(s.untakenBy(p), isEmpty);
    });

    test('the effects side by side at the start of the next call are one '
        'run back into the body', () {
      // helper: (f ? x ‖ y : ) → p, the next call's x and y after p.
      final helper = graphFunction(
        'helper',
        [forkAt('f'), effectAt('x'), effectAt('y'), effectAt('p')],
        ['>f', 'f>x', 'f>y', 'f>p', 'x>p', 'y>p', 'p>'],
      );
      final s = Shape.of(helper.body, places: calledInALoop(helper));
      final j = Journal('a1b2-session', workflow: 'flow', snapshot: false)
        ..effect('p', 1, end: 2, place: flowAt('p'), key: 'p1', after: null)
        ..effect('x', 3, end: 4, place: flowAt('x'), key: 'x', after: 'p1')
        ..effect('y', 3, end: 4, place: flowAt('y'), key: 'y', after: 'p1')
        ..effect('p', 5, end: 6, place: flowAt('p'), key: 'p2', after: 'p1');
      final p = s.passes(j.data);

      expect(s.forksOf(p), {'f': 2});
      expect(s.untakenBy(p), isEmpty);

      // A third call, the same way.
      j
        ..effect('x', 7, end: 8, place: flowAt('x'), key: 'x3', after: 'p2')
        ..effect('y', 7, end: 8, place: flowAt('y'), key: 'y3', after: 'p2')
        ..effect('p', 9, end: 10, place: flowAt('p'), key: 'p3', after: 'p2');
      final third = s.passes(j.data);

      expect(s.forksOf(third), {'f': 3});
      expect(s.untakenBy(third), isEmpty);
    });

    test('two calls side by side are no wait: await p(); await '
        'Future.wait([build(core, gen: true), build(tool, gen: false)]), '
        'build { if (gen) await generate(); await compile(); } — c passed by '
        'both calls, neither exit darker', () {
      final build = graphFunction(
        'build',
        [forkAt('c'), effectAt('generate'), effectAt('compile')],
        ['>c', 'c>generate', 'c>compile', 'generate>compile', 'compile>'],
      );
      final flow = graphFunction(
        'flow',
        [effectAt('p'), callAt('core', build), callAt('tool', build)],
        ['>p', 'p>core', 'p>tool', 'core>', 'tool>'],
      );
      final s = Shape.of(
        build.body,
        places: EffectPlaces.of(flow, {flow.id: flow, build.id: build}),
      );
      // The first effects of both calls come after p, core's first; tool's
      // compile started before core's generate finished, so no wait joined
      // generate before it.
      final j = Journal('a1b2-session', workflow: 'flow', snapshot: false)
        ..effect('p', 1, end: 2, place: flowAt('p'), key: 'p', after: null)
        ..effect(
          'generate',
          3,
          end: 4,
          place: flowAt('generate'),
          key: 'generate core',
          after: 'p',
        )
        ..effect(
          'compile',
          3,
          end: 4,
          place: flowAt('compile'),
          key: 'compile tool',
          after: 'p',
        )
        ..effect(
          'compile',
          5,
          end: 6,
          place: flowAt('compile'),
          key: 'compile core',
          after: 'generate core',
        )
        ..finish(7);
      final p = s.passes(j.data);

      expect(s.forksOf(p), {'c': 2});
      expect(s.takenBy(p), {
        '>c',
        'c>generate',
        'c>compile',
        'generate>compile',
        'compile>',
      });
      expect(s.untakenBy(p), isEmpty);
    });

    test('two calls side by side after an earlier one: await helper(); await '
        'Future.wait([helper(), helper()]), helper { if (c) await b(); if '
        '(d) await a(); } — d passed by all three calls', () {
      final helper = graphFunction(
        'helper',
        [forkAt('c'), effectAt('b'), forkAt('d'), effectAt('a')],
        ['>c', 'c>b', 'c>d', 'b>d', 'd>a', 'd>', 'a>'],
      );
      final flow = graphFunction(
        'flow',
        [callAt('h1', helper), callAt('h2', helper), callAt('h3', helper)],
        ['>h1', 'h1>h2', 'h1>h3', 'h2>', 'h3>'],
      );
      final s = Shape.of(
        helper.body,
        places: EffectPlaces.of(flow, {flow.id: flow, helper.id: helper}),
      );
      // The first call runs a; of the two after it, one runs b, the other a.
      final j = Journal('a1b2-session', workflow: 'flow', snapshot: false)
        ..effect('a', 1, end: 2, place: flowAt('a'), key: 'a1', after: null)
        ..effect('b', 3, end: 4, place: flowAt('b'), key: 'b2', after: 'a1')
        ..effect('a', 3, end: 4, place: flowAt('a'), key: 'a3', after: 'a1')
        ..finish(5);
      final p = s.passes(j.data);

      // c counts the two calls coming in side by side as one way back into
      // the body, as it counts effects side by side at the start of one
      // call above.
      expect(s.forksOf(p)['d'], 3);
      expect(s.untakenBy(p), isEmpty);
    });

    // if (c) { await a(); if (k) return; await Future.wait([x(), y()]); }
    // await e(); — x, y and e all after a, as the library keys the effect
    // after a wait.
    final waits = graphFunction(
      'waits',
      [
        forkAt('c'),
        effectAt('a'),
        forkAt('k'),
        effectAt('x'),
        effectAt('y'),
        effectAt('e'),
      ],
      ['>c', 'c>a', 'c>e', 'a>k', 'k>', 'k>x', 'k>y', 'x>e', 'y>e', 'e>'],
    );
    Journal waited() {
      final j = Journal('a1b2-session', workflow: 'flow', snapshot: false)
        ..effect('a', 1, end: 2, place: flowAt('a'), key: 'a', after: null);
      for (final name in ['x', 'y']) {
        j.effect(name, 3, end: 4, place: flowAt(name), key: name, after: 'a');
      }
      j.effect('e', 5, end: 6, place: flowAt('e'), key: 'e', after: 'a');
      return j..finish(7);
    }

    test('an effect after a wait comes after the effect before it, as the '
        'next call\'s first would: not split when an effect waited for '
        'leads to it', () {
      final s = Shape.of(waits.body, places: calledInALoop(waits));
      final p = s.passes(waited().data);

      expect(s.forksOf(p), {'c': 1, 'k': 1});
      // The next call may have begun at e all the same: the ways out of the
      // body after a and into it to e are not darker.
      expect(s.untakenBy(p), isEmpty);
    });

    test('the workflow\'s body is not split: run once, the wait marks what it '
        'did before the split existed', () {
      final s = Shape.of(
        waits.body,
        places: EffectPlaces.of(waits, {waits.id: waits}),
      );
      final p = s.passes(waited().data);

      expect(s.forksOf(p), {'c': 1, 'k': 1});
      expect(s.untakenBy(p), {'c>e', 'k>'});
    });

    test(
      'nor is a stale workflow\'s: x then y on `if (c) y; x; if (e) w;`',
      () {
        final s = Shape(
          [
            forkAt('c'),
            effectAt('y'),
            effectAt('x'),
            forkAt('e'),
            effectAt('w'),
          ],
          ['>c', 'c>y', 'c>x', 'y>x', 'x>e', 'e>w', 'e>', 'w>'],
        );
        final p = s.passes(ran(['x', 'y']).data);

        expect(s.forksOf(p), {'c': 1});
        expect(s.untakenBy(p), {'c>y'});
      },
    );

    test('a way through the body is there, and the code may have left it and '
        'come into it again: publish(pkg) { if (needsBuild) build(); if '
        '(isPublic) upload(); }, pkg 1 built and not public, pkg 2 uploaded '
        'unbuilt — no false exit darker', () {
      final publish = graphFunction(
        'publish',
        [forkAt('b'), effectAt('build'), forkAt('p'), effectAt('upload')],
        ['>b', 'b>build', 'b>p', 'build>p', 'p>upload', 'p>', 'upload>'],
      );
      final s = Shape.of(publish.body, places: calledInALoop(publish));
      final p = s.passes(ran(['build', 'upload'], finished: true).data);

      // What the way through the body passed and took: one run.
      expect(s.forksOf(p), {'b': 1, 'p': 1});
      expect(s.takenBy(p), {'>b', 'b>build', 'build>p', 'p>upload', 'upload>'});
      expect(s.untakenBy(p), isEmpty);
    });

    test('a loop a running session is still in: an earlier call left it by '
        'done, which is not darker', () {
      // helper: while (w) e;
      final helper = graphFunction(
        'helper',
        [forkAt('w'), effectAt('e')],
        ['>w', 'w>e', 'e>w', 'w>'],
      );
      final s = Shape.of(helper.body, places: calledInALoop(helper));
      final p = s.passes(ran(['e', 'e', 'e']).data);

      expect(s.forksOf(p), {'w': 3});
      expect(s.untakenBy(p), isEmpty);
    });

    test('the effects a wait joined lead to the effect after it, not the '
        'effect before the wait: await p(); await Future.wait([lint(), '
        'test()]); if (ok) await deploy();', () {
      final s = Shape(
        [
          effectAt('p'),
          effectAt('lint'),
          effectAt('test'),
          forkAt('ok'),
          effectAt('deploy'),
        ],
        [
          '>p',
          'p>lint',
          'p>test',
          'lint>ok',
          'test>ok',
          'ok>deploy',
          'ok>',
          'deploy>',
        ],
      );
      final j = Journal('a1b2-session', workflow: 'flow', snapshot: false)
        ..effect('p', 1, end: 2, place: flowAt('p'), key: 'p', after: null)
        ..effect('lint', 3, end: 4, place: flowAt('lint'), key: 'l', after: 'p')
        ..effect('test', 3, end: 4, place: flowAt('test'), key: 't', after: 'p')
        ..effect('deploy', 5, end: 6, place: flowAt('deploy'), after: 'p')
        ..finish(7);
      final p = s.passes(j.data);

      // Once, by the two joined; lint and test go nowhere after it.
      expect(s.forksOf(p), {'ok': 1});
      expect(s.takenBy(p), {
        '>p',
        'p>lint',
        'p>test',
        'lint>ok',
        'test>ok',
        'ok>deploy',
        'deploy>',
      });
      expect(s.untakenBy(p), {'ok>'});
    });

    group('calls that begin with a wait: for (env in envs) await '
        'deploy(env), deploy { await Future.wait(hosts.map(push)); if '
        '(notify) await notify(); }', () {
      final deploy = graphFunction(
        'deploy',
        [
          copiesNode(
            'c',
            GraphBody(
              nodes: [effectAt('push')],
              edges: [_edge('>push'), _edge('push>')],
            ),
          ),
          forkAt('n'),
          effectAt('notify'),
        ],
        ['>c', 'c>n', 'n>notify', 'n>', 'notify>'],
      );
      final s = Shape.of(deploy.body, places: calledInALoop(deploy));

      /// The calls, each pushing to [hosts] and notifying or not as
      /// [notifies] says; the session finished. A call's effects come after
      /// the last effect before the call, as the library keys them.
      Journal deploys(List<bool> notifies, {int hosts = 2}) {
        final j = Journal('a1b2-session', workflow: 'flow', snapshot: false);
        String? last;
        var t = 1;
        for (final (call, notify) in notifies.indexed) {
          for (var h = 0; h < hosts; h++) {
            j.effect(
              'push',
              t,
              end: t + 0.5,
              place: flowAt('push'),
              key: 'push $call $h',
              after: last,
            );
          }
          t++;
          if (notify) {
            j.effect(
              'notify',
              t,
              end: t + 0.5,
              place: flowAt('notify'),
              key: 'notify $call',
              after: last,
            );
            last = 'notify $call';
            t++;
          }
        }
        return j..finish(t);
      }

      test('every call notifies: n passed by each', () {
        final p = s.passes(deploys([true, true, true]).data);

        expect(s.forksOf(p), {'n': 3});
      });

      test('the second does not: n passed by the other two, and its false '
          'exit, which the second took, is not darker', () {
        final p = s.passes(deploys([true, false, true]).data);

        expect(s.forksOf(p)['n'], greaterThanOrEqualTo(2));
        expect(s.untakenBy(p), isNot(contains('n>')));
      });

      test('a thousand hosts in each call: the effects after one effect are '
          'looked at by their nodes, not each against each', () {
        final p = s.passes(deploys([true, true, true], hosts: 1000).data);

        expect(s.forksOf(p), {'n': 3});
      });
    });

    test('the first call begins the session with a wait: helper { await '
        'Future.wait([x(), y()]); if (k) await z(); }, twice — the first '
        "call's effects all after nothing, k passed by each call", () {
      final helper = graphFunction(
        'helper',
        [effectAt('x'), effectAt('y'), forkAt('k'), effectAt('z')],
        ['>x', '>y', 'x>k', 'y>k', 'k>z', 'k>', 'z>'],
      );
      final s = Shape.of(helper.body, places: calledInALoop(helper));
      final j = Journal('a1b2-session', workflow: 'flow', snapshot: false);
      String? last;
      for (final call in [1, 2]) {
        final t = call * 4;
        for (final name in ['x', 'y']) {
          j.effect(
            name,
            t,
            end: t + 1,
            place: flowAt(name),
            key: '$name$call',
            after: last,
          );
        }
        j.effect(
          'z',
          t + 2,
          end: t + 3,
          place: flowAt('z'),
          key: 'z$call',
          after: last,
        );
        last = 'z$call';
      }
      j.finish(13);
      final p = s.passes(j.data);

      expect(s.forksOf(p), {'k': 2});
      // Both calls went on to z, but x, y and z hold two effects each: the
      // function may have run more than once, so k> is not darker.
      expect(s.untakenBy(p), isEmpty);
    });

    test('the end of a call in a call is not the way into the next call: '
        'helper { if (c) await sub(); await e(); await sub(); }, sub { x; y '
        '}, twice, c false — the first sub (s1) was not left for e', () {
      final sub = graphFunction(
        'sub',
        [effectAt('x'), effectAt('y')],
        ['>x', 'x>y', 'y>'],
      );
      final helper = graphFunction(
        'helper',
        [forkAt('c'), callAt('s1', sub), effectAt('e'), callAt('s2', sub)],
        ['>c', 'c>s1', 'c>e', 's1>e', 'e>s2', 's2>'],
      );
      final flow = graphFunction(
        'flow',
        [effectAt('pre'), forkAt('for'), callAt('h', helper)],
        ['>pre', 'pre>for', 'for>h', 'h>for', 'for>'],
      );
      final s = Shape.of(
        helper.body,
        places: EffectPlaces.of(flow, {
          flow.id: flow,
          helper.id: helper,
          sub.id: sub,
        }),
      );
      // As the library keys it: e after pre in each call, sub's effects
      // after e.
      final j = Journal('a1b2-session', workflow: 'flow', snapshot: false)
        ..effect('pre', 0, end: 0.5, place: flowAt('pre'), key: 'pre');
      for (final call in [1, 2]) {
        final t = call * 10;
        j
          ..effect(
            'e',
            t,
            end: t + 1,
            place: flowAt('e'),
            key: 'e$call',
            after: 'pre',
          )
          ..effect('x', t + 2, end: t + 3, place: flowAt('x'), key: 'x$call')
          ..effect('y', t + 4, end: t + 5, place: flowAt('y'), key: 'y$call');
      }
      j.finish(30);
      final p = s.passes(j.data);

      expect(s.takenBy(p), isNot(contains('s1>e')));
      expect(s.takenBy(p), containsAll(['>c', 'e>s2', 's2>']));
    });

    test('for (pkg in pkgs) await publish(f, pkg): core goes on, tool rolls '
        'back — !ok passed by both, neither exit darker', () {
      final publish = loadGraphFile('release')
          .functions['lib/publish.dart#publish']!;
      final s = Shape.of(publish.body, places: calledInALoop(publish));
      final j = Journal('a1b2-session', workflow: 'flow', snapshot: false);
      for (final (i, (name, line)) in [
        ('upload', 12),
        ('verify', 13),
        ('upload', 12),
        ('verify', 13),
        ('rollback', 14),
      ].indexed) {
        j.effect(name, i + 1, end: i + 1.5, place: 'lib/publish.dart:$line');
      }
      j.finish(7);
      final p = s.passes(j.data);

      // upload → verify → (!ok ? rollback : end): 3 is !ok, 4 rollback.
      expect(s.forksOf(p), {'3': 2});
      expect(s.takenBy(p), {'>1', '1>2', '2>3', '3>', '3>4', '4>'});
      expect(s.untakenBy(p), isEmpty);
    });
  });

  group('a called body: an exit is darker only when no effect node of it '
      'holds more than one effect — needed for the function to have run once '
      'at most, not enough', () {
    // How many times the code came into a called body the journal does not
    // tell for sure: a wait does not move `after`, and a call that takes no
    // effect's result leaves all its effects after the caller's last one. So
    // the effects of one call can read as joined before an effect of the
    // next, and the way an earlier call took out of the body is lost. Calls
    // whose waits ran on different effect nodes leave each node one effect,
    // and can still darken an exit an earlier call took (passes.dart,
    // «Darker exits»).

    /// The places of [helper]'s effects, called from `flow`: `[await pre();]
    /// for (t in ts) await helper(t);`.
    EffectPlaces calledInALoop(GraphFunction helper) {
      final flow = graphFunction(
        'flow',
        [effectAt('pre'), forkAt('for'), callAt('h', helper)],
        ['>pre', 'pre>for', 'for>h', 'h>for', 'for>'],
      );
      return EffectPlaces.of(flow, {flow.id: flow, helper.id: helper});
    }

    // helper { await Future.wait([x(), y()]); if (k) await z(); }
    final helper = graphFunction(
      'helper',
      [effectAt('x'), effectAt('y'), forkAt('k'), effectAt('z')],
      ['>x', '>y', 'x>k', 'y>k', 'k>z', 'k>', 'z>'],
    );
    final s = Shape.of(helper.body, places: calledInALoop(helper));

    /// The calls of helper, each going on to z when [ks] says so. Their
    /// effects come after [before], the effect before the loop, or none when
    /// the loop begins the session; when [takesZ], the loop takes z's result,
    /// and the calls after one that ran z come after that z.
    Journal calls(
      List<bool> ks, {
      required String? before,
      required bool takesZ,
      required bool finished,
    }) {
      final j = Journal('a1b2-session', workflow: 'flow', snapshot: false);
      if (before != null) {
        j.effect(
          'pre',
          0,
          end: 0.5,
          place: flowAt('pre'),
          key: before,
          after: null,
        );
      }
      var last = before;
      var t = 1;
      for (final (call, k) in ks.indexed) {
        for (final name in ['x', 'y']) {
          j.effect(
            name,
            t,
            end: t + 1,
            place: flowAt(name),
            key: '$name$call',
            after: last,
          );
        }
        t += 2;
        if (k) {
          j.effect(
            'z',
            t,
            end: t + 1,
            place: flowAt('z'),
            key: 'z$call',
            after: last,
          );
          if (takesZ) last = 'z$call';
          t += 2;
        }
      }
      if (finished) j.finish(t);
      return j;
    }

    /// The passes of helper's body over [calls] of [ks], each way the
    /// library may key them, finished and running, with a reason naming it.
    Iterable<(Passes, String)> everyWay(List<bool> ks) sync* {
      for (final before in [null, 'pre']) {
        for (final takesZ in [false, true]) {
          for (final finished in [true, false]) {
            final journal = calls(
              ks,
              before: before,
              takesZ: takesZ,
              finished: finished,
            );
            yield (
              s.passes(journal.data),
              'after $before, z taken: $takesZ, finished: $finished',
            );
          }
        }
      }
    }

    test('helper called one call after another, the calls going out of k by '
        'both exits: neither exit is darker, and k is passed', () {
      for (final ks in [
        [false, true],
        [false, false, true],
        [true, false],
      ]) {
        for (final (p, reason) in everyWay(ks)) {
          expect(s.untakenBy(p), isEmpty, reason: 'k: $ks, $reason');
          // How many times, the journal does not tell for sure.
          expect(s.forksOf(p)['k'], isNotNull, reason: 'k: $ks, $reason');
        }
      }
    });

    test('helper called twice, both calls going out of k by one exit: the '
        'other is not darker either, though no call took it — x and y hold '
        'two effects each', () {
      for (final ks in [
        [true, true],
        [false, false],
      ]) {
        for (final (p, reason) in everyWay(ks)) {
          expect(s.untakenBy(p), isEmpty, reason: 'k: $ks, $reason');
        }
      }
    });

    test('a function called once whose loop runs an effect again: helper { '
        'while (w) { await e(); if (k) await z(); } }, e three times, z '
        'never — k>z is not darker on its body, as the rounds of a loop read '
        'as calls one after the other would; on a workflow, run once, it '
        'is', () {
      final nodes = [forkAt('w'), effectAt('e'), forkAt('k'), effectAt('z')];
      final edges = ['>w', 'w>e', 'e>k', 'k>z', 'k>w', 'z>w', 'w>'];
      final helper = graphFunction('helper', nodes, edges);
      final flow = graphFunction('flow', [callAt('h', helper)], ['>h', 'h>']);
      final called = Shape.of(
        helper.body,
        places: EffectPlaces.of(flow, {flow.id: flow, helper.id: helper}),
      );
      final workflow = Shape(nodes, edges);
      final j = ran(['e', 'e', 'e'], finished: true);

      final p = called.passes(j.data);
      expect(called.forksOf(p), {'w': 4, 'k': 3});
      expect(called.takenBy(p), {'>w', 'w>e', 'e>k', 'k>w', 'w>'});
      expect(called.untakenBy(p), isEmpty);

      final once = workflow.passes(j.data);
      expect(workflow.forksOf(once), {'w': 4, 'k': 3});
      expect(workflow.untakenBy(once), {'k>z'});
    });
  });

  group('after a wait', () {
    test('a session that begins with the wait: await Future.wait([lint(), '
        'test()]); if (ok) await deploy(); — all three after nothing, deploy '
        'after the two joined', () {
      final s = Shape(
        [effectAt('lint'), effectAt('test'), forkAt('ok'), effectAt('deploy')],
        ['>lint', '>test', 'lint>ok', 'test>ok', 'ok>deploy', 'ok>', 'deploy>'],
      );
      final j = Journal('a1b2-session', workflow: 'flow', snapshot: false)
        ..effect(
          'lint',
          1,
          end: 2,
          place: flowAt('lint'),
          key: 'l',
          after: null,
        )
        ..effect(
          'test',
          1,
          end: 2,
          place: flowAt('test'),
          key: 't',
          after: null,
        )
        ..effect('deploy', 3, end: 4, place: flowAt('deploy'), after: null)
        ..finish(5);
      final p = s.passes(j.data);

      expect(s.forksOf(p), {'ok': 1});
      expect(s.takenBy(p), contains('ok>deploy'));
      expect(s.untakenBy(p), {'ok>'});
    });

    test('the effects side by side after one wait went through the fork '
        'before them once: [await p();] await Future.wait([lint(), test()]); '
        'if (ok) await Future.wait([eu(), us()]);', () {
      for (final afterP in [false, true]) {
        final s = Shape(
          [
            if (afterP) effectAt('p'),
            effectAt('lint'),
            effectAt('test'),
            forkAt('ok'),
            effectAt('eu'),
            effectAt('us'),
          ],
          [
            if (afterP) ...[
              '>p',
              'p>lint',
              'p>test',
            ] else ...[
              '>lint',
              '>test',
            ],
            'lint>ok',
            'test>ok',
            'ok>eu',
            'ok>us',
            'ok>',
            'eu>',
            'us>',
          ],
        );
        final before = afterP ? 'p' : null;
        final j = Journal('a1b2-session', workflow: 'flow', snapshot: false);
        if (afterP) j.effect('p', 0, end: 0.5, place: flowAt('p'), key: 'p');
        for (final (name, start) in [
          ('lint', 1),
          ('test', 1),
          ('eu', 3),
          ('us', 3),
        ]) {
          j.effect(
            name,
            start,
            end: start + 1,
            place: flowAt(name),
            key: name,
            after: before,
          );
        }
        j.finish(5);
        final passes = s.passes(j.data);

        expect(s.forksOf(passes), {'ok': 1}, reason: 'after p: $afterP');
        expect(s.untakenBy(passes), {'ok>'}, reason: 'after p: $afterP');
      }
    });

    test('a loop of waits: await p(); while (c) await Future.wait([x(), '
        'y()]); three rounds — c tested once before each round, and once '
        'more when the loop ends', () {
      final s = Shape(
        [effectAt('p'), forkAt('c'), effectAt('x'), effectAt('y')],
        ['>p', 'p>c', 'c>x', 'c>y', 'x>c', 'y>c', 'c>'],
      );
      Journal rounds({required bool finished}) {
        final j = Journal('a1b2-session', workflow: 'flow', snapshot: false)
          ..effect('p', 1, end: 2, place: flowAt('p'), key: 'p', after: null);
        for (var round = 0; round < 3; round++) {
          for (final name in ['x', 'y']) {
            j.effect(
              name,
              3 + 2 * round,
              end: 4 + 2 * round,
              place: flowAt(name),
              key: '$name$round',
              after: 'p',
            );
          }
        }
        if (finished) j.finish(9);
        return j;
      }

      // While it runs, where the code went after the third round is not
      // known.
      expect(s.forksOf(s.passes(rounds(finished: false).data)), {'c': 3});

      final finished = s.passes(rounds(finished: true).data);
      expect(s.forksOf(finished), {'c': 4});
      expect(s.untakenBy(finished), isEmpty);
    });
  });

  group('the end of the session', () {
    // a → (f ? b : end)
    final s = Shape(
      [effectAt('a'), forkAt('f'), effectAt('b')],
      ['>a', 'a>f', 'f>b', 'f>', 'b>'],
    );

    test("a finished session goes from its last effect to the workflow's "
        'end', () {
      final p = s.passes(ran(['a'], finished: true).data);

      expect(s.forksOf(p), {'f': 1});
      expect(s.takenBy(p), {'>a', 'a>f', 'f>'});
      expect(s.untakenBy(p), {'f>b'});
    });

    test('a running, a failed and an interrupted session do not go anywhere '
        'after their last effect', () {
      for (final j in [
        ran(['a']),
        ran(['a'])..fail(2, 'StateError: boom'),
        ran(['a'])..processGone(),
      ]) {
        final p = s.passes(j.data);

        expect(s.forksOf(p), isEmpty);
        expect(s.takenBy(p), {'>a'});
        expect(s.untakenBy(p), isEmpty);
      }
    });

    test('an effect another follows is not the last', () {
      final p = s.passes(ran(['a', 'b'], finished: true).data);

      expect(s.forksOf(p), {'f': 1}, reason: 'a → b only');
      expect(s.takenBy(p), {'>a', 'a>f', 'f>b', 'b>'});
      expect(s.untakenBy(p), {'f>'});
    });

    test('the last effect in a call goes from the call to the end', () {
      // helper() → (f ? end : b); helper: x → y
      final helper = graphFunction(
        'helper',
        [effectAt('x'), effectAt('y')],
        ['>x', 'x>y', 'y>'],
      );
      final t = Shape(
        [callAt('h', helper), forkAt('f'), effectAt('b')],
        ['>h', 'h>f', 'f>', 'f>b', 'b>'],
        called: [helper],
      );

      // x → y is inside the call: no transition on this level.
      final running = t.passes(ran(['x', 'y']).data);
      expect(t.forksOf(running), isEmpty);
      expect(t.takenBy(running), {'>h'});

      final finished = t.passes(ran(['x', 'y'], finished: true).data);
      expect(t.forksOf(finished), {'f': 1});
      expect(t.takenBy(finished), {'>h', 'h>f', 'f>'});
      expect(t.untakenBy(finished), {'f>b'});
    });
  });

  group('keyed as the library keys them: after an awaited call or closure, '
      'the code goes on with the `after` it had', () {
    test('a call whose last effect another follows in no `after`: plan; '
        'await publish(); if (f) await announce(); else if (g) await b(); — '
        'publish { upload; verify }, announce after plan; f passed once, g '
        'never', () {
      final publish = graphFunction(
        'publish',
        [effectAt('upload'), effectAt('verify')],
        ['>upload', 'upload>verify', 'verify>'],
      );
      final s = Shape(
        [
          effectAt('plan'),
          callAt('c', publish),
          forkAt('f'),
          effectAt('announce'),
          forkAt('g'),
          effectAt('b'),
        ],
        [
          '>plan',
          'plan>c',
          'c>f',
          'f>announce',
          'f>g',
          'g>b',
          'g>',
          'announce>',
          'b>',
        ],
        called: [publish],
      );
      // As the library keys it, and as `return f.effect('verify', …)` would.
      for (final after in ['plan', 'verify']) {
        final j = Journal('a1b2-session', workflow: 'flow', snapshot: false)
          ..effect('plan', 1, end: 2, place: flowAt('plan'), key: 'plan')
          ..effect('upload', 3, end: 4, place: flowAt('upload'), key: 'upload')
          ..effect('verify', 5, end: 6, place: flowAt('verify'), key: 'verify')
          ..effect(
            'announce',
            7,
            end: 8,
            place: flowAt('announce'),
            key: 'announce',
            after: after,
          )
          ..finish(9);
        final p = s.passes(j.data);

        expect(s.forksOf(p), {'f': 1}, reason: 'announce after $after');
        expect(s.takenBy(p), {
          '>plan',
          'plan>c',
          'c>f',
          'f>announce',
          'announce>',
        }, reason: 'announce after $after');
        expect(s.untakenBy(p), {'f>g'}, reason: 'announce after $after');
      }
    });

    test('a closure called in place, drawn in place: await a(); await (() '
        'async { await b(); await c(); })(); if (x) await d(); — d after a, '
        'x passed by x>d', () {
      final s = Shape(
        [
          effectAt('a'),
          effectAt('b'),
          effectAt('c'),
          forkAt('x'),
          effectAt('d'),
        ],
        ['>a', 'a>b', 'b>c', 'c>x', 'x>d', 'x>', 'd>'],
      );
      final j = Journal('a1b2-session', workflow: 'flow', snapshot: false)
        ..effect('a', 1, end: 2, place: flowAt('a'), key: 'a', after: null)
        ..effect('b', 3, end: 4, place: flowAt('b'), key: 'b', after: 'a')
        ..effect('c', 5, end: 6, place: flowAt('c'), key: 'c', after: 'b')
        ..effect('d', 7, end: 8, place: flowAt('d'), key: 'd', after: 'a')
        ..finish(9);
      final p = s.passes(j.data);

      expect(s.forksOf(p), {'x': 1});
      expect(s.takenBy(p), {'>a', 'a>b', 'b>c', 'c>x', 'x>d', 'd>'});
      expect(s.untakenBy(p), {'x>'});
    });

    test('a call beside an effect in a wait, two effects in a row: await p(); '
        'await Future.wait([x(), helper()]); if (k) await q(); — helper { y; '
        'z }, q after p; k passed once', () {
      final helper = graphFunction(
        'helper',
        [effectAt('y'), effectAt('z')],
        ['>y', 'y>z', 'z>'],
      );
      final s = Shape(
        [
          effectAt('p'),
          effectAt('x'),
          callAt('h', helper),
          forkAt('k'),
          effectAt('q'),
        ],
        ['>p', 'p>x', 'p>h', 'x>k', 'h>k', 'k>q', 'k>', 'q>'],
        called: [helper],
      );
      final j = Journal('a1b2-session', workflow: 'flow', snapshot: false)
        ..effect('p', 1, end: 2, place: flowAt('p'), key: 'p', after: null)
        ..effect('x', 3, end: 4, place: flowAt('x'), key: 'x', after: 'p')
        ..effect('y', 3, end: 4, place: flowAt('y'), key: 'y', after: 'p')
        ..effect('z', 5, end: 6, place: flowAt('z'), key: 'z', after: 'y')
        ..effect('q', 7, end: 8, place: flowAt('q'), key: 'q', after: 'p')
        ..finish(9);
      final p = s.passes(j.data);

      expect(s.forksOf(p), {'k': 1});
      expect(s.takenBy(p), containsAll(['x>k', 'h>k', 'k>q']));
      expect(s.untakenBy(p), {'k>'});
    });

    test("a call's ends inside it are no ends of the session: if (k) { await "
        'helper(); await z(); } else { await helper(); } — helper { a; await '
        '(() async { b; c })(); d }, k true; not out of the other call', () {
      final helper = graphFunction(
        'helper',
        [effectAt('a'), effectAt('b'), effectAt('c'), effectAt('d')],
        ['>a', 'a>b', 'b>c', 'c>d', 'd>'],
      );
      final s = Shape(
        [
          forkAt('k'),
          callAt('h1', helper),
          effectAt('z'),
          callAt('h2', helper),
        ],
        ['>k', 'k>h1', 'k>h2', 'h1>z', 'z>', 'h2>'],
        called: [helper],
      );
      final j = Journal('a1b2-session', workflow: 'flow', snapshot: false)
        ..effect('a', 1, end: 2, place: flowAt('a'), key: 'a', after: null)
        ..effect('b', 3, end: 4, place: flowAt('b'), key: 'b', after: 'a')
        ..effect('c', 5, end: 6, place: flowAt('c'), key: 'c', after: 'b')
        ..effect('d', 7, end: 8, place: flowAt('d'), key: 'd', after: 'a')
        ..effect('z', 9, end: 10, place: flowAt('z'), key: 'z', after: null)
        ..finish(11);
      final p = s.passes(j.data);

      expect(s.forksOf(p), {'k': 1});
      expect(s.takenBy(p), {'>k', 'h1>z', 'z>'});
      expect(s.untakenBy(p), isEmpty);
    });
  });

  group('effects not on the graph', () {
    // for (…) { if (u) { await retry(() => f.effect('fetch')); await
    // f.effect('apply'); } else { await f.effect('queue'); } }: fetch is in a
    // closure passed on, which describe does not draw.
    final s = Shape(
      [forkAt('for'), forkAt('u'), effectAt('apply'), effectAt('queue')],
      ['>for', 'for>u', 'u>apply', 'u>queue', 'apply>for', 'queue>for', 'for>'],
    );

    test('queue, fetch, apply: the way to apply the code went is not darker, '
        'whether retry hands fetch on — apply after fetch — or not — apply '
        'after queue', () {
      for (final applyAfter in ['fetch', 'queue']) {
        for (final finished in [true, false]) {
          final j = Journal('a1b2-session', workflow: 'flow', snapshot: false)
            ..effect('queue', 1, end: 2, place: flowAt('queue'), key: 'queue')
            ..effect('fetch', 3, end: 4, key: 'fetch', after: 'queue')
            ..effect(
              'apply',
              5,
              end: 6,
              place: flowAt('apply'),
              key: 'apply',
              after: applyAfter,
            );
          if (finished) j.finish(7);
          final p = s.passes(j.data);
          final reason = 'apply after $applyAfter, finished: $finished';

          expect(s.untakenBy(p), isNot(contains('u>apply')), reason: reason);
          expect(s.forksOf(p), contains('u'), reason: reason);
        }
      }
    });

    test('the effects a wait joined before one not on the graph lead to the '
        'effect after it: await Future.wait([a(), b()]); await handOn(() => '
        "f.effect('h')); if (c) await x(); — x after h; not from a and b to "
        'the end', () {
      final t = Shape(
        [effectAt('a'), effectAt('b'), forkAt('c'), effectAt('x')],
        ['>a', '>b', 'a>c', 'b>c', 'c>x', 'c>', 'x>'],
      );
      final j = Journal('a1b2-session', workflow: 'flow', snapshot: false)
        ..effect('a', 1, end: 2, place: flowAt('a'), key: 'a', after: null)
        ..effect('b', 1, end: 2, place: flowAt('b'), key: 'b', after: null)
        ..effect('h', 3, end: 4, key: 'h', after: null)
        ..effect('x', 5, end: 6, place: flowAt('x'), key: 'x', after: 'h')
        ..finish(7);
      final p = t.passes(j.data);

      // Where the code went through h is not drawn: c is not marked.
      expect(t.forksOf(p), isEmpty);
      expect(t.takenBy(p), {'>a', '>b', 'x>'});
      expect(t.untakenBy(p), isEmpty);
    });
  });

  group('a session that has not finished: running, failed, interrupted', () {
    List<Journal> ending(Journal Function() journal) => [
      journal(),
      journal()..fail(9, 'StateError: boom'),
      journal()..processGone(),
    ];

    test(
      'a workflow that fails between an exit and the effect after it: for '
      '(…) { await build(); if (needsCheck) { checkSync(); await report(); '
      '} } — checkSync throws in round 2; needsCheck>report is not darker',
      () {
        final s = Shape(
          [forkAt('for'), effectAt('build'), forkAt('n'), effectAt('report')],
          [
            '>for',
            'for>build',
            'build>n',
            'n>report',
            'n>for',
            'report>for',
            'for>',
          ],
        );
        for (final j in ending(() => ran(['build', 'build']))) {
          final p = s.passes(j.data);

          expect(s.forksOf(p), {'for': 2, 'n': 1});
          expect(s.untakenBy(p), isEmpty);
        }
      },
    );

    test('a function called again after an earlier call left it: helper { if '
        '(c) await x(); else await y(); if (k) await z(); } — the first call '
        'x and out by k>, the second y and z; k> is not darker', () {
      final helper = graphFunction(
        'helper',
        [forkAt('c'), effectAt('x'), effectAt('y'), forkAt('k'), effectAt('z')],
        ['>c', 'c>x', 'c>y', 'x>k', 'y>k', 'k>z', 'k>', 'z>'],
      );
      final flow = graphFunction(
        'flow',
        [effectAt('pre'), forkAt('for'), callAt('h', helper)],
        ['>pre', 'pre>for', 'for>h', 'h>for', 'for>'],
      );
      final s = Shape.of(
        helper.body,
        places: EffectPlaces.of(flow, {flow.id: flow, helper.id: helper}),
      );
      // As the library keys it, y after pre, and as it would were x's result
      // handed on.
      for (final yAfter in ['pre', 'x']) {
        Journal calls() =>
            Journal('a1b2-session', workflow: 'flow', snapshot: false)
              ..effect('pre', 0, end: 0.5, place: flowAt('pre'), key: 'pre')
              ..effect('x', 1, end: 2, place: flowAt('x'), key: 'x')
              ..effect(
                'y',
                3,
                end: 4,
                place: flowAt('y'),
                key: 'y',
                after: yAfter,
              )
              ..effect('z', 5, end: 6, place: flowAt('z'), key: 'z');
        for (final j in ending(calls)) {
          final p = s.passes(j.data);

          expect(
            s.untakenBy(p),
            isNot(contains('k>')),
            reason: 'y after $yAfter',
          );
        }
      }
    });
  });

  group('the ends of a wait', () {
    test(
      'a wait that opens the workflow passes a fork after it once: await '
      'Future.wait([lint(), test()]); if (ok) await deploy(); — ok false',
      () {
        final s = Shape(
          [
            effectAt('lint'),
            effectAt('test'),
            forkAt('ok'),
            effectAt('deploy'),
          ],
          [
            '>lint',
            '>test',
            'lint>ok',
            'test>ok',
            'ok>deploy',
            'ok>',
            'deploy>',
          ],
        );
        final j = Journal('a1b2-session', workflow: 'flow', snapshot: false)
          ..effect(
            'lint',
            1,
            end: 2,
            place: flowAt('lint'),
            key: 'l',
            after: null,
          )
          ..effect(
            'test',
            1,
            end: 2,
            place: flowAt('test'),
            key: 't',
            after: null,
          )
          ..finish(3);
        final p = s.passes(j.data);

        expect(s.forksOf(p), {'ok': 1});
        expect(s.takenBy(p), {'>lint', '>test', 'lint>ok', 'test>ok', 'ok>'});
        expect(s.untakenBy(p), {'ok>deploy'});
      },
    );

    test('the ends of a wait joined before the next wait are not joined again '
        'after it: await Future.wait([a(), b()]); if (c) await '
        'Future.wait([x(), y()]); await z(); — c true, z after nothing like '
        'all of them', () {
      final s = Shape(
        [
          effectAt('a'),
          effectAt('b'),
          forkAt('c'),
          effectAt('x'),
          effectAt('y'),
          effectAt('z'),
        ],
        ['>a', '>b', 'a>c', 'b>c', 'c>x', 'c>y', 'c>z', 'x>z', 'y>z', 'z>'],
      );
      final j = Journal('a1b2-session', workflow: 'flow', snapshot: false);
      for (final (name, start) in [
        ('a', 1),
        ('b', 1),
        ('x', 3),
        ('y', 3),
        ('z', 5),
      ]) {
        j.effect(
          name,
          start,
          end: start + 1,
          place: flowAt(name),
          key: name,
          after: null,
        );
      }
      j.finish(7);
      final p = s.passes(j.data);

      expect(s.forksOf(p), {'c': 1});
      expect(s.takenBy(p), {
        '>a',
        '>b',
        'a>c',
        'b>c',
        'c>x',
        'c>y',
        'x>z',
        'y>z',
        'z>',
      });
      expect(s.untakenBy(p), {'c>z'});
    });

    group('effects side by side that end in the millisecond they start', () {
      // helper { await Future.wait([x(), y()]); }, x and y each ending in the
      // millisecond both started: either reads as joined before the other.
      final helper = graphFunction(
        'helper',
        [effectAt('x'), effectAt('y')],
        ['>x', '>y', 'x>', 'y>'],
      );

      /// x and y, after [after], starting and ending at [time].
      void beside(Journal j, num time, String after, String round) {
        for (final name in ['x', 'y']) {
          j.effect(
            name,
            time,
            end: time,
            place: flowAt(name),
            key: '$name$round',
            after: after,
          );
        }
      }

      test('one joined beside an effect and then, firmly, before a later one '
          'is no end: await inner(); if (k) await z(); — inner { await '
          'Future.wait([o(), long(), helper()]); }, helper { await retry(() => '
          "f.effect('h')); await e2(); }, o ending as it starts; k> is "
          'darker', () {
        final helper = graphFunction(
          'helper',
          [effectAt('e2')],
          ['>e2', 'e2>'],
        );
        final inner = graphFunction(
          'inner',
          [effectAt('o'), effectAt('long'), callAt('h', helper)],
          ['>o', '>long', '>h', 'o>', 'long>', 'h>'],
        );
        final s = Shape(
          [callAt('c', inner), forkAt('k'), effectAt('z')],
          ['>c', 'c>k', 'k>z', 'k>', 'z>'],
          called: [inner, helper],
        );
        // o ends in the millisecond long starts, beside it; e2, kept back by
        // h, starts after o ended and before long did: o is joined before e2
        // for sure.
        final j = Journal('a1b2-session', workflow: 'flow', snapshot: false)
          ..effect('o', 1, end: 1, place: flowAt('o'), key: 'o', after: null)
          ..effect(
            'long',
            1,
            end: 5,
            place: flowAt('long'),
            key: 'long',
            after: null,
          )
          ..effect('h', 1, end: 1.5, key: 'h', after: null)
          ..effect('e2', 2, end: 3, place: flowAt('e2'), key: 'e2', after: null)
          ..effect('z', 6, end: 7, place: flowAt('z'), key: 'z', after: null)
          ..finish(8);
        final p = s.passes(j.data);

        expect(s.forksOf(p), {'k': 1});
        expect(s.untakenBy(p), {'k>'});
      });

      test('the way into the call they are in is one the code may have gone: '
          'while (w) await p(); await helper(); — w>h, by which the code '
          'went, is not darker', () {
        final s = Shape(
          [forkAt('w'), effectAt('p'), callAt('h', helper)],
          ['>w', 'w>p', 'p>w', 'w>h', 'h>'],
          called: [helper],
        );
        final j = Journal('a1b2-session', workflow: 'flow', snapshot: false)
          ..effect('p', 1, end: 2, place: flowAt('p'), key: 'p1', after: null)
          ..effect('p', 3, end: 4, place: flowAt('p'), key: 'p2', after: 'p1');
        beside(j, 5, 'p2', '');
        j.finish(6);
        final p = s.passes(j.data);

        expect(s.forksOf(p), contains('w'));
        expect(s.untakenBy(p), isNot(contains('w>h')));
      });

      test('they may be the last effects all the same: await p(); while (w) '
          'await helper(); — the second round side by side, then out by w>, '
          'which is not darker', () {
        final s = Shape(
          [effectAt('p'), forkAt('w'), callAt('h', helper)],
          ['>p', 'p>w', 'w>h', 'h>w', 'w>'],
          called: [helper],
        );
        final j = Journal('a1b2-session', workflow: 'flow', snapshot: false)
          ..effect('p', 1, end: 2, place: flowAt('p'), key: 'p', after: null)
          ..effect('x', 3, end: 4, place: flowAt('x'), key: 'x1', after: 'p')
          ..effect('y', 3, end: 4, place: flowAt('y'), key: 'y1', after: 'p');
        beside(j, 5, 'p', '2');
        j.finish(6);
        final p = s.passes(j.data);

        expect(s.forksOf(p), contains('w'));
        expect(s.untakenBy(p), isNot(contains('w>')));
      });
    });

    test('every end before an effect passed by an effect beside it: the way '
        'from before them marks nothing — if (c) await (() async { await a(); '
        '})(); await helper(); await Future.wait([helper(), x()]); — helper { '
        "await retry(() => f.effect('h')); await y(); }, c true", () {
      final helper = graphFunction('helper', [effectAt('y')], ['>y', 'y>']);
      final s = Shape(
        [
          forkAt('c'),
          effectAt('a'),
          callAt('h1', helper),
          callAt('h2', helper),
          effectAt('x'),
        ],
        ['>c', 'c>a', 'c>h1', 'a>h1', 'h1>h2', 'h1>x', 'h2>', 'x>'],
        called: [helper],
      );
      // All after nothing, as the library keys them: the closure and the
      // calls hand nothing on. The first y ends before x, which ends before
      // the second y starts, h not on the graph keeping it back.
      final j = Journal('a1b2-session', workflow: 'flow', snapshot: false)
        ..effect('a', 1, end: 2, place: flowAt('a'), key: 'a', after: null)
        ..effect('h', 3, end: 4, key: 'h1', after: null)
        ..effect('y', 5, end: 6, place: flowAt('y'), key: 'y1', after: null)
        ..effect('h', 7, end: 8, key: 'h2', after: null)
        ..effect('x', 7, end: 8, place: flowAt('x'), key: 'x', after: null)
        ..effect('y', 9, end: 10, place: flowAt('y'), key: 'y2', after: null)
        ..finish(11);
      final p = s.passes(j.data);

      // The second y may have come from the start: by c>h1, which the code
      // did not take, it did not.
      expect(s.takenBy(p), isNot(contains('c>h1')));
      expect(s.forksOf(p), {'c': 1});
      expect(s.takenBy(p), containsAll(['>c', 'c>a', 'a>h1', 'h1>x']));
    });

    test('the other branches of a wait go with the one taken: await p(); if '
        '(c) await Future.wait([x(), helper()]); — helper ran no effect; '
        'c>helper is not darker', () {
      final helper = graphFunction(
        'helper',
        [forkAt('n'), effectAt('y')],
        ['>n', 'n>y:true', 'n>:false', 'y>'],
      );
      final s = Shape(
        [effectAt('p'), forkAt('c'), effectAt('x'), callAt('h', helper)],
        ['>p', 'p>c', 'c>x:true', 'c>h:true', 'c>:false', 'x>', 'h>'],
        called: [helper],
      );
      for (final finished in [true, false]) {
        final p = s.passes(ran(['p', 'x'], finished: finished).data);

        expect(s.forksOf(p), {'c': 1}, reason: 'finished: $finished');
        expect(s.untakenBy(p), {'c>'}, reason: 'finished: $finished');
      }
    });
  });

  group('copies', () {
    // plan → (each x: (f ? b : c) → (g ? e : end)) → (h ? announce : end);
    // three copies: the first and the third take b, the second c. The first
    // effect of each copy follows plan, as the library keys it.
    final inside = graphFunction(
      'inside',
      [forkAt('f'), effectAt('b'), effectAt('c'), forkAt('g'), effectAt('e')],
      ['>f', 'f>b', 'f>c', 'b>g', 'c>g', 'g>e', 'g>', 'e>'],
    ).body;
    final top = Shape(
      [
        effectAt('plan'),
        copiesNode('x', inside),
        forkAt('h'),
        effectAt('announce'),
      ],
      ['>plan', 'plan>x', 'x>h', 'h>announce', 'h>', 'announce>'],
    );
    final frame = top.body.nodes.whereType<CopiesNode>().single;
    final body = Shape.of(inside, places: top.places);

    /// plan, then three copies, then [announce] after plan when given.
    Journal copies({bool finished = false, bool announce = false}) {
      final j = Journal('a1b2-session', workflow: 'flow', snapshot: false)
        ..effect(
          'plan',
          1,
          end: 2,
          place: flowAt('plan'),
          key: 'p',
          after: null,
        );
      for (final (i, exit) in ['b', 'c', 'b'].indexed) {
        j.effect(
          exit,
          3 + i / 10,
          end: 4 + i,
          place: flowAt(exit),
          key: '$exit$i',
          after: 'p',
        );
      }
      if (announce) {
        j.effect('announce', 8, end: 9, place: flowAt('announce'), after: 'p');
      }
      if (finished) j.finish(10);
      return j;
    }

    List<EffectState> copy(SessionData session, int number) => copiesOf(
      frame,
      places: top.places,
      session: session,
    )[number - 1].effects;

    test('each copy marks its own exit', () {
      final session = copies().data;

      final first = body.passes(session, effects: copy(session, 1));
      expect(body.forksOf(first), {'f': 1});
      expect(body.takenBy(first), {'>f', 'f>b'});
      expect(body.untakenBy(first), {'f>c'});

      final second = body.passes(session, effects: copy(session, 2));
      expect(body.forksOf(second), {'f': 1});
      expect(body.takenBy(second), {'>f', 'f>c'});
      expect(body.untakenBy(second), {'f>b'});
    });

    test('all copies: each passed the fork, both exits taken', () {
      final p = body.passes(copies().data);

      expect(body.forksOf(p), {'f': 3});
      expect(body.takenBy(p), {'>f', 'f>b', 'f>c'});
      expect(body.untakenBy(p), isEmpty);
    });

    test("the last effect of a copy goes to the body's end only once the "
        'session has finished', () {
      final running = copies().data;
      final before = body.passes(running, effects: copy(running, 1));
      expect(body.forksOf(before), {'f': 1});
      expect(body.takenBy(before), {'>f', 'f>b'});

      final finished = copies(finished: true).data;
      final after = body.passes(finished, effects: copy(finished, 1));
      expect(body.forksOf(after), {'f': 1, 'g': 1});
      expect(body.takenBy(after), {'>f', 'f>b', 'b>g', 'g>'});
      expect(body.untakenBy(after), {'f>c', 'g>e'});

      final all = body.passes(finished);
      expect(body.forksOf(all), {'f': 3, 'g': 3});
      expect(body.untakenBy(all), {'g>e'});
    });

    test("at the level above, a copy's effects are on the copies node and go "
        "nowhere after it, however the copies end: the workflow's end is not "
        'reached from them', () {
      final session = copies(finished: true).data;
      for (final effects in [null, copy(session, 1), copy(session, 2)]) {
        final p = top.passes(session, effects: effects);

        expect(top.forksOf(p), isEmpty);
        expect(top.takenBy(p), {if (effects == null) '>plan', 'plan>x'});
        expect(top.untakenBy(p), isEmpty);
      }
    });

    test('the effect after the copies follows the effect before them: its '
        'path goes through the copies', () {
      final p = top.passes(copies(announce: true, finished: true).data);

      expect(top.forksOf(p), {'h': 1});
      expect(top.takenBy(p), {
        '>plan',
        'plan>x',
        'x>h',
        'h>announce',
        'announce>',
      });
      expect(top.untakenBy(p), {'h>'});
    });
  });

  group('no path, no marks', () {
    test('an effect node between the two effects', () {
      // a → f → b → g → c; the session ran a, then c.
      final s = Shape(
        [effectAt('a'), forkAt('f'), effectAt('b'), forkAt('g'), effectAt('c')],
        ['>a', 'a>f', 'f>b', 'b>g', 'g>c', 'c>'],
      );
      final p = s.passes(ran(['a', 'c']).data);

      expect(s.forksOf(p), isEmpty);
      expect(s.takenBy(p), {'>a'});
      expect(s.untakenBy(p), isEmpty);
    });

    test('an effect not on the graph between two with no way between them: '
        'neither the way to it nor the way from it, and nothing between them '
        'from the one before it', () {
      // (f ? a : b), drawn by code that changed since: the session ran a, z at
      // no node, then b after z, though no way leads from a to b.
      final s = Shape(
        [forkAt('f'), effectAt('a'), effectAt('b')],
        ['>f', 'f>a', 'f>b', 'a>', 'b>'],
      );
      for (final z in [flowAt('elsewhere'), null]) {
        final j = ran(['a'])
          ..effect('z', 2, end: 3, place: z)
          ..effect('b', 4, end: 5, place: flowAt('b'));
        final p = s.passes(j.data);

        expect(s.forksOf(p), {'f': 1}, reason: 'the start → a only');
        expect(s.takenBy(p), {'>f', 'f>a'});
        expect(s.untakenBy(p), {'f>b'});
      }
    });

    test('a predecessor no record of the session has is none: the path comes '
        'from the start of the body', () {
      final s = Shape(
        [forkAt('f'), effectAt('a'), effectAt('b')],
        ['>f', 'f>a', 'f>b', 'a>', 'b>'],
      );
      final j = Journal('a1b2-session', workflow: 'flow', snapshot: false)
        ..effect('b', 1, end: 2, place: flowAt('b'), after: 'lost#1@0');
      final p = s.passes(j.data);

      expect(s.forksOf(p), {'f': 1});
      expect(s.takenBy(p), {'>f', 'f>b'});
      expect(s.untakenBy(p), {'f>a'});
    });

    test('an effect whose record has not been given yet is left out', () {
      final s = Shape(
        [effectAt('a'), forkAt('f'), effectAt('b')],
        ['>a', 'a>f', 'f>b', 'b>'],
      );
      final j = ran(['a', 'b']);
      final session = SessionData(j.session, events: j.events);

      final p = s.passes(session);

      expect(s.forksOf(p), isEmpty);
      expect(s.takenBy(p), isEmpty);
    });
  });

  group('an effect on two nodes', () {
    // a → (f ? fin : fin) → (g ? z : end): a `finally` drawn once for each
    // way out of its `try`.
    final s = Shape(
      [
        effectAt('a'),
        forkAt('f'),
        effectAt('fin1', name: 'fin'),
        effectAt('fin2', name: 'fin'),
        forkAt('g'),
        effectAt('z'),
      ],
      ['>a', 'a>f', 'f>fin1', 'f>fin2', 'fin1>g', 'fin2>g', 'g>z', 'g>', 'z>'],
    );

    test('the paths to both nodes: what is on every one is marked', () {
      final p = s.passes(ran(['a', 'fin']).data);

      expect(s.forksOf(p), {'f': 1});
      expect(s.takenBy(p), {'>a', 'a>f'});
      expect(s.untakenBy(p), isEmpty);
    });

    test('the paths from both nodes: what is on every one is marked', () {
      final p = s.passes(ran(['a', 'fin', 'z']).data);

      expect(s.forksOf(p), {'f': 1, 'g': 1});
      expect(s.takenBy(p), {'>a', 'a>f', 'g>z'});
      expect(s.untakenBy(p), {'g>'});
    });
  });

  group('limits', () {
    /// a → f1 → f2 → f3 → f4 → b with [ways] edges from each fork to the
    /// next: the product of [ways] simple paths from a to b.
    Shape stages(List<int> ways) => Shape(
      [
        effectAt('a'),
        for (var i = 1; i <= ways.length + 1; i++) forkAt('f$i'),
        effectAt('b'),
      ],
      [
        '>a',
        'a>f1',
        for (final (i, n) in ways.indexed)
          for (var k = 0; k < n; k++) 'f${i + 1}>f${i + 2}',
        'f${ways.length + 1}>b',
        'b>',
      ],
    );

    test('a thousand paths between two effects are all searched', () {
      final s = stages([10, 10, 10]);
      final p = s.passes(ran(['a', 'b']).data);

      expect(s.forksOf(p), {'f1': 1, 'f2': 1, 'f3': 1, 'f4': 1});
      expect(s.takenBy(p), {'>a', 'a>f1', 'f4>b'});
    });

    test('more than a thousand give no marks; the other transitions are '
        'marked all the same', () {
      final s = stages([11, 10, 10]);
      final p = s.passes(ran(['a', 'b']).data);

      expect(s.forksOf(p), isEmpty);
      expect(s.takenBy(p), {'>a'});
      expect(s.untakenBy(p), isEmpty);
    });

    test('ways that lead nowhere are not walked: a loop with 2^40 ways round '
        'it, all back to where the path has been, does not keep the one path '
        'past it from being found', () {
      // a → g → b; g → w1 ⇉ w2 ⇉ … ⇉ w40 → g.
      final s = Shape(
        [
          effectAt('a'),
          forkAt('g'),
          for (var i = 1; i <= 40; i++) forkAt('w$i'),
          effectAt('b'),
        ],
        [
          '>a',
          'a>g',
          'g>b',
          'g>w1',
          for (var i = 1; i < 40; i++) ...['w$i>w${i + 1}', 'w$i>w${i + 1}'],
          'w40>g',
          'b>',
        ],
      );
      final p = s.passes(ran(['a', 'b']).data);

      expect(s.forksOf(p), {'g': 1});
      expect(s.takenBy(p), {'>a', 'a>g', 'g>b'});
      // The code may have gone round the loop, which runs no effect.
      expect(s.untakenBy(p), isEmpty);
    });

    test('a transition past the limit marks nothing, but the exits it may '
        'have taken are not untaken', () {
      // a → (f ? c : m1 ⇉ m2 ⇉ m3 ⇉ m4 → b), c → a: a, c, a, b — f is passed
      // on the way to c; the way to b has 1100 paths.
      final s = Shape(
        [
          effectAt('a'),
          forkAt('f'),
          effectAt('c'),
          for (var i = 1; i <= 4; i++) forkAt('m$i'),
          effectAt('b'),
        ],
        [
          '>a',
          'a>f',
          'f>c',
          'c>a',
          'f>m1',
          for (final (i, n) in [11, 10, 10].indexed)
            for (var k = 0; k < n; k++) 'm${i + 1}>m${i + 2}',
          'm4>b',
          'b>',
        ],
      );
      final p = s.passes(ran(['a', 'c', 'a', 'b']).data);

      expect(s.forksOf(p), {'f': 1});
      expect(s.takenBy(p), {'>a', 'a>f', 'f>c', 'c>a'});
      expect(s.untakenBy(p), isEmpty);
    });
  });

  group('the scope and asking again', () {
    // a → (c ? b : d)
    final s = Shape(
      [effectAt('a'), forkAt('c'), effectAt('b'), effectAt('d')],
      ['>a', 'a>c', 'c>b', 'c>d', 'b>', 'd>'],
    );

    test('only the effects shown make transitions', () {
      final session = ran(['a', 'b']).data;
      final p = s.passes(session, effects: [session.state.effects.last]);

      expect(s.forksOf(p), {'c': 1});
      expect(s.takenBy(p), {'a>c', 'c>b'}, reason: 'not the start → a');
    });

    test('the same question of an unchanged session, the effects shown given '
        'anew, has the same answer; other effects shown, another', () {
      final session = ran(['a', 'b']).data;
      Passes ask(Iterable<EffectState> effects) =>
          s.passes(session, effects: effects);

      final all = ask(session.state.effects);
      expect(ask([...session.state.effects]), same(all));
      final last = ask([session.state.effects.last]);
      expect(last, isNot(same(all)));
      expect(s.takenBy(last), {'a>c', 'c>b'});
    });

    test('a session that has changed is asked again', () {
      fakeAsync((async) {
        final j = ran(['a']);
        final changes = StreamController<Change>();
        final feed = SessionFeed(changes.stream);
        void give(Iterable<Change> given) {
          given.forEach(changes.add);
          async.flushMicrotasks();
        }

        give(j.changes);
        final session = feed.session(j.id)!;
        Passes ask() => s.passes(session);

        final first = ask();
        expect(ask(), same(first));
        expect(s.forksOf(first), isEmpty);

        // b starts before its record is given: no transition to it yet.
        final b = ran(['a', 'b']).effects.last;
        give([
          EventAdded(
            sessionId: j.id,
            event: EffectStarted(time: at(3), effectId: b.id),
          ),
        ]);
        final started = ask();
        expect(started, isNot(same(first)));
        expect(s.forksOf(started), isEmpty);

        give([EffectAdded(b)]);
        final recorded = ask();
        expect(s.forksOf(recorded), {'c': 1});
        expect(s.takenBy(recorded), {'>a', 'a>c', 'c>b'});

        // A rerun gives b's record again, after nothing.
        give([
          EffectChanged(
            Effect(
              id: b.id,
              sessionId: b.sessionId,
              name: b.name,
              key: b.key,
              after: null,
              place: b.place,
              outputId: b.outputId,
              log: b.log,
            ),
          ),
        ]);
        final rerun = ask();
        expect(rerun, isNot(same(recorded)));
        // After nothing, as a is: a, which finished before b started and
        // leads to it, is read as joined by a wait at the session's start,
        // so b's passes are again a's way to it.
        expect(s.forksOf(rerun), {'c': 1});
        expect(s.takenBy(rerun), {'>a', 'a>c', 'c>b'});

        feed.dispose();
        async.flushMicrotasks();
      });
    });
  });

  group('over the session the real library wrote (recordedReview)', () {
    final recorded = recordedReview();
    final session = recorded.sessions['review']!;
    final review = recorded.graph.functions['lib/review.dart#review']!;
    final s = Shape.of(
      review.body,
      places: EffectPlaces.of(review, recorded.graph.functions),
    );

    test('the journal: collect, inspect, fix, inspect, then publish and '
        'notify side by side, both after the second inspect', () {
      final records = session.effectsInOrder;

      expect(session.state.status, SessionStatus.finished);
      expect(
        [for (final effect in records.take(4)) effect.name],
        ['collect', 'inspect', 'fix', 'inspect'],
      );
      // Side by side, in the order they happened to start.
      expect([
        for (final effect in records.skip(4)) effect.name,
      ], unorderedEquals(['publish', 'notify']));
      expect(
        [for (final effect in records) effect.after],
        [
          null,
          records[0].key,
          records[1].key,
          records[2].key,
          records[3].key,
          records[3].key,
        ],
      );
    });

    test('the empty change fork once by its false edge, the findings fork '
        'twice by all its edges, the back edge; out of the body from publish '
        'and notify', () {
      final p = s.passes(session);

      expect(s.forksOf(p), {'2': 1, '5': 2});
      expect(s.takenBy(p), {
        '>1',
        '1>2',
        '2>4',
        '4>5',
        '5>6',
        '5>7',
        '5>8',
        '8>4',
        '6>',
        '7>',
      });
      expect(s.untakenBy(p), {'2>3'});
    });

    test('the same journal while it ran: not out of the body', () {
      final running = SessionData(
        session.session,
        events: session.events.where((event) => event is! SessionFinished),
        effects: session.effects.values,
      );
      final p = s.passes(running);

      expect(s.forksOf(p), {'2': 1, '5': 2});
      expect(s.takenBy(p), {
        '>1',
        '1>2',
        '2>4',
        '4>5',
        '5>6',
        '5>7',
        '5>8',
        '8>4',
      });
      expect(s.untakenBy(p), {'2>3'});
    });
  });

  group('over sessions the real library wrote (recordedCalls)', () {
    // release: plan → publish() → (plan == 'stable' ? announce : end);
    // inPlace: the same with publish's body drawn in place. Both run on the
    // stable channel.
    final recorded = recordedCalls();
    final functions = recorded.graph.functions;

    for (final workflow in ['release', 'inPlace']) {
      final session = recorded.sessions[workflow]!;
      final function = functions['lib/calls.dart#$workflow']!;
      final s = Shape.of(
        function.body,
        places: EffectPlaces.of(function, functions),
      );

      test('$workflow: announce after plan, not after verify, the last '
          'effect before it', () {
        final records = session.effectsInOrder;
        expect(
          [for (final effect in records) effect.name],
          ['plan', 'upload', 'verify', 'announce'],
        );
        expect(records[3].after, records[0].key);
      });

      test('$workflow: the fork passed once, by its true edge; its false '
          'edge, to the end, darker', () {
        final p = s.passes(session);
        final fork = function.body.nodes.whereType<ConditionNode>().single.id;
        final announce = function.body.nodes
            .whereType<EffectNode>()
            .singleWhere((node) => node.name == 'announce')
            .id;

        expect(s.forksOf(p), {fork: 1});
        expect(s.takenBy(p), contains('$fork>$announce'));
        expect(s.takenBy(p), isNot(contains('$fork>')));
        expect(s.untakenBy(p), {'$fork>'});
      });
    }
  });
}
