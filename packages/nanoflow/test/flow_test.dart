import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:nanoflow/nanoflow.dart';
import 'package:nanoflow/src/flow.dart' show startWithSaved;
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support.dart';

Future<String> review(Flow f, String branch) async {
  final change = await f.step('collect', () => 'change of $branch'); // collect
  return f.step('inspect', () async => '$change: clean'); // inspect
}

Future<String> flaky(Flow f, String target) async {
  try {
    await f.step<String>('deploy', () => throw StateError('no\r\ndisk'));
  } on StateError catch (e) {
    return f.step('rollback', () => 'rolled back $target: ${e.message}');
  }
  return 'deployed';
}

Future<String> broken(Flow f, String branch) async {
  await f.step('collect', () => 'change of $branch');
  throw StateError('broken\nworkflow');
}

/// What each [gated] session waits for, by its input.
final gates = <String, Completer<String>>{};

Future<String> gated(Flow f, String who) async {
  final opened = await f.step('wait', () => gates[who]!.future);
  return f.step('echo', () => '$who after $opened');
}

Future<String> describeDate(Flow f, DateTime date) async => '$date';

Future<String> datedStep(Flow f, String x) async {
  try {
    await f.step('date', () => DateTime.utc(2026, 10, 3));
  } on CodecException catch (e) {
    return 'failed: $e';
  }
  return 'dated';
}

Future<DateTime> datedResult(Flow f, String x) async =>
    DateTime.utc(2026, 10, 3);

/// A step awaited later through Future.wait, then copies whose first await is
/// not a step, with random pauses.
Future<String> release(Flow f, String version) async {
  final pending = f.step('download', () => work('src-$version'));
  await pause();
  await pause();
  final [source] = await Future.wait([pending]);
  final results = await Future.wait([
    for (final pkg in ['core', 'tool'])
      () async {
        await pause(); // like http.get outside any step
        final up = await f.step('upload', () => work('$pkg:$source'));
        return f.step('verify', () => work('$up:verified'));
      }(),
  ]);
  return f.step('announce', () => work(results.join(' | ')));
}

/// A plain future started early, like an http.get, awaited later — done by
/// then or not — then copies whose first await is not a step, with random
/// pauses.
Future<String> fetchLater(Flow f, String version) async {
  final pending = work('src-$version');
  await pause();
  await pause();
  final source = await pending;
  final results = await Future.wait([
    for (final pkg in ['core', 'tool'])
      () async {
        await pause(); // like http.get outside any step
        final up = await f.step('upload', () => work('$pkg:$source'));
        return f.step('verify', () => work('$up:verified'));
      }(),
  ]);
  return f.step('announce', () => work(results.join(' | ')));
}

/// The step records of the session [sessionId] of [dir].
Future<List<Step>> stepsOf(String dir, String sessionId) async =>
    (await openSession(dir, sessionId)).steps();

/// A flow other than the one that runs [otherFlowStep].
late Flow otherFlow;

Future<String> otherFlowStep(Flow f, String x) async =>
    otherFlow.step('collect', () => x);

/// A stack trace's text that names this file.
final namesThisFile = contains('flow_test.dart');

void main() {
  group('run', () {
    test('writes one session: the input, a record and events for every step '
        'and the result', () async {
      final dir = await tempDir();
      final flow = Flow(directory: dir);
      expect(flow.directory, dir);

      expect(await flow.run(review, 'main'), 'change of main: clean');

      final handle = await onlySession(dir);
      final session = handle.session;
      expect(session.workflow, 'review');
      expect(session.graph, isNull);
      expect(await handle.documentValue(session.inputId!), 'main');
      expect(p.basename(handle.dir), startsWith('review-'));

      final steps = await handle.steps();
      expect([for (final s in steps) s.name], ['collect', 'inspect']);
      final [collect, inspect] = steps;
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
        'step-started',
        'step-finished',
        'step-started',
        'step-finished',
        'session-finished',
      ]);
      expect(
        events[1],
        isA<StepStarted>().having((e) => e.stepId, 'stepId', collect.id),
      );
      expect(
        events[2],
        isA<StepFinished>()
            .having((e) => e.stepId, 'stepId', collect.id)
            .having((e) => e.outputId, 'outputId', collect.outputId),
      );
      expect(
        events[3],
        isA<StepStarted>().having((e) => e.stepId, 'stepId', inspect.id),
      );
      expect(
        events[4],
        isA<StepFinished>()
            .having((e) => e.stepId, 'stepId', inspect.id)
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
      const graph = {'format': 1, 'package': 'review_example'};
      File(p.join(dir, 'nanoflow.graph.json'))
          .writeAsStringSync(jsonEncode(graph));

      await Flow(directory: dir).run(review, 'main');

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

  test('a step that throws fails, and its exception reaches the '
      'workflow', () async {
    final dir = await tempDir();

    expect(
      await Flow(directory: dir).run(flaky, 'prod'),
      'rolled back prod: no\r\ndisk',
    );

    final handle = await onlySession(dir);
    final [deploy, rollback] = await handle.steps();
    expect(deploy.name, 'deploy');
    expect(deploy.outputId, isNull);
    final events = await eventsOf(handle);
    expect(events.map((e) => e.name), [
      'session-started',
      'step-started',
      'step-failed',
      'step-started',
      'step-finished',
      'session-finished',
    ]);
    expect(
      events[2],
      isA<StepFailed>()
          .having((e) => e.stepId, 'stepId', deploy.id)
          .having((e) => e.error, 'error', 'Bad state: no disk')
          .having((e) => e.stack, 'stack', namesThisFile),
    );
    // An exception is not a result: the code that caught it took no step's.
    expect(rollback.after, isNull);
  });

  test('a workflow that throws fails the session, and its result is the '
      'exception', () async {
    final dir = await tempDir();

    final session = await Flow(directory: dir).start(broken, 'main');
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
      'step-started',
      'step-finished',
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

    final session = await Flow(directory: dir).start(gated, 'owner');
    expect(sessionIds(dir), [session.id]);
    expect(await ownerCheck(dir, session.id), 'busy');

    gates['owner']!.complete('open');
    expect(await session.result, 'owner after open');
    expect(await ownerCheck(dir, session.id), 'opened');
  });

  test('two sessions of one flow at once keep their steps apart', () async {
    final dir = await tempDir();
    final flow = Flow(directory: dir);
    gates['a'] = Completer();
    gates['b'] = Completer();

    final a = await flow.start(gated, 'a');
    final b = await flow.start(gated, 'b');
    gates['b']!.complete('B');
    expect(await b.result, 'b after B');
    gates['a']!.complete('A');
    expect(await a.result, 'a after A');

    expect(a.id, isNot(b.id));
    for (final (session, who, opened) in [(a, 'a', 'A'), (b, 'b', 'B')]) {
      final handle = await openSession(dir, session.id);
      final steps = await handle.steps();
      expect([for (final s in steps) s.name], ['wait', 'echo']);
      expect(await handle.documentValue(steps[0].outputId!), opened);
      expect(
        await handle.documentValue(steps[1].outputId!),
        '$who after $opened',
      );
      final ids = {for (final s in steps) s.id};
      for (final event in await eventsOf(handle)) {
        if (event
            case StepStarted(:final stepId) || StepFinished(:final stepId)) {
          expect(ids, contains(stepId));
        }
      }
    }
  });

  for (final (title, workflow, count) in [
    ('a step awaited later through Future.wait', release, 6),
    ('a plain future awaited later', fetchLater, 5),
  ]) {
    group('the keys of steps after $title', () {
      test('are the same whatever the timing', () async {
        final dir = await tempDir();
        final flow = Flow(directory: dir);
        Map<String, String?>? expected;
        for (var seed = 1; seed <= 10; seed++) {
          random = Random(seed);
          final session = await flow.start(workflow, '1.0');
          await session.result;
          final steps = await stepsOf(dir, session.id);
          final afters = {for (final s in steps) s.key: s.after};
          expect(afters, hasLength(count));
          expect(afters, expected ??= afters, reason: 'seed $seed');
        }
      });

      test('find the steps a session finished before, which then neither '
          'run nor are written again', () async {
        final dir = await tempDir();
        final flow = Flow(directory: dir);
        random = Random(1);
        final first = await flow.start(workflow, '1.0');
        final expected = await first.result;
        final handle = await openSession(dir, first.id);
        // In the order the steps were created.
        final results = {
          for (final s in await handle.steps())
            s.key: await handle.documentValue(s.outputId!),
        };
        final keys = results.keys.toList();
        for (var seed = 2; seed < 13; seed++) {
          random = Random(seed);
          final saved = seed == 2
              // The first step alone; in release the step awaited later,
              // which, saved, is done by the time Future.wait takes it.
              ? {keys.first}
              : (keys.toList()..shuffle(random))
                    .take(1 + random.nextInt(keys.length - 1))
                    .toSet();
          final again = await startWithSaved(flow, workflow, '1.0', {
            for (final key in saved) key: results[key],
          });
          expect(await again.result, expected, reason: 'seed $seed');
          expect(
            {for (final s in await stepsOf(dir, again.id)) s.key},
            keys.toSet().difference(saved),
            reason: 'seed $seed, saved $saved',
          );
        }
      });
    });
  }

  group('f.step', () {
    test('outside a session is a StateError', () async {
      final flow = Flow(directory: await tempDir());
      expect(() => flow.step('collect', () => 'x'), throwsStateError);
    });

    test('of another flow inside a session is a StateError', () async {
      final dir = await tempDir();
      otherFlow = Flow(directory: dir);
      await expectLater(
        Flow(directory: dir).run(otherFlowStep, 'x'),
        throwsStateError,
      );
    });
  });

  group('a value that is not JSON', () {
    test('as the input fails start, and no session is written', () async {
      final dir = await tempDir();
      await expectLater(
        Flow(directory: dir).start(describeDate, DateTime.utc(2026, 10, 3)),
        throwsA(isA<CodecException>().having((e) => e.type, 'type', DateTime)),
      );
      expect(Directory(p.join(dir, 'runs')).existsSync(), isFalse);
    });

    test('as a step result fails the step with a CodecException', () async {
      final dir = await tempDir();
      expect(
        await Flow(directory: dir).run(datedStep, 'x'),
        startsWith('failed: CodecException: DateTime'),
      );
      final handle = await onlySession(dir);
      final events = await eventsOf(handle);
      expect(
        events[2],
        isA<StepFailed>().having(
          (e) => e.error,
          'error',
          startsWith('CodecException: DateTime'),
        ),
      );
      expect(events.last, isA<SessionFinished>());
    });

    test('as the result fails the session with a CodecException', () async {
      final dir = await tempDir();
      await expectLater(
        Flow(directory: dir).run(datedResult, 'x'),
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
