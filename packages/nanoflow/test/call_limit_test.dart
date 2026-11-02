// Limiting the copies of a call (call limit design): a node or a graph a
// route calls with `limit:` runs at most that many copies at once, per call
// site and run of the graph whose route calls it, in the order of the calls;
// a copy waiting writes nothing. Resume, stop, the keys of the effects and
// the node's own concurrency with it.

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:nanoflow/nanoflow.dart';
import 'package:nanoflow/src/flow.dart' show startWithSaved;
import 'package:nanoflow/src/graph.dart' show GraphRun;
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_store/nanoflow_store.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support.dart';

/// What the bodies of the nodes entered, in order.
final entered = <String>[];

/// How many [task]s run now, and the most that ran at once.
var running = 0;
var mostRunning = 0;

/// Opened to let [task]s finish.
var taskGate = Completer<void>();

final ids = node('ids', (List<int> ids) async => ids);

final task = node('task', (int i) async {
  entered.add('task $i');
  mostRunning = max(mostRunning, ++running);
  try {
    await taskGate.future;
    await pause();
    if (i < 0) throw StateError('negative $i');
    return i * 10;
  } finally {
    running--;
  }
});

final tasksOfThree = Graph<List<int>, Object?>('tasksOfThree', [
  Graph.start(ids).next((ids) => {for (final i in ids) task(i, limit: 3)}),
]);

final tasksOfOne = Graph<List<int>, Object?>('tasksOfOne', [
  Graph.start(ids).next((ids) => {for (final i in ids) task(i, limit: 1)}),
]);

/// One copy of [task] on each of the ids with a limit of one, and one on 99
/// without.
final tasksAndOneFree = Graph<List<int>, Object?>('tasksAndOneFree', [
  Graph.start(ids)
      .next((ids) => {for (final i in ids) task(i, limit: 1), task(99)}),
]);

final class Plan {
  Plan(this.parallel, this.count);

  factory Plan.fromJson(Map<String, Object?> json) =>
      Plan(json['parallel']! as int, json['count']! as int);

  /// How many tasks run at once.
  final int parallel;
  final int count;

  Map<String, Object?> toJson() => {'parallel': parallel, 'count': count};
}

final plan = node('plan', (Plan plan) async => plan);

final planned = Graph<Plan, Object?>('planned', [
  Graph.start(plan).next(
    (plan) => {
      for (var i = 0; i < plan.count; i++) task(i, limit: plan.parallel),
    },
  ),
]);

/// The copies of [sub] that run now: from the first of its nodes whose body
/// runs to the end of [subB]'s; and the most that ran at once.
final live = <int>{};
var mostLive = 0;

void goLive(int copy) {
  live.add(copy);
  mostLive = max(mostLive, live.length);
}

/// The gates [subB] of each copy waits at; one not there is open.
final gates = <int, Completer<void>>{};

void close(Iterable<int> copies) {
  for (final copy in copies) {
    gates[copy] = Completer();
  }
}

void open(int copy) {
  if (gates.remove(copy) case final gate? when !gate.isCompleted) {
    gate.complete();
  }
}

void openAll() => [...gates.keys].forEach(open);

final subA = node('subA', (int i) async {
  entered.add('a $i');
  goLive(i);
  await pause();
  return i;
});

final subB = node('subB', (int i) async {
  entered.add('b $i');
  goLive(i);
  await (gates[i]?.future ?? Future<void>.value());
  await pause();
  live.remove(i);
  return i;
});

/// A copy of two nodes, one after the other.
final sub = Graph<int, int>('sub', [Graph.start(subA).next((i) => subB(i))]);

final subsOfOne = Graph<List<int>, Object?>('subsOfOne', [
  Graph.start(ids).next((ids) => {for (final i in ids) sub(i, limit: 1)}),
]);

/// Another graph that calls [sub] as [subsOfOne] does.
final subsOfOneToo = Graph<List<int>, Object?>('subsOfOneToo', [
  Graph.start(ids).next((ids) => {for (final i in ids) sub(i, limit: 1)}),
]);

final subsOfTwo = Graph<List<int>, Object?>('subsOfTwo', [
  Graph.start(ids).next((ids) => {for (final i in ids) sub(i, limit: 2)}),
]);

/// [subsOfTwo] without the limit.
final subsFree = Graph<List<int>, Object?>('subsFree', [
  Graph.start(ids).next((ids) => {for (final i in ids) sub(i)}),
]);

/// [subsOfOne] and [subsOfOneToo] side by side, the second on the ids plus
/// 10.
final bothParents = Graph<List<int>, Object?>('bothParents', [
  Graph.start(ids).next(
    (ids) => {
      subsOfOne(ids),
      subsOfOneToo([for (final i in ids) i + 10]),
    },
  ),
]);

final round = node('round', (int n) async {
  entered.add('round $n');
  return n;
});

/// Three rounds of a loop, each calling two copies of [sub] from the same
/// route: n * 10 and n * 10 + 1.
final rounds = Graph<int, Object?>('rounds', [
  Graph.start(round).next(
    (n) => {
      if (n < 2) round(n + 1),
      for (var i = 0; i < 2; i++) sub(n * 10 + i, limit: 1),
    },
  ),
]);

final done = node('done', (int i) async {
  entered.add('done $i');
  return i;
});

final subsThenDone = Graph<List<int>, Object?>('subsThenDone', [
  Graph.start(ids).next((ids) => {for (final i in ids) sub(i, limit: 1)}),
  Graph.part(sub).next((i) => done(i)),
]);

/// [subsThenDone] as a workflow function, for [startWithSaved].
Future<Object?> subsThenDoneWorkflow(Flow f, List<int> ids) =>
    subsThenDone.runWith(f, ids);

/// The gates [prep] of each copy waits at; one not there is open.
final prepGates = <int, Completer<void>>{};

final prep = node('prep', (int i) async {
  await (prepGates[i]?.future ?? Future<void>.value());
  return i;
});

/// Copies of one call site made by different branches, one by the route of
/// each [prep], in the order the preps end, which a resume does not keep.
final fanIn = Graph<List<int>, Object?>('fanIn', [
  Graph.start(ids).next((ids) => {for (final i in ids) prep(i)}),
  Graph.part(prep).next((i) => sub(i, limit: 1)),
]);

final left = node('left', (int i) async {
  await pause();
  return i;
});

final right = node('right', (int i) async {
  await pause();
  return i;
});

/// A call with a limit from a join's route: a copy of [sub] for each pair
/// of [left] and [right].
final joined = Graph<List<int>, Object?>('joined', [
  Graph.start(ids).next(
    (ids) => {for (final i in ids) left(i), for (final i in ids) right(i)},
  ),
  Graph.join([left, right]).next(((int, int) pair) => sub(pair.$1, limit: 1)),
]);

/// How many [heavy] run now, the most that ran at once, and those that
/// ended.
var heavyRunning = 0;
var mostHeavy = 0;
final heavyDone = <int>[];

final heavy = node('heavy', (int i) async {
  mostHeavy = max(mostHeavy, ++heavyRunning);
  await pause();
  heavyRunning--;
  heavyDone.add(i);
  return i;
}, concurrency: 1);

final heavyInner = Graph<int, Object?>('heavyInner', [
  Graph.start(fan)
      .next((i) => {for (var j = 0; j < 3; j++) heavy(i * 10 + j, limit: 1)}),
]);

/// Limits nested in limits, over a node of one effect at a time.
final heavyOuter = Graph<List<int>, Object?>('heavyOuter', [
  Graph.start(ids).next(
    (ids) => {
      for (final i in ids) heavyInner(i, limit: 2),
      for (final i in ids) heavy(100 + i, limit: 1),
    },
  ),
]);

final failsIfOdd = node('failsIfOdd', (int i) async {
  await pause();
  if (i.isOdd) throw StateError('odd $i');
  return i;
});

final alongside = node('alongside', (int i) async {
  await pause();
  entered.add('alongside $i');
  return i;
});

/// A copy of two branches, one of which fails on an odd input.
final forked = Graph<int, Object?>('forked', [
  Graph.start(fan).next((i) => {failsIfOdd(i), alongside(i)}),
]);

final forkedOfOne = Graph<List<int>, Object?>('forkedOfOne', [
  Graph.start(ids).next((ids) => {for (final i in ids) forked(i, limit: 1)}),
]);

/// How many [capped] run now in each session, by the hundreds of their
/// input, and the most that ran at once in each.
final cappedRunning = <int, int>{};
final mostCapped = <int, int>{};

final capped = node('capped', (int i) async {
  final session = i ~/ 100;
  final now = cappedRunning[session] = (cappedRunning[session] ?? 0) + 1;
  mostCapped[session] = max(mostCapped[session] ?? 0, now);
  mostRunning = max(mostRunning, ++running);
  await taskGate.future;
  await pause();
  running--;
  cappedRunning[session] = cappedRunning[session]! - 1;
  return i;
}, concurrency: 3);

final cappedOfTwo = Graph<List<int>, Object?>('cappedOfTwo', [
  Graph.start(ids).next((ids) => {for (final i in ids) capped(i, limit: 2)}),
]);

/// The copies of [inner] whose tasks ran at once with another's.
var innerOverlap = false;
final innerRunning = <int>{};

final fan = node('fan', (int i) async => i);

final nested = node('nested', (int i) async {
  innerRunning.add(i ~/ 10);
  if (innerRunning.length > 1) innerOverlap = true;
  mostRunning = max(mostRunning, ++running);
  await taskGate.future;
  await pause();
  running--;
  if (running == 0) innerRunning.clear();
  return i;
});

final inner = Graph<int, Object?>('inner', [
  Graph.start(fan)
      .next((i) => {for (var j = 0; j < 3; j++) nested(i * 10 + j, limit: 2)}),
]);

final outer = Graph<List<int>, Object?>('outer', [
  Graph.start(ids).next((ids) => {for (final i in ids) inner(i, limit: 1)}),
]);

/// A flow in [dir] with the codecs of the values above.
Flow flowIn(String dir) => Flow(directory: dir)..addCodec(Plan.fromJson);

/// The effects named [name] of the session [id] of [dir] whose directories
/// are there: the session is locked while it runs.
int writtenEffects(String dir, String id, String name) {
  final effects = Directory(p.join(sessionDirOf(dir, id), 'effects'));
  if (!effects.existsSync()) return 0;
  return effects
      .listSync()
      .where((e) => p.basename(e.path).contains('-$name-'))
      .length;
}

/// How many times each effect of [handle] named [name] started, by its
/// output, or by its id when it has none.
Future<Map<Object?, int>> startsOf(FsSession handle, String name) async {
  final events = await eventsOf(handle);
  return {
    for (final e in await handle.effects())
      if (e.name == name)
        (e.outputId == null
            ? e.id
            : await handle.documentValue(e.outputId!)): events
            .whereType<EffectStarted>()
            .where((s) => s.effectId == e.id)
            .length,
  };
}

void main() {
  setUp(() {
    random = Random(1);
    entered.clear();
    running = 0;
    mostRunning = 0;
    taskGate = Completer();
    live.clear();
    mostLive = 0;
    openAll();
    cappedRunning.clear();
    mostCapped.clear();
    innerOverlap = false;
    innerRunning.clear();
    prepGates.clear();
    heavyRunning = 0;
    mostHeavy = 0;
    heavyDone.clear();
  });

  group('a node', () {
    test('runs at most limit copies at once, each of the calls once', () async {
      final dir = await tempDir();
      final session = await flowIn(dir)
          .start(tasksOfThree, [for (var i = 0; i < 10; i++) i]);
      await until(() => running == 3, 'three tasks');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(running, 3);
      expect(entered, unorderedEquals(['task 0', 'task 1', 'task 2']));
      taskGate.complete();
      await session.result;
      expect(mostRunning, 3);
      final handle = await onlySession(dir);
      final outputs = [
        for (final e in await handle.effects())
          if (e.name == 'task') await handle.documentValue(e.outputId!),
      ];
      expect(outputs, unorderedEquals([for (var i = 0; i < 10; i++) i * 10]));
    });

    test('copies start in the order they were called', () async {
      taskGate.complete();
      final dir = await tempDir();
      await flowIn(dir).run(tasksOfOne, [for (var i = 0; i < 10; i++) i]);
      expect(entered, [for (var i = 0; i < 10; i++) 'task $i']);
      expect(mostRunning, 1);
    });

    test('a call without a limit neither waits nor counts', () async {
      final dir = await tempDir();
      final session = await flowIn(dir).start(tasksAndOneFree, [0, 1, 2]);
      await until(() => running == 2, 'a limited task and the free one');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(entered, unorderedEquals(['task 0', 'task 99']));
      taskGate.complete();
      await session.result;
      expect(entered.where((e) => e != 'task 99'), [
        'task 0',
        'task 1',
        'task 2',
      ]);
    });

    test('a copy that threw gives its slot back', () async {
      taskGate.complete();
      final dir = await tempDir();
      await expectLater(
        flowIn(dir).run(tasksOfOne, [-1, 0, 1]),
        throwsA(isA<StateError>()),
      );
      expect(entered, ['task -1', 'task 0', 'task 1']);
    });
  });

  group('a graph', () {
    test('runs at most limit copies at once, each held from its first node '
        'to its last', () async {
      final dir = await tempDir();
      await flowIn(dir).run(subsOfTwo, [for (var i = 0; i < 8; i++) i]);
      expect(mostLive, 2);
      final handle = await onlySession(dir);
      expect(await startsOf(handle, 'subA'), {
        for (var i = 0; i < 8; i++) i: 1,
      });
      expect(await startsOf(handle, 'subB'), {
        for (var i = 0; i < 8; i++) i: 1,
      });
    });

    test('a copy waiting is not in the time of any effect: the next starts '
        'once the one before has finished', () async {
      final dir = await tempDir();
      await flowIn(dir).run(subsOfOne, [0, 1, 2, 3]);
      final handle = await onlySession(dir);
      final events = await eventsOf(handle);
      final started = <(String, Object?), DateTime>{};
      final finished = <(String, Object?), DateTime>{};
      for (final e in await handle.effects()) {
        if (e.name == 'ids') continue;
        final copy = await handle.documentValue(e.outputId!);
        started[(e.name, copy)] = events
            .whereType<EffectStarted>()
            .singleWhere((s) => s.effectId == e.id)
            .time;
        finished[(e.name, copy)] = events
            .whereType<EffectFinished>()
            .singleWhere((s) => s.effectId == e.id)
            .time;
      }
      for (var i = 1; i < 4; i++) {
        expect(
          started[('subA', i)]!.isBefore(finished[('subB', i - 1)]!),
          isFalse,
          reason: 'copy $i',
        );
      }
      expect(entered, [
        for (var i = 0; i < 4; i++) ...['a $i', 'b $i'],
      ]);
    });

    test('a copy waiting writes nothing', () async {
      close([for (var i = 0; i < 5; i++) i]);
      final dir = await tempDir();
      final session = await flowIn(dir)
          .start(subsOfTwo, [for (var i = 0; i < 5; i++) i]);
      await until(
        () => entered.contains('b 0') && entered.contains('b 1'),
        'two copies at subB',
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(entered, unorderedEquals(['a 0', 'a 1', 'b 0', 'b 1']));
      expect(writtenEffects(dir, session.id, 'subA'), 2);
      expect(writtenEffects(dir, session.id, 'subB'), 2);
      openAll();
      await session.result;
      final handle = await onlySession(dir);
      expect((await startsOf(handle, 'subA')).values, everyElement(1));
      expect(await startsOf(handle, 'subA'), hasLength(5));
    });
  });

  group('the slots are of', () {
    test('a session: two sessions of a graph have their own', () async {
      close([0, 1, 2, 10, 11, 12]);
      final dir = await tempDir();
      final flow = flowIn(dir);
      final one = await flow.start(subsOfOne, [0, 1, 2]);
      final two = await flow.start(subsOfOne, [10, 11, 12]);
      await until(
        () => entered.contains('b 0') && entered.contains('b 10'),
        'a copy of each session at subB',
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(live, {0, 10});
      openAll();
      await Future.wait([one.result, two.result]);
      expect(mostLive, 2);
    });

    test('a graph that calls: two graphs calling one graph have their '
        'own', () async {
      close([0, 1, 2, 10, 11, 12]);
      final dir = await tempDir();
      final session = await flowIn(dir).start(bothParents, [0, 1, 2]);
      await until(
        () => entered.contains('b 0') && entered.contains('b 10'),
        'a copy of each graph at subB',
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(live, {0, 10});
      openAll();
      await session.result;
      expect(mostLive, 2);
    });

    test('a call site: the rounds of a loop share them, in the order of '
        'the calls', () async {
      close([0, 1, 10, 11, 20, 21]);
      final dir = await tempDir();
      final session = await flowIn(dir).start(rounds, 0);
      await until(
        () => entered.contains('round 2') && entered.contains('b 0'),
        'the last round and the first copy at subB',
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(live, {0});
      openAll();
      await session.result;
      expect(mostLive, 1);
      expect(entered.where((e) => e.startsWith('a ')), [
        'a 0',
        'a 1',
        'a 10',
        'a 11',
        'a 20',
        'a 21',
      ]);
    });
  });

  group('a limit', () {
    test('is computed by the route from what it takes', () async {
      for (final parallel in [2, 4]) {
        entered.clear();
        mostRunning = 0;
        taskGate = Completer();
        final dir = await tempDir();
        final session = await flowIn(dir).start(planned, Plan(parallel, 8));
        await until(() => running == parallel, '$parallel tasks');
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(running, parallel);
        taskGate.complete();
        await session.result;
        expect(mostRunning, parallel);
        expect(entered, hasLength(8));
      }
    });

    test('of less than 1 is an ArgumentError of the route', () async {
      final dir = await tempDir();
      await expectLater(
        flowIn(dir).run(planned, Plan(0, 3)),
        throwsA(isA<ArgumentError>()),
      );
      expect(entered, isEmpty);
    });

    test('gives the effects the keys and the after they have without it, '
        'whatever the timing', () async {
      Future<Map<String, String?>> keysOf(
        Graph<List<int>, Object?> graph,
        int seed,
      ) async {
        random = Random(seed);
        final dir = await tempDir();
        await flowIn(dir).run(graph, [0, 1, 2, 3, 4]);
        return {
          for (final e in await (await onlySession(dir)).effects())
            e.key: e.after,
        };
      }

      final free = await keysOf(subsFree, 1);
      expect(free, hasLength(11));
      for (var seed = 1; seed < 8; seed++) {
        expect(await keysOf(subsOfTwo, seed), free, reason: 'seed $seed');
      }
    });

    test('and the concurrency of the node: a copy waits for both', () async {
      final dir = await tempDir();
      final flow = flowIn(dir);
      final one = await flow.start(cappedOfTwo, [0, 1, 2, 3, 4]);
      final two = await flow.start(cappedOfTwo, [100, 101, 102, 103, 104]);
      await until(() => running == 3, 'three capped');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(running, 3);
      expect(cappedRunning.values, unorderedEquals([2, 1]));
      taskGate.complete();
      await Future.wait([one.result, two.result]);
      expect(mostRunning, 3);
      expect(mostCapped.values, everyElement(lessThanOrEqualTo(2)));
    });

    test('in a graph called with a limit: both hold', () async {
      final dir = await tempDir();
      final session = await flowIn(dir).start(outer, [0, 1, 2]);
      await until(() => running == 2, 'two nested');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(running, 2);
      expect(innerRunning, {0});
      taskGate.complete();
      await session.result.timeout(const Duration(seconds: 10));
      expect(mostRunning, 2);
      expect(innerOverlap, isFalse);
    });
  });

  group('a call with a limit', () {
    test('from the route of each of several branches shares one line, a '
        'single call too', () async {
      final dir = await tempDir();
      await flowIn(dir).run(fanIn, [0, 1, 2, 3]);
      expect(mostLive, 1);
      expect(
        entered.where((e) => e.startsWith('a ')),
        unorderedEquals(['a 0', 'a 1', 'a 2', 'a 3']),
      );
    });

    test("from a join's route runs at most limit copies at once", () async {
      final dir = await tempDir();
      await flowIn(dir).run(joined, [0, 1, 2, 3]);
      expect(mostLive, 1);
      expect(
        entered.where((e) => e.startsWith('b ')),
        unorderedEquals(['b 0', 'b 1', 'b 2', 'b 3']),
      );
    });

    test('nested in another, over a node of one effect at a time, in two '
        'sessions, ends', () async {
      final dir = await tempDir();
      final flow = flowIn(dir);
      final one = await flow.start(heavyOuter, [0, 1, 2, 3]);
      final two = await flow.start(heavyOuter, [4, 5, 6]);
      await Future.wait([one.result, two.result])
          .timeout(const Duration(seconds: 20));
      expect(mostHeavy, 1);
      expect(heavyDone, hasLength(4 * 3 + 4 + 3 * 3 + 3));
    });

    test('whose copy has a branch that failed gives the slot back once the '
        'copy has ended', () async {
      final dir = await tempDir();
      await expectLater(
        flowIn(dir)
            .run(forkedOfOne, [0, 1, 2, 3])
            .timeout(const Duration(seconds: 10)),
        throwsA(isA<StateError>()),
      );
      expect(
        entered,
        unorderedEquals([for (var i = 0; i < 4; i++) 'alongside $i']),
      );
    });
  });

  group('on resume', () {
    test('the copies started before take the slots before new ones, and no '
        'more run than the limit', () async {
      final copies = [for (var i = 0; i < 6; i++) i];
      close([0, 2, 3, 4, 5]);
      final dir = await tempDir();
      final first = flowIn(dir);
      final session = await first.start(subsOfTwo, copies);
      await until(
        () => entered.contains('b 0') && entered.contains('b 2'),
        'copies 0 and 2 at subB',
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(entered, isNot(contains('a 3')));
      first.stop();
      openAll();
      await expectLater(session.result, throwsA(isA<FlowStoppedException>()));

      entered.clear();
      live.clear();
      mostLive = 0;
      close(copies);
      final resumed = await flowIn(dir).resume(subsOfTwo, session.id);
      await until(
        () => entered.contains('b 0') && entered.contains('b 2'),
        'copies 0 and 2 at subB again',
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(entered, unorderedEquals(['b 0', 'b 2']));
      open(0);
      await until(() => entered.contains('b 3'), 'copy 3 at subB');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(live, {2, 3});
      openAll();
      await resumed.result;
      expect(mostLive, 2);
      expect(
        entered.where((e) => e.startsWith('a ')),
        unorderedEquals(['a 3', 'a 4', 'a 5']),
      );
      final handle = await onlySession(dir);
      expect(await startsOf(handle, 'subA'), {for (final i in copies) i: 1});
      expect(await startsOf(handle, 'subB'), {
        for (final i in copies) i: i == 0 || i == 2 ? 2 : 1,
      });
    });

    test('the copies started before go first even when other branches make '
        'the copies in another order than before', () async {
      close([0, 1, 2]);
      for (final i in [0, 1, 2]) {
        prepGates[i] = Completer();
      }
      final dir = await tempDir();
      final first = flowIn(dir);
      final session = await first.start(fanIn, [0, 1, 2]);
      // Copy 2 is called first and runs; 0 and 1 wait for it.
      prepGates[2]!.complete();
      await until(() => entered.contains('b 2'), 'copy 2 at subB');
      prepGates[0]!.complete();
      prepGates[1]!.complete();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(entered, ['a 2', 'b 2']);
      first.stop();
      openAll();
      await expectLater(session.result, throwsA(isA<FlowStoppedException>()));

      // On resume the preps replay in their order, making copy 2 last.
      entered.clear();
      live.clear();
      mostLive = 0;
      close([0, 1, 2]);
      final resumed = await flowIn(dir).resume(fanIn, session.id);
      await until(() => entered.contains('b 2'), 'copy 2 at subB again');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(entered, ['b 2']);
      open(2);
      await until(
        () => entered.contains('b 0') || entered.contains('b 1'),
        'a new copy at subB',
      );
      openAll();
      await resumed.result;
      expect(mostLive, 1);
      final handle = await onlySession(dir);
      expect(await startsOf(handle, 'subA'), {0: 1, 1: 1, 2: 1});
      expect(await startsOf(handle, 'subB'), {0: 1, 1: 1, 2: 2});
    });

    test('a copy whose every effect is saved takes no slot: it ends while '
        'the only one is taken', () async {
      final saved = <String, ({String? after, Object? value})>{};
      final before = await tempDir();
      await (await startWithSaved(flowIn(before), subsThenDoneWorkflow, [
        0,
        1,
      ], const {})).result;
      final handle = await onlySession(before);
      for (final e in await handle.effects()) {
        final value = await handle.documentValue(e.outputId!);
        if (e.name.startsWith('sub') && value == 1) {
          saved[e.key] = (after: e.after, value: value);
        }
      }
      expect(saved, hasLength(2));

      entered.clear();
      close([0]);
      final dir = await tempDir();
      final session = await startWithSaved(flowIn(dir), subsThenDoneWorkflow, [
        0,
        1,
      ], saved);
      await until(
        () => entered.contains('done 1') && entered.contains('b 0'),
        'copy 1 done while copy 0 is at subB',
      );
      expect(live, {0});
      expect(entered, isNot(contains('a 1')));
      openAll();
      await session.result;
    });
  });

  test('a stop while copies wait ends the session and writes nothing for '
      'those waiting', () async {
    close([for (var i = 0; i < 5; i++) i]);
    final dir = await tempDir();
    final flow = flowIn(dir);
    final session = await flow.start(subsOfTwo, [
      for (var i = 0; i < 5; i++) i,
    ]);
    await until(
      () => entered.contains('b 0') && entered.contains('b 1'),
      'two copies at subB',
    );
    flow.stop();
    openAll();
    await expectLater(session.result, throwsA(isA<FlowStoppedException>()));
    final handle = await onlySession(dir);
    final names = [for (final e in await handle.effects()) e.name];
    expect(names.where((n) => n == 'subA'), hasLength(2));
    expect(names.where((n) => n == 'subB'), hasLength(2));
    expect(entered, unorderedEquals(['a 0', 'a 1', 'b 0', 'b 1']));
  });
}
