import 'dart:async';
import 'dart:io';

import 'package:nanoflow/nanoflow.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_store/nanoflow_store.dart'
    show FsStore, StoreCorruptedException;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support.dart';

/// What each session waits for, by its input.
final gates = <String, Completer<String>>{};

/// Completed when the session of each input begins to wait for its gate.
final waiting = <String, Completer<void>>{};

/// What the steps of each session threw at its workflow, by its input.
final caught = <String, List<Object>>{};

/// The bodies of the steps that ran, as `<input>:<step>`.
final ran = <String>[];

/// Gives the session of [who] a gate to wait for.
void prepare(String who) {
  gates[who] = Completer();
  waiting[who] = Completer();
  caught[who] = [];
}

/// The bodies of the steps of the session of [who] that ran, in order.
List<String> ranIn(String who) => [
  for (final step in ran)
    if (step.startsWith('$who:')) step.substring(who.length + 1),
];

String body(String who, String step) {
  ran.add('$who:$step');
  return step;
}

/// Waits for its gate in its step `wait`, then calls its step `echo`; keeps
/// what each throws.
Future<String> waitInStep(Flow f, String who) async {
  await f.step('first', () => body(who, 'first'));
  try {
    await f.step('wait', () {
      body(who, 'wait');
      waiting[who]!.complete();
      return gates[who]!.future;
    });
  } on Exception catch (e) {
    caught[who]!.add(e);
  }
  try {
    return await f.step('echo', () => body(who, 'echo'));
  } on Exception catch (e) {
    caught[who]!.add(e);
    rethrow;
  }
}

/// Waits for its gate between its steps `first` and `second`.
Future<String> waitBetween(Flow f, String who) async {
  await f.step('first', () => body(who, 'first'));
  waiting[who]!.complete();
  await gates[who]!.future;
  return f.step('second', () => body(who, 'second'));
}

void main() {
  group('a session whose directory is removed', () {
    test('while a step runs fails that step and every step after it with a '
        'StorageException, which is its result; nothing is written '
        'again', () async {
      final dir = await tempDir();
      prepare('in step');
      final session = await Flow(directory: dir).start(waitInStep, 'in step');
      await waiting['in step']!.future;

      Directory(sessionDirOf(dir, session.id)).deleteSync(recursive: true);
      gates['in step']!.complete('open');

      await expectLater(session.result, throwsA(isA<StorageException>()));
      expect(caught['in step'], [
        isA<StorageException>().having(
          (e) => e.cause,
          'cause',
          isA<FileSystemException>(),
        ),
        isA<StorageException>(),
      ]);
      expect(ranIn('in step'), ['first', 'wait']);
      expect(Directory(runsDirOf(dir)).listSync(), isEmpty);
    });

    test('between steps fails the next step with a StorageException, which '
        'is its result; nothing is written again', () async {
      final dir = await tempDir();
      prepare('between');
      final session = await Flow(directory: dir).start(waitBetween, 'between');
      await waiting['between']!.future;

      Directory(sessionDirOf(dir, session.id)).deleteSync(recursive: true);
      gates['between']!.complete('open');

      await expectLater(
        session.result,
        throwsA(
          isA<StorageException>().having(
            (e) => e.cause,
            'cause',
            isA<FileSystemException>(),
          ),
        ),
      );
      expect(ranIn('between'), ['first']);
      expect(Directory(runsDirOf(dir)).listSync(), isEmpty);
    });
  });

  test('a session whose write failed is not written again, even where a '
      'write would succeed', () async {
    final dir = await tempDir();
    prepare('documents');
    final session = await Flow(directory: dir).start(waitInStep, 'documents');
    await waiting['documents']!.future;
    final sessionDir = sessionDirOf(dir, session.id);

    Directory(p.join(sessionDir, documentsDirName)).deleteSync(recursive: true);
    final files = filesUnder(sessionDir);
    gates['documents']!.complete('open');

    await expectLater(session.result, throwsA(isA<StorageException>()));
    expect(caught['documents'], [
      isA<StorageException>(),
      isA<StorageException>(),
    ]);
    expect(ranIn('documents'), ['first', 'wait']);
    expect(filesUnder(sessionDir), files);
  });

  test('a session that cannot be created is a StorageException', () async {
    final dir = await tempDir();
    File(runsDirOf(dir)).writeAsStringSync('not a directory');

    await expectLater(
      Flow(directory: dir).start(waitBetween, 'x'),
      throwsA(
        isA<StorageException>().having(
          (e) => e.cause,
          'cause',
          isA<FileSystemException>(),
        ),
      ),
    );
  });

  test('a session whose journal cannot be read is not resumed: a '
      'StorageException', () async {
    final dir = await tempDir();
    final handle = await FsStore(runsDirOf(dir)).createSession(
      workflow: 'waitBetween',
      graph: null,
      input: (value: 'x'),
      code: null,
    );
    await handle.release();
    File(p.join(handle.dir, eventsFileName))
        .writeAsStringSync('not json\n', mode: FileMode.append);
    final files = filesUnder(handle.dir);

    await expectLater(
      Flow(directory: dir).resume(waitBetween, handle.session.id),
      throwsA(
        isA<StorageException>().having(
          (e) => e.cause,
          'cause',
          isA<StoreCorruptedException>(),
        ),
      ),
    );
    expect(filesUnder(handle.dir), files);
  });

  group('stop', () {
    test('fails the step that runs and every step after it with a '
        'FlowStoppedException, which is the result; nothing more is written, '
        'and the session can be resumed', () async {
      final dir = await tempDir();
      final flow = Flow(directory: dir);
      prepare('stopped');
      final session = await flow.start(waitInStep, 'stopped');
      await waiting['stopped']!.future;
      final sessionDir = sessionDirOf(dir, session.id);
      final files = filesUnder(sessionDir);

      flow.stop();
      gates['stopped']!.complete('open');

      await expectLater(session.result, throwsA(isA<FlowStoppedException>()));
      expect(caught['stopped'], [
        isA<FlowStoppedException>(),
        isA<FlowStoppedException>(),
      ]);
      expect(ranIn('stopped'), ['first', 'wait']);
      expect(filesUnder(sessionDir), files);
      expect(await ownerCheck(dir, session.id), 'opened');

      waiting['stopped'] = Completer();
      final again = await Flow(directory: dir).resume(waitInStep, session.id);
      expect(await again.result, 'echo');
      expect(ranIn('stopped'), ['first', 'wait', 'wait', 'echo']);
      final handle = await openSession(dir, session.id);
      final state = replaySession(await eventsOf(handle));
      expect(state.status, SessionStatus.finished);
      expect([for (final s in state.steps) s.starts], [1, 2, 1]);
    });

    test('lets no session start or resume', () async {
      final dir = await tempDir();
      final flow = Flow(directory: dir)..stop();

      await expectLater(
        flow.start(waitBetween, 'x'),
        throwsA(isA<FlowStoppedException>()),
      );
      expect(Directory(runsDirOf(dir)).existsSync(), isFalse);

      final handle = await FsStore(runsDirOf(dir)).createSession(
        workflow: 'waitBetween',
        graph: null,
        input: (value: 'x'),
        code: null,
      );
      await handle.release();
      final files = filesUnder(handle.dir);
      await expectLater(
        flow.resume(waitBetween, handle.session.id),
        throwsA(isA<FlowStoppedException>()),
      );
      expect(filesUnder(handle.dir), files);
    });
  });
}
