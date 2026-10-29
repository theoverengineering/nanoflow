// Running a graph of nodes in a session (graph node objects design §3–§7):
// nodes as effects, routes, sets, joins and loops; graphs as nodes and as
// workflows; the journal, resume, the result, the places and the keys of its
// effects.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:nanoflow/nanoflow.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support.dart';

final class Change {
  Change(this.path);

  factory Change.fromJson(Map<String, Object?> json) =>
      Change(json['path']! as String);

  final String path;

  Map<String, Object?> toJson() => {'path': path};
}

final class Report {
  Report(this.path, this.findings);

  factory Report.fromJson(Map<String, Object?> json) =>
      Report(json['path']! as String, json['findings']! as int);

  final String path;
  final int findings;

  Map<String, Object?> toJson() => {'path': path, 'findings': findings};
}

/// What [collect] gives: the change of a branch, or that it has none.
sealed class Collected {
  static Collected fromJson(Map<String, Object?> json) =>
      json.containsKey('branch')
      ? Empty(json['branch']! as String)
      : Found(Change.fromJson(json));

  Map<String, Object?> toJson();
}

final class Empty extends Collected {
  Empty(this.branch);

  final String branch;

  @override
  Map<String, Object?> toJson() => {'branch': branch};
}

final class Found extends Collected {
  Found(this.change);

  final Change change;

  @override
  Map<String, Object?> toJson() => change.toJson();
}

enum Verdict { pass, fail }

/// The nodes that ran, in order, with what they were given.
final calls = <String>[];

final collect = node('collect', (String branch) async {
  calls.add('collect $branch');
  return branch.isEmpty ? Empty(branch) : Found(Change(branch));
});

final inspect = node('inspect', (Change change) async {
  calls.add('inspect ${change.path}');
  return Report(change.path, change.path.endsWith('!') ? 0 : 1);
});

final fix = node('fix', (Report report) async {
  calls.add('fix ${report.path}');
  return Change('${report.path}!');
});

final discard = node('discard', (String branch) async {
  calls.add('discard $branch');
  return 'discarded';
});

final publish = node('publish', (Report report) async {
  calls.add('publish ${report.path}');
  return 'published ${report.path}';
});

final notify = node('notify', (Report report) async {
  calls.add('notify ${report.path}');
  return report.findings;
});

final report = node('report', ((String, int) sent) async {
  calls.add('report');
  return '${sent.$1} with ${sent.$2} findings';
});

final review = Graph<String, String>('review', [
  Graph.start(collect).next(
    (collected) => switch (collected) {
      Empty(:final branch) => discard(branch),
      Found(:final change) => inspect(change),
    },
  ),
  Graph.part(inspect)
      .next((r) => r.findings == 0 ? {publish(r), notify(r)} : fix(r)),
  Graph.part(fix).next((change) => inspect(change)),
  Graph.join([publish, notify]).next(((String, int) sent) => report(sent)),
]);

final isLong = node('isLong', (String text) async => text.length > 3);

final long = node('long', (bool yes) async => 'long');

final short = node('short', (bool yes) async => 'short');

final measured = Graph<String, String>('measured', [
  Graph.start(isLong).next((yes) => yes ? long(yes) : short(yes)),
]);

final longOnly = Graph<String, Object?>('longOnly', [
  Graph.start(isLong).next((yes) => yes ? long(yes) : null),
]);

final shout = node('shout', (String text) async => text.toUpperCase());

final left = node('left', (String text) async {
  calls.add('left $text');
  return 'left';
});

final right = node('right', (String text) async {
  calls.add('right $text');
  return 'right';
});

final fanned = Graph<String, String>('fanned', [
  Graph.start(shout).next((text) => {left(text), right(text)}),
]);

final listing = Graph<String, Object?>('listing', [
  Graph.start(shout).next((text) => [left(text), right(text)]),
]);

/// Another node named as [shout].
final shoutAgain = node('shout', (String text) async => text);

final clashing = Graph<String, Object?>('clashing', [
  Graph.start(shout).next((text) => shoutAgain(text)),
]);

final tick = node('tick', (int n) async {
  calls.add('tick $n');
  return n + 1;
});

final counting = Graph<int, int>('counting', [
  Graph.start(tick).next((n) => n < 3 ? tick(n) : null),
]);

/// Opened when a [slow] node may finish.
var slowGate = Completer<void>();

final slow = node('slow', (String text) async {
  await slowGate.future;
  return 'slow $text';
});

final boom = node(
  'boom',
  (String text) async => throw StateError('boom $text'),
);

final picky = node('picky', (String text) async => text);

final both = node('both', ((String, String) parts) async => 'both');

final failing = Graph<String, Object?>('failing', [
  Graph.start(shout).next((text) => {boom(text), slow(text)}),
  Graph.join([boom, slow]).next(((String, String) parts) => both(parts)),
]);

final routeThrows = Graph<String, Object?>('routeThrows', [
  Graph.start(shout).next((text) => {picky(text), slow(text)}),
  Graph.part(picky).next((text) {
    switch (text) {
      case 'OK':
        return null;
      default:
        throw StateError('no route for $text');
    }
  }),
  Graph.part(slow).next((text) => left(text)),
  Graph.join([picky, slow]).next(((String, String) parts) => both(parts)),
]);

final tens = node('tens', (int n) async => n * 10);

final hundreds = node('hundreds', (int n) async => n * 100);

final sum = node('sum', ((int, int) parts) async {
  calls.add('sum ${parts.$1} ${parts.$2}');
  return parts.$1 ~/ 10;
});

final ticking = Graph<int, int>('ticking', [
  Graph.start(tick).next((n) => n < 3 ? {tens(n), hundreds(n)} : null),
  Graph.join([tens, hundreds]).next(((int, int) parts) => sum(parts)),
  Graph.part(sum).next((n) => tick(n)),
]);

/// A join with no route: its record is where the graph ends.
final joinEnds = Graph<String, (String, String)>('joinEnds', [
  Graph.start(shout).next((text) => {left(text), right(text)}),
  Graph.join([left, right]),
]);

/// A join whose route gives null: its record is where the graph ends too.
final joinGivesNull = Graph<String, (String, String)>('joinGivesNull', [
  Graph.start(shout).next((text) => {left(text), right(text)}),
  Graph.join([left, right]).next(((String, String) both) => null),
]);

/// A join whose route throws while [slow] still runs.
final joinRouteThrows = Graph<String, Object?>('joinRouteThrows', [
  Graph.start(shout).next((text) => {left(text), right(text), slow(text)}),
  Graph.join([left, right])
      .next(((String, String) both) => throw StateError('boom')),
]);

/// A join whose route takes another record than its nodes give.
final joinWrongRecord = Graph<String, Object?>('joinWrongRecord', [
  Graph.start(shout).next((text) => {left(text), right(text)}),
  Graph.join([left, right]).next(((int, int) both) => null),
]);

final isOn = node('isOn', (bool yes) async => yes);

final on = node('on', (bool yes) async => 'on');

final off = node('off', (bool yes) async => 'off');

final joined = node('joined', ((String, String) parts) async {
  calls.add('joined');
  return 0;
});

final halfJoined = Graph<bool, Object?>('halfJoined', [
  Graph.start(isOn).next((yes) => yes ? on(yes) : off(yes)),
  Graph.join([on, off]).next(((String, String) parts) => joined(parts)),
]);

/// Completed when a [target] node has run.
var targetRan = Completer<void>();

final early = node('early', (String text) async => 'early $text');

final twice = node('twice', (String text) async {
  calls.add('twice $text');
  return 'twice $text';
});

final later = node('later', (String text) async {
  await targetRan.future;
  return 'later $text';
});

final target = node('target', ((String, String) parts) async {
  if (!targetRan.isCompleted) targetRan.complete();
  return 'target of ${parts.$1}, ${parts.$2}';
});

/// [twice] gives a second output, which no output of [early] joins, after
/// [target] has run.
final membersNoEnds = Graph<String, String>('membersNoEnds', [
  Graph.start(early),
  Graph.start(twice),
  Graph.start(later).next((text) => twice(text)),
  Graph.join([early, twice]).next(((String, String) parts) => target(parts)),
]);

final judge = node('judge', (String text) async {
  calls.add('judge $text');
  return text.length > 3 ? Verdict.pass : Verdict.fail;
});

final judging = Graph<String, Verdict>('judging', [Graph.start(judge)]);

final accept = node('accept', (Verdict verdict) async => 'accepted');

final refuse = node('refuse', (Verdict verdict) async => 'refused');

final judged = Graph<String, String>('judged', [
  Graph.start(judging).next(
    (verdict) => switch (verdict) {
      Verdict.pass => accept(verdict),
      Verdict.fail => refuse(verdict),
    },
  ),
]);

final shouting = Graph<String, String>('shouting', [Graph.start(shout)]);

/// Opened to let a [waits] node finish.
var gate = Completer<void>();

/// Completed when a [waits] node starts.
var atGate = Completer<void>();

final waits = node('waits', (String text) async {
  calls.add('waits $text');
  if (!atGate.isCompleted) atGate.complete();
  await gate.future;
  return 'past $text';
});

final measure = node('measure', (String text) async {
  calls.add('measure $text');
  return (text, text.length);
});

final gated = Graph<String, String>('gated', [
  Graph.start(measure).next((sized) => waits('${sized.$1} of ${sized.$2}')),
]);

final judgedGated = Graph<String, String>('judgedGated', [
  Graph.start(judging).next(
    (verdict) => switch (verdict) {
      Verdict.pass => waits(verdict.name),
      Verdict.fail => refuse(verdict),
    },
  ),
]);

final placedInner = Graph<String, String>('placedInner', [Graph.start(shout)]);

final placedOuter = Graph<String, String>('placedOuter', [
  Graph.start(shout).next((text) => placedInner(text)),
]);

/// A value with a toJson whose type has no codec.
final class Unregistered {
  Map<String, Object?> toJson() => {};
}

final makesUnregistered = node(
  'makesUnregistered',
  (String text) async => Unregistered(),
);

final unregistered = Graph<String, Object?>('unregistered', [
  Graph.start(makesUnregistered),
]);

final paceA = node('paceA', (int n) async {
  await pause();
  return n + 1;
});

final paceB = node('paceB', (int n) async {
  await pause();
  return n;
});

final paceC = node('paceC', (int n) async {
  await pause();
  return n * 2;
});

final paceD = node('paceD', ((int, int) parts) async {
  await pause();
  return parts.$1;
});

final paced = Graph<int, int>('paced', [
  Graph.start(paceA).next((n) => {paceB(n), paceC(n)}),
  Graph.join([paceB, paceC]).next(((int, int) parts) => paceD(parts)),
  Graph.part(paceD).next((n) => n < 3 ? paceA(n) : null),
]);

/// A flow in [dir] with the codecs of the values above.
Flow flowIn(String dir) => Flow(directory: dir)
  ..addCodec(Change.fromJson)
  ..addCodec(Report.fromJson)
  ..addCodec(Collected.fromJson)
  ..addEnum(Verdict.values);

/// The effects of the only session of [dir], in the order they started.
Future<List<Effect>> effectsIn(String dir) async =>
    (await onlySession(dir)).effects();

/// A graph file of [functions], each a graph by its name with the places of
/// its nodes by their names, all in `lib/g.dart`.
GraphFile graphFileOf(Map<String, Map<String, String>> functions) => GraphFile(
  format: graphFileFormat,
  package: 'g',
  fingerprint: 'sha256:0',
  sources: const {},
  builds: const {},
  workflows: [for (final name in functions.keys) 'lib/g.dart#$name'],
  functions: {
    for (final MapEntry(key: name, value: places) in functions.entries)
      'lib/g.dart#$name': GraphFunction(
        id: 'lib/g.dart#$name',
        name: name,
        place: 'lib/g.dart:1',
        body: GraphBody(
          nodes: [
            for (final (i, MapEntry(key: node, value: place))
                in places.entries.indexed)
              EffectNode(id: '${i + 1}', place: place, name: node),
          ],
          edges: const [],
        ),
      ),
  },
  warnings: const [],
);

void main() {
  setUp(calls.clear);

  test('a node runs as an effect named after it, its result journaled with '
      'the codec of O', () async {
    expect(collect, isA<Node<String, Collected>>());
    final dir = await tempDir();
    expect(await flowIn(dir).run(review, ''), 'discarded');
    final handle = await onlySession(dir);
    final [collected, discarded] = await handle.effects();
    expect(collected.name, 'collect');
    expect(collected.key, 'collect#1@${h('')}');
    expect(await handle.documentValue(collected.outputId!), {'branch': ''});
    expect(discarded.name, 'discard');
    expect(discarded.after, collected.key);
    expect(
      await eventsOf(handle),
      contains(
        isA<EffectFinished>()
            .having((e) => e.effectId, 'effectId', collected.id)
            .having((e) => e.outputId, 'outputId', collected.outputId),
      ),
    );
  });

  group('routes', () {
    test('a switch on a sealed output gives each case its own next node and '
        'argument', () async {
      final dir = await tempDir();
      final result = await flowIn(dir).run(review, 'main');
      expect(result, 'published main! with 0 findings');
      // publish and notify run side by side: their bodies run in the order
      // their effects are written.
      expect(calls.take(4), [
        'collect main',
        'inspect main',
        'fix main',
        'inspect main!',
      ]);
      expect(
        calls.skip(4).take(2),
        unorderedEquals(['publish main!', 'notify main!']),
      );
      expect(calls.last, 'report');
      final effects = await effectsIn(dir);
      expect(
        [for (final e in effects) e.name],
        unorderedEquals([
          'collect',
          'inspect',
          'fix',
          'inspect',
          'publish',
          'notify',
          'report',
        ]),
      );
      Effect named(String name, {String? after}) => effects.singleWhere(
        (e) => e.name == name && (after == null || e.after == after),
      );
      final fix = named('fix');
      final again = named('inspect', after: fix.key);
      expect(fix.after, named('inspect', after: named('collect').key).key);
      expect(named('publish').after, again.key);
      expect(named('notify').after, again.key);
      expect(named('report').after, named('publish').key);
      expect({for (final e in effects) e.key}, hasLength(7));
    });

    test('the other way of the same graph', () async {
      final dir = await tempDir();
      expect(await flowIn(dir).run(review, ''), 'discarded');
      expect(calls, ['collect ', 'discard ']);
    });

    test('?: on a bool picks one', () async {
      final dir = await tempDir();
      expect(await flowIn(dir).run(measured, 'long text'), 'long');
      expect(await flowIn(dir).run(measured, 'ab'), 'short');
    });

    test('a set runs both side by side', () async {
      final dir = await tempDir();
      expect(await flowIn(dir).run(fanned, 'x'), anyOf('left', 'right'));
      expect(calls, unorderedEquals(['left X', 'right X']));
      final [shouted, ...others] = await effectsIn(dir);
      expect(shouted.name, 'shout');
      expect([
        for (final e in others) e.name,
      ], unorderedEquals(['left', 'right']));
      expect([for (final e in others) e.after], [shouted.key, shouted.key]);
    });

    test('null ends the branch and its output is the result', () async {
      final dir = await tempDir();
      expect(await flowIn(dir).run(longOnly, 'ab'), false);
      expect(await flowIn(dir).run(longOnly, 'long text'), 'long');
    });

    test('a result that is not the graph\'s type is a TypeError', () async {
      final dir = await tempDir();
      final longOnlyString = Graph<String, String>('longOnlyString', [
        Graph.start(isLong).next((yes) => yes ? long(yes) : null),
      ]);
      await expectLater(
        flowIn(dir).run(longOnlyString, 'ab'),
        throwsA(isA<TypeError>()),
      );
    });

    test('a loop goes round until the route leaves it', () async {
      final dir = await tempDir();
      expect(await flowIn(dir).run(counting, 0), 3);
      expect(calls, ['tick 0', 'tick 1', 'tick 2']);
      final effects = await effectsIn(dir);
      expect([for (final e in effects) e.name], ['tick', 'tick', 'tick']);
      expect(
        [for (final e in effects) e.after],
        [null, effects[0].key, effects[1].key],
      );
    });

    test(
      'a List of transitions is a StateError naming the graph and the node',
      () async {
        final dir = await tempDir();
        await expectLater(
          flowIn(dir).run(listing, 'x'),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              allOf(
                contains(
                  'graph "listing": the route of shout gave '
                  '[Next(left), Next(right)]',
                ),
                contains('a route gives a Next, a set of them or null'),
              ),
            ),
          ),
        );
        expect(calls, isEmpty);
      },
    );

    test('a route that throws fails the session once the other branch has '
        'ended', () async {
      final dir = await tempDir();
      slowGate = Completer();
      final session = await flowIn(dir).start(routeThrows, 'x');
      final failed = expectLater(
        session.result,
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'no route for X',
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      slowGate.complete();
      await failed;
      // The other branch went on to its next node before the session failed.
      expect(calls, ['left slow X']);
      final effects = await effectsIn(dir);
      expect([
        for (final e in effects) e.name,
      ], unorderedEquals(['shout', 'picky', 'slow', 'left']));
      expect(effects.singleWhere((e) => e.name == 'left').outputId, isNotNull);
    });

    test('a node that throws fails the session once the other branch has '
        'ended, and its join does not hold it', () async {
      final dir = await tempDir();
      slowGate = Completer();
      final session = await flowIn(dir).start(failing, 'x');
      final failed = expectLater(
        session.result,
        throwsA(
          isA<StateError>().having((e) => e.message, 'message', 'boom X'),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      slowGate.complete();
      await failed;
      final effects = await effectsIn(dir);
      final names = [for (final e in effects) e.name];
      expect(names.first, 'shout');
      expect(names.skip(1), unorderedEquals(['boom', 'slow']));
    });

    test(
      'a node of a name another node of the graph has is a StateError',
      () async {
        final dir = await tempDir();
        await expectLater(
          flowIn(dir).run(clashing, 'x'),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              'graph "clashing": two nodes are named shout',
            ),
          ),
        );
        expect([for (final e in await effectsIn(dir)) e.name], ['shout']);
      },
    );
  });

  group('joins', () {
    test('fire once for each full set, round a loop', () async {
      final dir = await tempDir();
      expect(await flowIn(dir).run(ticking, 0), 3);
      expect(calls, ['tick 0', 'sum 10 100', 'tick 1', 'sum 20 200', 'tick 2']);
    });

    test('that never fill up end their branch, and the graph ends', () async {
      final dir = await tempDir();
      expect(await flowIn(dir).run(halfJoined, true), isNull);
      expect(calls, isNot(contains('joined')));
    });

    test('a join without a route, or whose route gives null, gives its '
        'record as the graph\'s result', () async {
      expect(await flowIn(await tempDir()).run(joinEnds, 'x'), (
        'left',
        'right',
      ));
      expect(await flowIn(await tempDir()).run(joinGivesNull, 'x'), (
        'left',
        'right',
      ));
    });

    test('a join route that throws fails the session with its error, and '
        'does not hang', () async {
      final dir = await tempDir();
      slowGate = Completer();
      final session = await flowIn(dir).start(joinRouteThrows, 'x');
      final failed = expectLater(
        session.result.timeout(const Duration(seconds: 5)),
        throwsA(isA<StateError>().having((e) => e.message, 'message', 'boom')),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      slowGate.complete();
      await failed;
    });

    test('a join route that takes another record than its nodes give is a '
        'StateError naming the graph and the join', () async {
      await expectLater(
        flowIn(await tempDir())
            .run(joinWrongRecord, 'x')
            .timeout(const Duration(seconds: 5)),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(
              startsWith('graph "joinWrongRecord": '),
              contains('the route of the join of left, right'),
              contains('(String, String)'),
              contains('is not a subtype'),
            ),
          ),
        ),
      );
    });

    test(
      'a join member without its own arrows is no end of the graph',
      () async {
        final dir = await tempDir();
        targetRan = Completer();
        expect(
          await flowIn(dir).run(membersNoEnds, 'x'),
          'target of early x, twice x',
        );
        expect(calls, ['twice x', 'twice later x']);
      },
    );
  });

  test('a graph is a node: it runs on its own effects, and its result goes '
      'into the outer route', () async {
    expect(await flowIn(await tempDir()).run(judged, 'ab'), 'refused');
    final dir = await tempDir();
    expect(await flowIn(dir).run(judged, 'long text'), 'accepted');
    final effects = await effectsIn(dir);
    expect([for (final e in effects) e.name], ['judge', 'accept']);
  });

  test('a graph that is a node gives the outer route its result on resume '
      'too, from the journal', () async {
    final dir = await tempDir();
    gate = Completer();
    atGate = Completer();
    final flow = flowIn(dir);
    final first = await flow.start(judgedGated, 'long text');
    await atGate.future;
    flow.stop();
    gate.complete();
    await expectLater(first.result, throwsA(isA<FlowStoppedException>()));
    gate = Completer()..complete();
    final resumed = await flowIn(dir).resume(judgedGated, first.id);
    expect(await resumed.result, 'past pass');
    expect(calls, ['judge long text', 'waits pass', 'waits pass']);
  });

  test('a session of a graph is named after it, unfinished finds it, and '
      'resume takes finished nodes from the journal and reruns an unfinished '
      'one whole', () async {
    final dir = await tempDir();
    gate = Completer();
    atGate = Completer();
    final flow = flowIn(dir);
    final first = await flow.start(gated, 'main');
    await atGate.future;
    expect(await flowIn(dir).unfinished(gated), [first.id]);
    flow.stop();
    gate.complete();
    await expectLater(first.result, throwsA(isA<FlowStoppedException>()));
    gate = Completer()..complete();
    final resumed = await flowIn(dir).resume(gated, first.id);
    expect(await resumed.result, 'past main of 4');
    // measure ran once, its output a record from the journal on resume;
    // waits had not finished, and ran again.
    expect(calls, ['measure main', 'waits main of 4', 'waits main of 4']);
    final handle = await openSession(dir, first.id);
    expect(handle.session.workflow, 'gated');
  });

  test('a node whose output has no codec fails as it runs, with a '
      'CodecException', () async {
    final dir = await tempDir();
    await expectLater(
      flowIn(dir).run(unregistered, 'x'),
      throwsA(
        isA<CodecException>().having((e) => e.type, 'type', Unregistered),
      ),
    );
    final handle = await onlySession(dir);
    expect([
      for (final event in await eventsOf(handle)) event.runtimeType,
    ], contains(EffectFailed));
  });

  group('the place of a node\'s effect', () {
    test('is the one the graph file gives the node in that graph', () async {
      final dir = await tempDir();
      final file = graphFileOf({
        'placedOuter': {'shout': 'lib/g.dart:3'},
        'placedInner': {'shout': 'lib/g.dart:7'},
      });
      await File(p.join(dir, graphFileName))
          .writeAsString(jsonEncode(file.toJson()));
      expect(await flowIn(dir).run(placedOuter, 'x'), 'X');
      expect(
        [for (final e in await effectsIn(dir)) e.place],
        ['lib/g.dart:3', 'lib/g.dart:7'],
      );
    });

    test('is null without a graph file', () async {
      final dir = await tempDir();
      await flowIn(dir).run(placedOuter, 'x');
      expect([for (final e in await effectsIn(dir)) e.place], [null, null]);
    });
  });

  test('gives the same keys and the same after whatever the timing', () async {
    Future<Map<String, String?>> keysAt(int seed) async {
      random = Random(seed);
      final dir = await tempDir();
      expect(await flowIn(dir).run(paced, 0), 3);
      return {for (final e in await effectsIn(dir)) e.key: e.after};
    }

    final first = await keysAt(1);
    expect(first, hasLength(12));
    for (var seed = 2; seed < 12; seed++) {
      expect(await keysAt(seed), first, reason: 'seed $seed');
    }
  });
}
