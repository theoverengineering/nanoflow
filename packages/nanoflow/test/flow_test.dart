import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:nanoflow/nanoflow.dart';
import 'package:nanoflow/src/flow.dart' show startWithSaved, WorkflowFunctions;
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_store/nanoflow_store.dart' show FsStore;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support.dart';

Future<String> review(Flow f, String branch) async {
  final diff = await f.effect('collect', () => 'change of $branch'); // collect
  return f.effect('inspect', () async => '$diff: clean'); // inspect
}

Future<String> flaky(Flow f, String target) async {
  try {
    await f.effect<String>('deploy', () => throw StateError('no\r\ndisk'));
  } on StateError catch (e) {
    return f.effect('rollback', () => 'rolled back $target: ${e.message}');
  }
  return 'deployed';
}

Future<String> broken(Flow f, String branch) async {
  await f.effect('collect', () => 'change of $branch');
  throw StateError('broken\nworkflow');
}

/// What each [gated] session waits for, by its input.
final gates = <String, Completer<String>>{};

Future<String> gated(Flow f, String who) async {
  final opened = await f.effect('wait', () => gates[who]!.future);
  return f.effect('echo', () => '$who after $opened');
}

/// Starts an effect it does not await, which waits for the gate of [who].
Future<String> leavesEffect(Flow f, String who) async {
  unawaited(f.effect('background', () => gates[who]!.future));
  return 'returned';
}

/// What the effect that each [callsLate] session calls after its workflow
/// returned gave, or threw, by input.
final lateEffects = <String, Future<Object?>>{};

/// Calls an effect 10 ms after it returned.
Future<String> callsLate(Flow f, String who) async {
  lateEffects[who] = Future<Object?>.delayed(
    const Duration(milliseconds: 10),
    () => f.effect('late', () => 'late'),
  ).then((value) => value, onError: (Object e) => e);
  return 'returned';
}

Future<String> describeDate(Flow f, DateTime date) async => '$date';

Future<String> datedEffect(Flow f, String x) async {
  try {
    await f.effect('date', () => DateTime.utc(2026, 10, 3));
  } on CodecException catch (e) {
    return 'failed: $e';
  }
  return 'dated';
}

Future<DateTime> datedResult(Flow f, String x) async =>
    DateTime.utc(2026, 10, 3);

/// An effect awaited later through Future.wait, then copies whose first await
/// is not an effect, with random pauses.
Future<String> release(Flow f, String version) async {
  final pending = f.effect('download', () => work('src-$version'));
  await pause();
  await pause();
  final [source] = await Future.wait([pending]);
  final results = await Future.wait([
    for (final pkg in ['core', 'tool'])
      () async {
        await pause(); // like http.get outside any effect
        final up = await f.effect('upload', () => work('$pkg:$source'));
        return f.effect('verify', () => work('$up:verified'));
      }(),
  ]);
  return f.effect('announce', () => work(results.join(' | ')));
}

/// A plain future started early, like an http.get, awaited later — done by
/// then or not — then copies whose first await is not an effect, with random
/// pauses.
Future<String> fetchLater(Flow f, String version) async {
  final pending = work('src-$version');
  await pause();
  await pause();
  final source = await pending;
  final results = await Future.wait([
    for (final pkg in ['core', 'tool'])
      () async {
        await pause(); // like http.get outside any effect
        final up = await f.effect('upload', () => work('$pkg:$source'));
        return f.effect('verify', () => work('$up:verified'));
      }(),
  ]);
  return f.effect('announce', () => work(results.join(' | ')));
}

/// Items of a stream that a producer adds after pauses, each handled in
/// `await for` by copies whose first await is not an effect.
Future<String> streamed(Flow f, String version) async {
  final controller = StreamController<String>();
  unawaited(() async {
    for (final item in ['a', 'b', 'c', 'd']) {
      await pause();
      await pause();
      controller.add('$item-$version');
    }
    await controller.close();
  }());
  final handled = <String>[];
  await for (final item in controller.stream) {
    final results = await Future.wait([
      for (final pkg in ['core', 'tool'])
        () async {
          await pause(); // like http.get outside any effect
          return f.effect('upload', () => work('$pkg:$item'));
        }(),
    ]);
    handled.add(results.join('+'));
  }
  return f.effect('announce', () => work(handled.join(' | ')));
}

/// The effect records of the session [sessionId] of [dir].
Future<List<Effect>> effectsOf(String dir, String sessionId) async =>
    (await openSession(dir, sessionId)).effects();

/// A flow other than the one that runs [otherFlowEffect].
late Flow otherFlow;

Future<String> otherFlowEffect(Flow f, String x) async =>
    otherFlow.effect('collect', () => x);

/// A stack trace's text that names this file.
final namesThisFile = contains('flow_test.dart');

void main() {
  group('run', () {
    test('writes one session: the input, a record and events for every effect '
        'and the result', () async {
      final dir = await tempDir();
      final flow = Flow(directory: dir);
      expect(flow.directory, dir);

      expect(await flow.runWorkflow(review, 'main'), 'change of main: clean');

      final handle = await onlySession(dir);
      final session = handle.session;
      expect(session.workflow, 'review');
      expect(session.graph, isNull);
      expect(await handle.documentValue(session.inputId!), 'main');
      expect(p.basename(handle.dir), startsWith('review-'));

      final effects = await handle.effects();
      expect([for (final s in effects) s.name], ['collect', 'inspect']);
      final [collect, inspect] = effects;
      final root = h('');
      expect(collect.key, 'collect#1@$root');
      expect(collect.after, isNull);
      expect(collect.place, placeOfMarker('collect'));
      expect(inspect.key, 'inspect#1@${h(collect.key)}');
      expect(inspect.after, collect.key);
      expect(inspect.place, placeOfMarker('inspect'));
      expect(await handle.documentValue(collect.outputId!), 'change of main');
      expect(
        await handle.documentValue(inspect.outputId!),
        'change of main: clean',
      );

      final events = await eventsOf(handle);
      expect(events.map((e) => e.name), [
        'session-started',
        'effect-started',
        'effect-finished',
        'effect-started',
        'effect-finished',
        'session-finished',
      ]);
      expect(
        events[1],
        isA<EffectStarted>().having((e) => e.effectId, 'effectId', collect.id),
      );
      expect(
        events[2],
        isA<EffectFinished>()
            .having((e) => e.effectId, 'effectId', collect.id)
            .having((e) => e.outputId, 'outputId', collect.outputId),
      );
      expect(
        events[3],
        isA<EffectStarted>().having((e) => e.effectId, 'effectId', inspect.id),
      );
      expect(
        events[4],
        isA<EffectFinished>()
            .having((e) => e.effectId, 'effectId', inspect.id)
            .having((e) => e.outputId, 'outputId', inspect.outputId),
      );
      final finished = events[5] as SessionFinished;
      expect(
        await handle.documentValue(finished.outputId!),
        'change of main: clean',
      );
      expect(replaySession(events).status, SessionStatus.finished);
    });

    test('records the graph file and the code hash the session starts '
        'with', () async {
      final dir = await tempDir();
      File(p.join(dir, 'lib', 'review.dart'))
        ..parent.createSync()
        ..writeAsStringSync('// review\n');
      const graph = {'format': 2, 'package': 'review_example'};
      File(p.join(dir, 'nanoflow.graph.json'))
          .writeAsStringSync(jsonEncode(graph));

      await Flow(directory: dir).runWorkflow(review, 'main');

      final handle = await onlySession(dir);
      expect(handle.session.graph, graph);
      final started = (await eventsOf(handle)).first as SessionStarted;
      expect(
        started.code,
        fingerprintOf({
          'lib/review.dart': sourceHash(utf8.encode('// review\n')),
        }),
      );
    });
  });

  test('an effect that throws fails, and its exception reaches the '
      'workflow', () async {
    final dir = await tempDir();

    expect(
      await Flow(directory: dir).runWorkflow(flaky, 'prod'),
      'rolled back prod: no\r\ndisk',
    );

    final handle = await onlySession(dir);
    final [deploy, rollback] = await handle.effects();
    expect(deploy.name, 'deploy');
    expect(deploy.outputId, isNull);
    final events = await eventsOf(handle);
    expect(events.map((e) => e.name), [
      'session-started',
      'effect-started',
      'effect-failed',
      'effect-started',
      'effect-finished',
      'session-finished',
    ]);
    expect(
      events[2],
      isA<EffectFailed>()
          .having((e) => e.effectId, 'effectId', deploy.id)
          .having((e) => e.error, 'error', 'Bad state: no disk')
          .having((e) => e.stack, 'stack', namesThisFile),
    );
    // An exception is not a result: the code that caught it took no effect's.
    expect(rollback.after, isNull);
  });

  test('a workflow that throws fails the session, and its result is the '
      'exception', () async {
    final dir = await tempDir();

    final session = await Flow(directory: dir).startWorkflow(broken, 'main');
    await expectLater(
      session.result,
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          'broken\nworkflow',
        ),
      ),
    );

    final handle = await onlySession(dir);
    expect(handle.session.id, session.id);
    final events = await eventsOf(handle);
    expect(events.map((e) => e.name), [
      'session-started',
      'effect-started',
      'effect-finished',
      'session-failed',
    ]);
    expect(
      events.last,
      isA<SessionFailed>()
          .having((e) => e.error, 'error', 'Bad state: broken workflow')
          .having((e) => e.stack, 'stack', namesThisFile),
    );
  });

  test('owns the session while it runs and lets it go when it ends', () async {
    final dir = await tempDir();
    gates['owner'] = Completer();

    final session = await Flow(directory: dir).startWorkflow(gated, 'owner');
    expect(sessionIds(dir), [session.id]);
    expect(await ownerCheck(dir, session.id), 'busy');

    gates['owner']!.complete('open');
    expect(await session.result, 'owner after open');
    expect(await ownerCheck(dir, session.id), 'opened');
  });

  group('the end of a session', () {
    test('waits for the effects the workflow did not await: their outcome is '
        'written before the session\'s', () async {
      final dir = await tempDir();
      gates['left'] = Completer();
      final session = await Flow(directory: dir)
          .startWorkflow(leavesEffect, 'left');
      var ended = false;
      unawaited(session.result.then((_) => ended = true));

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(ended, isFalse);
      expect(eventNamesOf(dir, session.id), [
        'session-started',
        'effect-started',
      ]);

      gates['left']!.complete('open');
      expect(await session.result, 'returned');
      final handle = await onlySession(dir);
      expect((await eventsOf(handle)).map((e) => e.name), [
        'session-started',
        'effect-started',
        'effect-finished',
        'session-finished',
      ]);
      final [background] = await handle.effects();
      expect(await handle.documentValue(background.outputId!), 'open');
    });

    test('lets no effect start after it', () async {
      final dir = await tempDir();

      expect(
        await Flow(directory: dir).runWorkflow(callsLate, 'late'),
        'returned',
      );

      expect(await lateEffects['late'], isStateError);
      final handle = await onlySession(dir);
      expect(await handle.effects(), isEmpty);
      expect((await eventsOf(handle)).map((e) => e.name), [
        'session-started',
        'session-finished',
      ]);
    });
  });

  test('two sessions of one flow at once keep their effects apart', () async {
    final dir = await tempDir();
    final flow = Flow(directory: dir);
    gates['a'] = Completer();
    gates['b'] = Completer();

    final a = await flow.startWorkflow(gated, 'a');
    final b = await flow.startWorkflow(gated, 'b');
    gates['b']!.complete('B');
    expect(await b.result, 'b after B');
    gates['a']!.complete('A');
    expect(await a.result, 'a after A');

    expect(a.id, isNot(b.id));
    for (final (session, who, opened) in [(a, 'a', 'A'), (b, 'b', 'B')]) {
      final handle = await openSession(dir, session.id);
      final effects = await handle.effects();
      expect([for (final s in effects) s.name], ['wait', 'echo']);
      expect(await handle.documentValue(effects[0].outputId!), opened);
      expect(
        await handle.documentValue(effects[1].outputId!),
        '$who after $opened',
      );
      final ids = {for (final s in effects) s.id};
      for (final event in await eventsOf(handle)) {
        if (event
            case EffectStarted(:final effectId) ||
                EffectFinished(:final effectId)) {
          expect(ids, contains(effectId));
        }
      }
    }
  });

  for (final (title, workflow, count) in [
    ('an effect awaited later through Future.wait', release, 6),
    ('a plain future awaited later', fetchLater, 5),
    ('items of a stream handled by copies', streamed, 9),
  ]) {
    group('the keys of effects with $title', () {
      test('are the same whatever the timing', () async {
        final dir = await tempDir();
        final flow = Flow(directory: dir);
        Map<String, String?>? expected;
        for (var seed = 1; seed <= 10; seed++) {
          random = Random(seed);
          final session = await flow.startWorkflow(workflow, '1.0');
          await session.result;
          final effects = await effectsOf(dir, session.id);
          final afters = {for (final s in effects) s.key: s.after};
          expect(afters, hasLength(count));
          expect(afters, expected ??= afters, reason: 'seed $seed');
        }
      });

      test('find the effects a session finished before, which then neither '
          'run nor are written again', () async {
        final dir = await tempDir();
        final flow = Flow(directory: dir);
        random = Random(1);
        final first = await flow.startWorkflow(workflow, '1.0');
        final expected = await first.result;
        final handle = await openSession(dir, first.id);
        // In the order the effects were created.
        final results = {
          for (final s in await handle.effects())
            s.key: (
              after: s.after,
              value: await handle.documentValue(s.outputId!),
            ),
        };
        final keys = results.keys.toList();
        for (var seed = 2; seed < 13; seed++) {
          random = Random(seed);
          final saved = seed == 2
              // The first effect alone; in release the effect awaited later,
              // which, saved, is done by the time Future.wait takes it.
              ? {keys.first}
              : (keys.toList()..shuffle(random))
                    .take(1 + random.nextInt(keys.length - 1))
                    .toSet();
          final again = await startWithSaved(flow, workflow, '1.0', {
            for (final key in saved) key: results[key]!,
          });
          expect(await again.result, expected, reason: 'seed $seed');
          expect(
            {for (final s in await effectsOf(dir, again.id)) s.key},
            keys.toSet().difference(saved),
            reason: 'seed $seed, saved $saved',
          );
        }
      });
    });
  }

  group('the store', () {
    test('a flow given one writes its sessions there, not to runs/ of the '
        'project, and resumes them from there', () async {
      final dir = await tempDir();
      final elsewhere = await tempDir();
      final store = FsStore(runsDirOf(elsewhere));

      final session = await Flow(
        directory: dir,
        store: store,
      ).startWorkflow(review, 'main');
      expect(await session.result, 'change of main: clean');

      expect(Directory(runsDirOf(dir)).existsSync(), isFalse);
      expect(sessionIds(elsewhere), [session.id]);
      final resumed = await Flow(
        directory: dir,
        store: store,
      ).resumeWorkflow(review, session.id);
      expect(await resumed.result, 'change of main: clean');
    });

    test('start takes the id it is given', () async {
      final dir = await tempDir();
      final id = newId();

      final session = await Flow(directory: dir)
          .startWorkflow(review, 'main', id: id);

      expect(session.id, id);
      expect(await session.result, 'change of main: clean');
      expect(sessionIds(dir), [id]);
    });

    test('start with the id of a session there is fails with '
        'SessionExistsException, and writes nothing', () async {
      final dir = await tempDir();
      final flow = Flow(directory: dir);
      final first = await flow.startWorkflow(review, 'main');
      await first.result;
      final before = filesUnder(runsDirOf(dir));

      await expectLater(
        flow.startWorkflow(review, 'main', id: first.id),
        throwsA(
          isA<SessionExistsException>().having(
            (e) => e.sessionId,
            'sessionId',
            first.id,
          ),
        ),
      );
      expect(filesUnder(runsDirOf(dir)), before);
    });

    test('start with an id that is not a lowercase UUID is an ArgumentError, '
        'and writes nothing', () async {
      final dir = await tempDir();

      await expectLater(
        Flow(directory: dir)
            .startWorkflow(review, 'main', id: newId().toUpperCase()),
        throwsArgumentError,
      );
      expect(Directory(runsDirOf(dir)).existsSync(), isFalse);
    });
  });

  group('f.effect', () {
    test('outside a session is a StateError', () async {
      final flow = Flow(directory: await tempDir());
      expect(() => flow.effect('collect', () => 'x'), throwsStateError);
    });

    test('of another flow inside a session is a StateError', () async {
      final dir = await tempDir();
      otherFlow = Flow(directory: dir);
      await expectLater(
        Flow(directory: dir).runWorkflow(otherFlowEffect, 'x'),
        throwsStateError,
      );
    });
  });

  group('a value that is not JSON', () {
    test('as the input fails start, and no session is written', () async {
      final dir = await tempDir();
      await expectLater(
        Flow(directory: dir)
            .startWorkflow(describeDate, DateTime.utc(2026, 10, 3)),
        throwsA(isA<CodecException>().having((e) => e.type, 'type', DateTime)),
      );
      expect(Directory(p.join(dir, 'runs')).existsSync(), isFalse);
    });

    test(
      'as an effect result fails the effect with a CodecException',
      () async {
        final dir = await tempDir();
        expect(
          await Flow(directory: dir).runWorkflow(datedEffect, 'x'),
          startsWith('failed: CodecException: DateTime'),
        );
        final handle = await onlySession(dir);
        final events = await eventsOf(handle);
        expect(
          events[2],
          isA<EffectFailed>().having(
            (e) => e.error,
            'error',
            startsWith('CodecException: DateTime'),
          ),
        );
        expect(events.last, isA<SessionFinished>());
      },
    );

    test('as the result fails the session with a CodecException', () async {
      final dir = await tempDir();
      await expectLater(
        Flow(directory: dir).runWorkflow(datedResult, 'x'),
        throwsA(isA<CodecException>().having((e) => e.type, 'type', DateTime)),
      );
      final events = await eventsOf(await onlySession(dir));
      expect(
        events.last,
        isA<SessionFailed>().having(
          (e) => e.error,
          'error',
          startsWith('CodecException: DateTime'),
        ),
      );
    });
  });
}
