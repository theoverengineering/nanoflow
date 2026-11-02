// A route for a failed call (failure route design): a part of a graph says
// what follows when the call of its node — a node or a graph — fails. The
// failure route gets the call's input and the failure; the failure fails
// neither the branch nor the session, and is final on resume. A stop and the
// end of the session by its store or a codec are no failure.

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:nanoflow/nanoflow.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:test/test.dart';

import 'support.dart';

/// What the bodies of the nodes did, in order.
final ran = <String>[];

/// What the failure routes got, in order: the input and the failure.
final routed = <String>[];

/// The gates the nodes wait at, by name; one not there is open.
final gates = <String, Completer<void>>{};

/// Completed when a node comes to the gate of its name.
final atGates = <String, Completer<void>>{};

/// Closes the gate [name]: a node that comes to it waits until [open].
void close(String name) {
  gates[name] = Completer();
  atGates[name] = Completer();
}

void open(String name) {
  if (gates.remove(name) case final gate? when !gate.isCompleted) {
    gate.complete();
  }
}

/// Completes once a node has come to the gate [name].
Future<void> cameTo(String name) => atGates[name]!.future;

Future<void> gate(String name) async {
  if (atGates[name] case final at? when !at.isCompleted) at.complete();
  await gates[name]?.future;
}

/// Throws a [StateError] for an input with `bad` in it, after its gate.
final risky = node('risky', (String s) async {
  ran.add('risky $s');
  await gate('risky $s');
  if (s.contains('bad')) throw StateError('boom $s');
  return s.toUpperCase();
});

final settle = node('settle', (String s) async {
  ran.add('settle $s');
  return 'settled $s';
});

final giveBack = node('giveBack', (String s) async {
  ran.add('giveBack $s');
  await gate('giveBack $s');
  return 'gave back $s';
});

final hold = node('hold', (String s) async {
  ran.add('hold $s');
  await gate('hold');
  return 'held $s';
});

final prepare = node('prepare', (String s) async {
  ran.add('prepare $s');
  return s;
});

final slow = node('slow', (String s) async {
  ran.add('slow $s');
  await gate('slow');
  return 'slow $s';
});

/// The failure route the graphs share: notes what it got, and gives the
/// input back with the error's text.
Next back(String input, CallFailure failure) {
  routed.add('$input: $failure');
  return giveBack('$input: ${failure.error}');
}

final guarded = Graph<String, String>('guarded', [
  Graph.start(risky).next((s) => settle(s)).failed(back),
]);

/// [guarded] without its failure route.
final unguarded = Graph<String, String>('unguarded', [
  Graph.start(risky).next((s) => settle(s)),
]);

/// [guarded], then [hold].
final guardedThenHold = Graph<String, String>('guardedThenHold', [
  Graph.start(risky).next((s) => settle(s)).failed(back),
  Graph.part(giveBack).next((s) => hold(s)),
  Graph.part(settle).next((s) => hold(s)),
]);

/// [risky] two levels down: in [deep], in [middle].
final deep = Graph<String, String>('deep', [
  Graph.start(risky).next((s) => settle(s)),
]);

final middle = Graph<String, String>('middle', [
  Graph.start(prepare).next((s) => deep(s)),
]);

final outer = Graph<String, String>('outer', [
  Graph.start(slow).next((s) => middle(s)),
  Graph.part(middle).next((s) => hold(s)).failed(back),
  Graph.part(giveBack).next((s) => hold(s)),
]);

/// A graph whose route throws for an input that starts with `bad`.
final picky = Graph<String, String>('picky', [
  Graph.start(prepare).next(
    (s) => s.startsWith('bad') ? throw StateError('no way for $s') : settle(s),
  ),
]);

final pickyCalled = Graph<String, String>('pickyCalled', [
  Graph.start(picky).failed(back),
]);

/// A graph whose result is not its type.
final mistyped = Graph<String, int>('mistyped', [Graph.start(prepare)]);

final mistypedCalled = Graph<String, Object?>('mistypedCalled', [
  Graph.start(mistyped).failed(back),
]);

/// [risky] and [slow] side by side: [risky] fails while [slow] runs.
final besides = Graph<String, String>('besides', [
  Graph.start(risky),
  Graph.start(slow),
]);

final besidesCalled = Graph<String, String>('besidesCalled', [
  Graph.start(besides).failed(back),
]);

/// [guarded], which catches the failure of its node, called with a failure
/// route of its own.
final guardedCalled = Graph<String, String>('guardedCalled', [
  Graph.start(guarded).failed((s, f) {
    routed.add('outer $s: $f');
    return null;
  }),
]);

final left = node('left', (String s) async => 'left $s');

final right = node('right', (String s) async => 'right $s');

/// A graph whose join's route throws.
final joined = Graph<String, String>('joined', [
  Graph.start(prepare).next((s) => {left(s), right(s)}),
  Graph.join([
    left,
    right,
  ]).next(((String, String) both) => throw StateError('no way for ${both.$1}')),
]);

final joinedCalled = Graph<String, String>('joinedCalled', [
  Graph.start(joined).failed(back),
]);

final names = node('names', (List<String> names) async => names);

final each = Graph<List<String>, Object?>('each', [
  Graph.start(names).next((names) => {for (final n in names) risky(n)}),
  Graph.part(risky).next((s) => settle(s)).failed(back),
]);

/// [each] without its failure route.
final eachUnguarded = Graph<List<String>, Object?>('eachUnguarded', [
  Graph.start(names).next((names) => {for (final n in names) risky(n)}),
]);

final ids = node('ids', (List<int> ids) async => ids);

final claim = node('claim', (int i) async {
  ran.add('claim $i');
  return i;
});

/// Fails for 0.
final develop = node('develop', (int i) async {
  ran.add('develop $i');
  if (i == 0) throw StateError('develop $i failed');
  return i;
});

final settleIdea = node('settleIdea', (int i) async {
  ran.add('settle $i');
  return i;
});

final giveBackIdea = node('giveBackIdea', (int i) async {
  ran.add('giveBack $i');
  await gate('giveBack $i');
  ran.add('gave back $i');
  return -i;
});

/// One idea of a night: its slot is held from [claim] to [settleIdea] or
/// [giveBackIdea].
final nightIdea = Graph<int, int>('nightIdea', [
  Graph.start(claim).next((i) => develop(i)),
  Graph.part(develop)
      .next((i) => settleIdea(i))
      .failed((i, f) => giveBackIdea(i)),
]);

final night = Graph<List<int>, Object?>('night', [
  Graph.start(ids).next((ids) => {for (final i in ids) nightIdea(i, limit: 1)}),
]);

/// [develop] called with a limit, its failure route on its own part: after
/// the copy.
final developEach = Graph<List<int>, Object?>('developEach', [
  Graph.start(ids).next((ids) => {for (final i in ids) develop(i, limit: 1)}),
  Graph.part(develop).failed((i, f) => giveBackIdea(i)),
]);

/// Throws `late` after a while.
final lateFail = node('lateFail', (String s) async {
  await Future<void>.delayed(const Duration(milliseconds: 30));
  ran.add('lateFail');
  throw StateError('late');
});

/// Throws `early` at once.
final earlyFail = node('earlyFail', (String s) async {
  ran.add('earlyFail');
  throw StateError('early');
});

final twoFail = Graph<String, String>('twoFail', [
  Graph.start(lateFail),
  Graph.start(earlyFail),
]);

final twoFailCalled = Graph<String, String>('twoFailCalled', [
  Graph.start(twoFail).failed(back),
  Graph.part(giveBack).next((s) => hold(s)),
]);

final ended = Graph<String, Object?>('ended', [
  Graph.start(risky).failed((s, f) => null),
  Graph.start(prepare),
]);

final throwing = Graph<String, Object?>('throwing', [
  Graph.start(risky).failed((s, f) => throw StateError('the route threw')),
]);

final givingOther = Graph<String, Object?>('givingOther', [
  Graph.start(risky).failed((s, f) => 'giveBack'),
]);

final class Produced {
  Produced(this.text);

  factory Produced.fromJson(Map<String, Object?> json) =>
      Produced(json['text']! as String);

  final String text;

  Map<String, Object?> toJson() => {'text': text};
}

final produce = node('produce', (String s) async {
  ran.add('produce $s');
  return Produced(s);
});

final heldProduce = node('heldProduce', (Produced p) async {
  ran.add('hold ${p.text}');
  await gate('hold');
  return p.text;
});

final produced = Graph<String, String>('produced', [
  Graph.start(produce).next((p) => heldProduce(p)),
]);

final producedCalled = Graph<String, String>('producedCalled', [
  Graph.start(produced).failed(back),
]);

/// Takes a random while, as [pause] does.
final paced = node('paced', (String s) async {
  await pause();
  if (s.startsWith('bad')) throw StateError('boom $s');
  return s;
});

final pacedAfter = node('pacedAfter', (String s) async {
  await pause();
  return s;
});

final pacedEach = Graph<List<String>, Object?>('pacedEach', [
  Graph.start(names).next((names) => {for (final n in names) paced(n)}),
  Graph.part(paced)
      .next((s) => pacedAfter(s))
      .failed((s, f) => {pacedAfter('$s back'), pacedAfter('$s again')}),
]);

/// [pacedEach] without its failure route.
final pacedEachUnguarded = Graph<List<String>, Object?>('pacedEachUnguarded', [
  Graph.start(names).next((names) => {for (final n in names) paced(n)}),
  Graph.part(paced).next((s) => pacedAfter(s)),
]);

Flow flowIn(String dir) => Flow(directory: dir)..addCodec(Produced.fromJson);

/// The effects of the only session of [dir], in the order they started.
Future<List<Effect>> effectsIn(String dir) async =>
    (await onlySession(dir)).effects();

/// The names of the events of the only session of [dir], read without
/// owning it: it can be resumed after.
Future<List<String>> eventsIn(String dir) async =>
    eventNamesOf(dir, sessionIds(dir).single);

/// Stops [flow] once a node has come to the gate [name], then opens it:
/// the session of [session] ends with a [FlowStoppedException].
Future<void> stopAt(
  Flow flow,
  FlowSession<Object?> session,
  String name,
) async {
  await cameTo(name);
  flow.stop();
  open(name);
  await expectLater(session.result, throwsA(isA<FlowStoppedException>()));
}

void main() {
  setUp(() {
    ran.clear();
    routed.clear();
    gates.clear();
    atGates.clear();
  });

  group('a node that fails', () {
    test('goes on along its failure route, which gets its input and the '
        'failure: the session finishes', () async {
      final dir = await tempDir();
      expect(
        await flowIn(dir).run(guarded, 'bad'),
        'gave back bad: Bad '
        'state: boom bad',
      );
      expect(routed, ['bad: CallFailure(StateError: Bad state: boom bad)']);
      expect(ran, ['risky bad', 'giveBack bad: Bad state: boom bad']);
      expect(await eventsIn(dir), [
        'session-started',
        'effect-started',
        'effect-failed',
        'effect-started',
        'effect-finished',
        'session-finished',
      ]);
      final failed = (await eventsOf(await onlySession(dir)))
          .whereType<EffectFailed>()
          .single;
      expect(failed.error, 'Bad state: boom bad');
      expect(failed.errorType, 'StateError');
    });

    test('that does not fail goes on along its route', () async {
      final dir = await tempDir();
      expect(await flowIn(dir).run(guarded, 'ok'), 'settled OK');
      expect(routed, isEmpty);
    });

    test('is followed by the effects of its failure route, as by those of its '
        'route', () async {
      final dir = await tempDir();
      await flowIn(dir).run(guarded, 'bad');
      final [failed, givenBack] = await effectsIn(dir);
      expect(givenBack.after, failed.key);
      final other = await tempDir();
      await flowIn(other).run(guarded, 'ok');
      final [finished, settled] = await effectsIn(other);
      expect(settled.after, finished.key);
      // One context goes on from the node either way.
      expect(givenBack.key.split('@').last, settled.key.split('@').last);
    });

    test('without a failure route fails the session as before', () async {
      final dir = await tempDir();
      await expectLater(
        flowIn(dir).run(unguarded, 'bad'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'boom '
                'bad',
          ),
        ),
      );
      expect(await eventsIn(dir), contains('session-failed'));
    });

    test('in a copy of a for element goes along the failure route alone; the '
        'other copies go on along the route', () async {
      final dir = await tempDir();
      await flowIn(dir).run(each, ['a', 'bad', 'c']);
      expect(routed, ['bad: CallFailure(StateError: Bad state: boom bad)']);
      expect(
        ran,
        containsAll([
          'settle A',
          'settle C',
          'giveBack bad: Bad state: boom bad',
        ]),
      );
      expect(ran.where((r) => r.startsWith('settle')), hasLength(2));
    });
  });

  group('a graph that fails', () {
    test('two levels down goes on along the failure route of its call, which '
        'gets its input and the failure', () async {
      final dir = await tempDir();
      expect(
        await flowIn(dir).run(outer, 'bad'),
        'held gave back slow bad: Bad state: boom slow bad',
      );
      expect(routed, [
        'slow bad: CallFailure(StateError: Bad state: boom slow bad)',
      ]);
      expect(ran, [
        'slow bad',
        'prepare slow bad',
        'risky slow bad',
        'giveBack slow bad: Bad state: boom slow bad',
        'hold gave back slow bad: Bad state: boom slow bad',
      ]);
      expect(await eventsIn(dir), isNot(contains('session-failed')));
    });

    test('is followed by the effects of its failure route as by those of its '
        'route: after the effect before the call', () async {
      final dir = await tempDir();
      await flowIn(dir).run(outer, 'bad');
      final effects = await effectsIn(dir);
      final first = effects.firstWhere((e) => e.name == 'slow');
      expect(effects.firstWhere((e) => e.name == 'giveBack').after, first.key);
      final other = await tempDir();
      await flowIn(other).run(outer, 'ok');
      final passed = await effectsIn(other);
      final before = passed.firstWhere((e) => e.name == 'slow');
      expect(passed.firstWhere((e) => e.name == 'hold').after, before.key);
    });

    test('by a route of its own is caught as well', () async {
      final dir = await tempDir();
      await flowIn(dir).run(pickyCalled, 'bad');
      expect(routed, [
        'bad: CallFailure(StateError: Bad state: no way for '
            'bad)',
      ]);
    });

    test('by the route of a join is caught as well', () async {
      final dir = await tempDir();
      await flowIn(dir).run(joinedCalled, 'x');
      expect(routed, [
        'x: CallFailure(StateError: Bad state: no way for left '
            'x)',
      ]);
    });

    test('whose failure a part of it caught has not failed', () async {
      final dir = await tempDir();
      expect(
        await flowIn(dir).run(guardedCalled, 'bad'),
        'gave back bad: Bad state: boom bad',
      );
      expect(routed, ['bad: CallFailure(StateError: Bad state: boom bad)']);
    });

    test('by a result that is not its type is caught as well', () async {
      final dir = await tempDir();
      await flowIn(dir).run(mistypedCalled, 'x');
      expect(routed.single, startsWith('x: CallFailure('));
      expect(routed.single, contains('TypeError'));
    });

    test('fails once its other branches have ended, and its failure route '
        'goes on after them', () async {
      final dir = await tempDir();
      close('slow');
      final session = await flowIn(dir).start(besidesCalled, 'bad');
      await cameTo('slow');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(routed, isEmpty);
      open('slow');
      expect(await session.result, 'gave back bad: Bad state: boom bad');
      expect(ran.take(2), unorderedEquals(['risky bad', 'slow bad']));
      expect(ran.skip(2), ['giveBack bad: Bad state: boom bad']);
    });

    test('in several branches gives the failure of the first in the graph\'s '
        'order, not the first in time', () async {
      final dir = await tempDir();
      await flowIn(dir).start(twoFailCalled, 'x').then((s) => s.result);
      expect(ran.take(2), ['earlyFail', 'lateFail']);
      expect(routed, ['x: CallFailure(StateError: Bad state: late)']);
    });
  });

  group('a caught failure is final', () {
    test(
      'the node that failed does not run again on resume; its failure '
      'route gets the same failure, its next node comes from the journal',
      () async {
        final dir = await tempDir();
        close('hold');
        final flow = flowIn(dir);
        final first = await flow.start(guardedThenHold, 'bad');
        await stopAt(flow, first, 'hold');
        final resumed = await flowIn(dir).resume(guardedThenHold, first.id);
        expect(await resumed.result, 'held gave back bad: Bad state: boom bad');
        expect(ran, [
          'risky bad',
          'giveBack bad: Bad state: boom bad',
          'hold gave back bad: Bad state: boom bad',
          'hold gave back bad: Bad state: boom bad',
        ]);
        expect(routed, [
          'bad: CallFailure(StateError: Bad state: boom bad)',
          'bad: CallFailure(StateError: Bad state: boom bad)',
        ]);
        final events = await eventsIn(dir);
        expect(events.where((e) => e == 'effect-failed'), hasLength(1));
        expect(events.where((e) => e == 'effect-started'), hasLength(4));
      },
    );

    test('in a graph: none of its nodes runs again on resume, and its '
        'failure route gets the same failure', () async {
      final dir = await tempDir();
      close('hold');
      final flow = flowIn(dir);
      final first = await flow.start(outer, 'bad');
      await stopAt(flow, first, 'hold');
      final resumed = await flowIn(dir).resume(outer, first.id);
      expect(
        await resumed.result,
        'held gave back slow bad: Bad state: boom slow bad',
      );
      expect(ran, [
        'slow bad',
        'prepare slow bad',
        'risky slow bad',
        'giveBack slow bad: Bad state: boom slow bad',
        'hold gave back slow bad: Bad state: boom slow bad',
        'hold gave back slow bad: Bad state: boom slow bad',
      ]);
      expect(routed.toSet(), hasLength(1));
      expect(routed, hasLength(2));
    });

    test('in a graph that was cut before its other branch ended: the node '
        'that failed does not run again, the one that ran runs again, and '
        'then the failure route goes on', () async {
      final dir = await tempDir();
      close('slow');
      final flow = flowIn(dir);
      final first = await flow.start(besidesCalled, 'bad');
      await until(
        () => eventNamesOf(dir, first.id).contains('effect-failed'),
        'the failure in the journal',
      );
      // The stop is no failure: nothing caught it.
      await stopAt(flow, first, 'slow');
      expect(routed, isEmpty);
      final resumed = await flowIn(dir).resume(besidesCalled, first.id);
      expect(await resumed.result, 'gave back bad: Bad state: boom bad');
      expect(ran.take(2), unorderedEquals(['risky bad', 'slow bad']));
      expect(ran.skip(2), ['slow bad', 'giveBack bad: Bad state: boom bad']);
      expect(routed, ['bad: CallFailure(StateError: Bad state: boom bad)']);
    });

    test('of several branches, the same on resume as before', () async {
      final dir = await tempDir();
      close('hold');
      final flow = flowIn(dir);
      final first = await flow.start(twoFailCalled, 'x');
      await stopAt(flow, first, 'hold');
      final resumed = await flowIn(dir).resume(twoFailCalled, first.id);
      await resumed.result;
      expect(routed, [
        'x: CallFailure(StateError: Bad state: late)',
        'x: CallFailure(StateError: Bad state: late)',
      ]);
      expect(ran.where((r) => r.endsWith('Fail')), hasLength(2));
    });

    test('but a node without a failure route round it runs again on resume, '
        'as before', () async {
      final dir = await tempDir();
      close('risky ok');
      final flow = flowIn(dir);
      final first = await flow.start(eachUnguarded, ['bad', 'ok']);
      await until(
        () => eventNamesOf(dir, first.id).contains('effect-failed'),
        'the failure in the journal',
      );
      await stopAt(flow, first, 'risky ok');
      await expectLater(
        flowIn(dir).resume(eachUnguarded, first.id).then((s) => s.result),
        throwsA(isA<StateError>()),
      );
      expect(ran.where((r) => r == 'risky bad'), hasLength(2));
    });
  });

  group('no failure route catches', () {
    test('a stop: the session ends with it, and the node runs again on '
        'resume', () async {
      final dir = await tempDir();
      close('risky bad');
      final flow = flowIn(dir);
      final first = await flow.start(guarded, 'bad');
      await stopAt(flow, first, 'risky bad');
      expect(routed, isEmpty);
      expect(await eventsIn(dir), isNot(contains('effect-failed')));
      final resumed = await flowIn(dir).resume(guarded, first.id);
      expect(await resumed.result, 'gave back bad: Bad state: boom bad');
      expect(ran.where((r) => r == 'risky bad'), hasLength(2));
      expect(routed, hasLength(1));
    });

    test('a failure of the store: the session ends with it', () async {
      final dir = await tempDir();
      close('risky bad');
      final session = await flowIn(dir).start(guarded, 'bad');
      await cameTo('risky bad');
      Directory(sessionDirOf(dir, session.id)).deleteSync(recursive: true);
      open('risky bad');
      await expectLater(session.result, throwsA(isA<StorageException>()));
      expect(routed, isEmpty);
    });

    test('a saved result whose type has no codec on resume: the session ends '
        'with the CodecException', () async {
      final dir = await tempDir();
      close('hold');
      final flow = flowIn(dir);
      final first = await flow.start(producedCalled, 'x');
      await stopAt(flow, first, 'hold');
      await expectLater(
        Flow(directory: dir)
            .resume(producedCalled, first.id)
            .then((s) => s.result),
        throwsA(isA<CodecException>()),
      );
      expect(routed, isEmpty);
      expect(ran, ['produce x', 'hold x']);
    });
  });

  group('a failure route', () {
    test(
      'that gives null ends its branch, and gives the graph no result',
      () async {
        final dir = await tempDir();
        expect(await flowIn(dir).run(ended, 'bad'), 'bad');
        expect(ran, containsAll(['risky bad', 'prepare bad']));
      },
    );

    test('that throws fails the session with its exception', () async {
      final dir = await tempDir();
      await expectLater(
        flowIn(dir).run(throwing, 'bad'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'the route '
                'threw',
          ),
        ),
      );
    });

    test('that gives neither a Next, a set of them nor null is a StateError '
        'that names it', () async {
      final dir = await tempDir();
      await expectLater(
        flowIn(dir).run(givingOther, 'bad'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'graph "givingOther": the failure route of risky gave giveBack: '
                'a route gives a Next, a set of them or null',
          ),
        ),
      );
    });
  });

  group('in a copy of a call with a limit', () {
    test(
      'the failure route and what follows it hold the copy\'s slot',
      () async {
        final dir = await tempDir();
        close('giveBack 0');
        final session = await flowIn(dir).start(night, [0, 1]);
        await cameTo('giveBack 0');
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(ran, ['claim 0', 'develop 0', 'giveBack 0']);
        open('giveBack 0');
        await session.result;
        expect(ran, [
          'claim 0',
          'develop 0',
          'giveBack 0',
          'gave back 0',
          'claim 1',
          'develop 1',
          'settle 1',
        ]);
      },
    );

    test('a failure route on the part of the call itself comes after the '
        'copy, as a route does', () async {
      final dir = await tempDir();
      close('giveBack 0');
      final session = await flowIn(dir).start(developEach, [0, 1]);
      await cameTo('giveBack 0');
      await until(() => ran.contains('develop 1'), 'the second copy');
      open('giveBack 0');
      await session.result;
    });
  });

  group('keys', () {
    test(
      'are the same and follow the same effects whatever the timing',
      () async {
        Future<Map<String, String?>> keysAt(int seed) async {
          random = Random(seed);
          final dir = await tempDir();
          await flowIn(dir).run(pacedEach, ['a', 'bad1', 'b', 'bad2']);
          return {for (final e in await effectsIn(dir)) e.key: e.after};
        }

        final first = await keysAt(1);
        expect(first, hasLength(1 + 4 + 2 + 4));
        for (var seed = 2; seed < 8; seed++) {
          expect(await keysAt(seed), first, reason: 'seed $seed');
        }
      },
    );

    test('of the effects round a call are the same as without its failure '
        'route', () async {
      Future<Map<String, String?>> keysOf(
        Graph<List<String>, Object?> g,
      ) async {
        random = Random(1);
        final dir = await tempDir();
        await flowIn(dir).run(g, ['a', 'b', 'c']);
        return {for (final e in await effectsIn(dir)) e.key: e.after};
      }

      expect(await keysOf(pacedEach), await keysOf(pacedEachUnguarded));
    });
  });
}
