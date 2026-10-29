import 'dart:convert';
import 'dart:io';

import 'package:nanoflow/nanoflow.dart';
import 'package:nanoflow/src/flow.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_store/nanoflow_store.dart' show FsStore, FsSession;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'fixtures/review.dart';
import 'support.dart';

/// test/fixtures/run_review.dart, compiled once for the tests of this file.
late String runReview;

/// A workflow other than [review], whose session fails.
Future<String> failing(Flow f, String work) async {
  await f.effect('collect', () => 'change');
  throw StateError('no\nway');
}

/// The keys of the effects of [review].
final collectKey = 'collect#1@${h('')}';
final inspectKey = 'inspect#1@${h(collectKey)}';
final publishKey = 'publish#1@${h(inspectKey)}';

/// A project directory to run [review] in, and a directory for its work.
Future<({String dir, String work})> project() async =>
    (dir: await tempDir(), work: await tempDir());

/// How many times the body of the effect [name] of [review] ran with [work].
int runsOf(String work, String name) {
  final file = File(p.join(work, name));
  return file.existsSync() ? file.lengthSync() : 0;
}

/// Starts run_review.dart, which runs a session of [review] in [dir] with
/// [work], and waits until its effect `inspect` runs; it is killed after the
/// test.
Future<({Process process, String sessionId})> startUntilInspect(
  String dir,
  String work,
) async {
  final process = await Process.start(Platform.resolvedExecutable, [
    runReview,
    dir,
    work,
  ]);
  addTearDown(() => process.kill(ProcessSignal.sigkill));
  final errors = StringBuffer();
  process.stderr.transform(utf8.decoder).listen(errors.write);
  int? exitCode;
  process.exitCode.then((code) => exitCode = code).ignore();
  final lines = process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter());
  final sessionId = await lines.first.catchError(
    (Object _) => fail('run_review printed no id: $errors'),
  );
  await until(
    () => runsOf(work, 'inspect') == 1 || exitCode != null,
    'the effect inspect of run_review',
  );
  expect(exitCode, isNull, reason: '$errors');
  return (process: process, sessionId: sessionId);
}

/// Kills [process] as a crash would and waits until it is gone.
Future<void> kill(Process process) async {
  process.kill(ProcessSignal.sigkill);
  await process.exitCode;
}

/// Writes a session of [review] with [work] in [dir], as a process that
/// died would have left it, with the hash of its code [code]; [build] adds
/// to it. Gives its id.
Future<String> writeSession(
  String dir,
  String work, {
  String? code,
  Future<void> Function(FsSession handle)? build,
}) async {
  final handle = await FsStore(runsDirOf(dir)).createSession(
    workflow: 'review',
    graph: null,
    input: (value: work),
    code: code,
  );
  await build?.call(handle);
  await handle.release();
  return handle.session.id;
}

/// Writes the effect `collect` of [review] to the session of [handle],
/// finished with [value], as following [after]; leaves its `outputId` out of
/// `effect.json` unless [outputInEffectJson].
Future<Effect> writeCollect(
  FsSession handle, {
  required String? after,
  required Object? value,
  bool outputInEffectJson = true,
}) async {
  final effect = await handle.createEffect(
    name: 'collect',
    key: collectKey,
    after: after,
    place: null,
  );
  await handle.appendEvent(
    EffectStarted(time: systemClock(), effectId: effect.id),
  );
  final outputId = await handle.writeDocument(value);
  await handle.appendEvent(
    EffectFinished(
      time: systemClock(),
      effectId: effect.id,
      outputId: outputId,
    ),
  );
  if (outputInEffectJson) await handle.setEffectOutput(effect, outputId);
  return effect;
}

void main() {
  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('nanoflow_fixture');
    addTearDown(() => dir.delete(recursive: true));
    runReview = p.join(dir.path, 'run_review.dill');
    // A snapshot of the VM, as `dart run` makes: what `dart compile kernel`
    // makes is a product build, which the library takes for a compiled
    // program, with the hash of its executable for the code.
    final compiled = await Process.run(Platform.resolvedExecutable, [
      '--snapshot-kind=kernel',
      '--snapshot=$runReview',
      p.join('test', 'fixtures', 'run_review.dart'),
    ]);
    expect(
      compiled.exitCode,
      0,
      reason: '${compiled.stdout}${compiled.stderr}',
    );
  });

  group('a session whose process was killed in its second effect', () {
    test('cannot be resumed while that process owns it', () async {
      final (:dir, :work) = await project();
      final running = await startUntilInspect(dir, work);

      await expectLater(
        Flow(directory: dir).resumeWorkflow(review, running.sessionId),
        throwsA(
          isA<SessionBusyException>().having(
            (e) => e.sessionId,
            'sessionId',
            running.sessionId,
          ),
        ),
      );
    });

    test('goes on where it was: the effect that finished is taken from the '
        'journal, the one that ran runs again in its record', () async {
      final (:dir, :work) = await project();
      final running = await startUntilInspect(dir, work);
      await kill(running.process);
      File(p.join(work, 'go')).createSync();

      final session = await Flow(directory: dir)
          .resumeWorkflow(review, running.sessionId);
      expect(session.id, running.sessionId);
      expect(await session.result, 'published change: clean');
      expect(
        [
          for (final name in ['collect', 'inspect', 'publish'])
            runsOf(work, name),
        ],
        [1, 2, 1],
      );

      final handle = await openSession(dir, running.sessionId);
      final effects = await handle.effects();
      expect(
        [for (final s in effects) s.key],
        [collectKey, inspectKey, publishKey],
      );
      final events = await eventsOf(handle);
      expect(events.map((e) => e.name), [
        'session-started',
        'effect-started',
        'effect-finished',
        'effect-started',
        'session-resumed',
        'effect-started',
        'effect-finished',
        'effect-started',
        'effect-finished',
        'session-finished',
      ]);
      final state = replaySession(events);
      expect(state.status, SessionStatus.finished);
      expect(
        [for (final s in state.effects) (s.effectId, s.starts)],
        [
          for (final (s, starts) in [
            (effects[0], 1),
            (effects[1], 2),
            (effects[2], 1),
          ])
            (s.id, starts),
        ],
      );
      final started = events.whereType<SessionStarted>().single;
      final resumed = events.whereType<SessionResumed>().single;
      expect(resumed.code, started.code);
      expect(resumed.graphId, isNull);
      expect(
        await handle.documentValue(state.outputId!),
        'published change: clean',
      );
    });

    test('is the only unfinished session of its workflow', () async {
      final (:dir, :work) = await project();
      final finished = await tempDir();
      File(p.join(finished, 'go')).createSync();
      await Flow(directory: dir).runWorkflow(review, finished);
      final other = await FsStore(runsDirOf(dir)).createSession(
        workflow: 'failing',
        graph: null,
        input: (value: work),
        code: null,
      );
      await other.release();
      final running = await startUntilInspect(dir, work);
      await kill(running.process);

      expect(await Flow(directory: dir).unfinishedOf(review), [
        running.sessionId,
      ]);
    });
  });

  group('resume', () {
    test('of a finished session gives its result, and neither runs nor '
        'writes anything', () async {
      final (:dir, :work) = await project();
      File(p.join(work, 'go')).createSync();
      final first = await Flow(directory: dir).startWorkflow(review, work);
      await first.result;
      final files = filesUnder(sessionDirOf(dir, first.id));

      final session = await Flow(directory: dir)
          .resumeWorkflow(review, first.id);

      expect(session.id, first.id);
      expect(await session.result, 'published change: clean');
      expect(
        [
          for (final name in ['collect', 'inspect', 'publish'])
            runsOf(work, name),
        ],
        [1, 1, 1],
      );
      expect(filesUnder(sessionDirOf(dir, first.id)), files);
      expect(await ownerCheck(dir, first.id), 'opened');
    });

    test('of a session this process runs is a SessionBusyException, and the '
        'session stays owned', () async {
      final (:dir, :work) = await project();
      final flow = Flow(directory: dir);
      final running = await flow.startWorkflow(review, work);
      await until(() => runsOf(work, 'inspect') == 1, 'the effect inspect');

      for (final resume in [
        () => Flow(directory: dir).resumeWorkflow(failing, running.id),
        () => flow.resumeWorkflow(review, running.id),
      ]) {
        await expectLater(
          resume(),
          throwsA(
            isA<SessionBusyException>().having(
              (e) => e.sessionId,
              'sessionId',
              running.id,
            ),
          ),
        );
        expect(await ownerCheck(dir, running.id), 'busy');
      }

      File(p.join(work, 'go')).createSync();
      expect(await running.result, 'published change: clean');
      expect(
        [
          for (final name in ['collect', 'inspect', 'publish'])
            runsOf(work, name),
        ],
        [1, 1, 1],
      );
      expect(await ownerCheck(dir, running.id), 'opened');
    });

    test('of a failed session gives its error', () async {
      final (:dir, :work) = await project();
      final first = await Flow(directory: dir).startWorkflow(failing, work);
      await expectLater(first.result, throwsStateError);
      final files = filesUnder(sessionDirOf(dir, first.id));

      final session = await Flow(directory: dir)
          .resumeWorkflow(failing, first.id);

      Object? error;
      StackTrace? stack;
      try {
        await session.result;
      } catch (e, s) {
        error = e;
        stack = s;
      }
      expect(
        error,
        isA<SessionFailedException>()
            .having((e) => e.sessionId, 'sessionId', first.id)
            .having((e) => e.error, 'error', 'Bad state: no way'),
      );
      expect(filesUnder(sessionDirOf(dir, first.id)), files);
      expect(await ownerCheck(dir, first.id), 'opened');
      final failed = (await eventsOf(await openSession(dir, first.id))).last;
      expect('$stack', (failed as SessionFailed).stack);
    });

    test('of a session that is not there is a '
        'SessionNotFoundException', () async {
      final id = newId();
      await expectLater(
        Flow(directory: await tempDir()).resumeWorkflow(review, id),
        throwsA(
          isA<SessionNotFoundException>().having(
            (e) => e.sessionId,
            'sessionId',
            id,
          ),
        ),
      );
    });

    test('with another workflow is a WorkflowMismatchException, and changes '
        'nothing', () async {
      final (:dir, :work) = await project();
      final id = await writeSession(dir, work);
      final files = filesUnder(sessionDirOf(dir, id));

      await expectLater(
        Flow(directory: dir).resumeWorkflow(failing, id),
        throwsA(
          isA<WorkflowMismatchException>()
              .having((e) => e.sessionId, 'sessionId', id)
              .having((e) => e.expected, 'expected', 'review')
              .having((e) => e.actual, 'actual', 'failing'),
        ),
      );
      expect(filesUnder(sessionDirOf(dir, id)), files);
      expect(await ownerCheck(dir, id), 'opened');
    });

    test('on other code writes the graph file as it is now, and '
        'session-resumed names it', () async {
      final (:dir, :work) = await project();
      File(p.join(work, 'go')).createSync();
      final id = await writeSession(dir, work, code: 'sha256:old');
      const graph = {'format': 2, 'package': 'review_fixture'};
      File(p.join(dir, 'nanoflow.graph.json'))
          .writeAsStringSync(jsonEncode(graph));
      File(p.join(dir, 'lib', 'review.dart'))
        ..parent.createSync()
        ..writeAsStringSync('// review\n');

      await (await Flow(directory: dir).resumeWorkflow(review, id)).result;

      final handle = await openSession(dir, id);
      final resumed = (await eventsOf(handle))
          .whereType<SessionResumed>()
          .single;
      expect(
        resumed.code,
        fingerprintOf({
          'lib/review.dart': sourceHash(utf8.encode('// review\n')),
        }),
      );
      expect(await handle.documentValue(resumed.graphId!), graph);
      expect(handle.session.graph, isNull);
    });

    test('on other code without a graph file writes no snapshot, and '
        'session-resumed names none', () async {
      final (:dir, :work) = await project();
      File(p.join(work, 'go')).createSync();
      final id = await writeSession(dir, work, code: 'sha256:old');

      await (await Flow(directory: dir).resumeWorkflow(review, id)).result;

      final handle = await openSession(dir, id);
      final events = await eventsOf(handle);
      final resumed = events.whereType<SessionResumed>().single;
      expect(resumed.code, isNot('sha256:old'));
      expect(resumed.graphId, isNull);
      // The input, the output of each effect and the result.
      final documents = Directory(p.join(handle.dir, documentsDirName));
      expect(documents.listSync(), hasLength(5));
    });

    test('takes a finished effect from the journal only when it follows the '
        'effect it followed then; otherwise the effect runs again in its '
        'record', () async {
      final (:dir, :work) = await project();
      File(p.join(work, 'go')).createSync();
      late Effect collect;
      final id = await writeSession(
        dir,
        work,
        build: (handle) async => collect = await writeCollect(
          handle,
          after: 'elsewhere#1@${h('')}',
          value: 'stale',
        ),
      );

      final session = await Flow(directory: dir).resumeWorkflow(review, id);

      expect(await session.result, 'published change: clean');
      expect(runsOf(work, 'collect'), 1);
      final handle = await openSession(dir, id);
      final effects = await handle.effects();
      expect(
        [for (final s in effects) s.key],
        [collectKey, inspectKey, publishKey],
      );
      expect(effects.first.id, collect.id);
      // A result it is given from now on is for a call that follows what
      // this one followed.
      expect(effects.first.after, isNull);
      expect(await handle.documentValue(effects.first.outputId!), 'change');
      final state = replaySession(await eventsOf(handle));
      expect(state.effects.first.effectId, collect.id);
      expect(state.effects.first.starts, 2);
    });

    test('writes to effect.json the outputId of an effect whose '
        'effect-finished was written when effect.json was not', () async {
      final (:dir, :work) = await project();
      File(p.join(work, 'go')).createSync();
      late Effect collect;
      final id = await writeSession(
        dir,
        work,
        build: (handle) async => collect = await writeCollect(
          handle,
          after: null,
          value: 'saved change',
          outputInEffectJson: false,
        ),
      );

      final session = await Flow(directory: dir).resumeWorkflow(review, id);

      expect(await session.result, 'published saved change: clean');
      expect(runsOf(work, 'collect'), 0);
      final handle = await openSession(dir, id);
      final finished = (await eventsOf(handle)).whereType<EffectFinished>();
      expect(finished.first.effectId, collect.id);
      expect(
        (await handle.effects()).first,
        collect.withOutput(finished.first.outputId!),
      );
    });
  });
}
