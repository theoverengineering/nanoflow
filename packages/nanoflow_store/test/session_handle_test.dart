import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_store/nanoflow_store.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support.dart';

// newSession() reads the ticking clock once: the session is created at
// 10:00:00.482. The next reading is 10:00:01.482.

void main() {
  group('createStep', () {
    test('writes steps/<time>-<name>-<id>/step.json and no event', () async {
      final handle = await newSession();
      final events = await handle.events();

      final step = await handle.createStep(
        name: 'collect',
        key: 'collect#1@e3b0c44298fc1c14',
        after: 'inspect#1@9f2c1a7b3d5e8f04',
        place: 'lib/review.dart:12',
      );

      expect(isId(step.id), isTrue);
      expect(
        step,
        Step(
          id: step.id,
          sessionId: handle.session.id,
          name: 'collect',
          key: 'collect#1@e3b0c44298fc1c14',
          after: 'inspect#1@9f2c1a7b3d5e8f04',
          place: 'lib/review.dart:12',
          outputId: null,
          log: 'step.log',
        ),
      );
      final dir = only(
        p.join(handle.dir, 'steps'),
        '2026-10-03T10-00-01-482-collect-$anId',
      );
      expect(dir.id, step.id);
      expect(names(dir.path), ['step.json']);
      expect(read(p.join(dir.path, 'step.json')), '''
{
  "id": "${step.id}",
  "sessionId": "${handle.session.id}",
  "name": "collect",
  "key": "collect#1@e3b0c44298fc1c14",
  "after": "inspect#1@9f2c1a7b3d5e8f04",
  "place": "lib/review.dart:12",
  "outputId": null,
  "log": "step.log"
}
''');
      expect(await handle.steps(), [step]);
      expect(await handle.events(), events);
      expect(dotEntries(handle.dir), isEmpty);
    });

    test('writes null after and place', () async {
      final handle = await newSession();

      final step = await handle.createStep(
        name: 'collect',
        key: 'collect#1@e3b0c44298fc1c14',
        after: null,
        place: null,
      );

      expect(step.after, isNull);
      expect(step.place, isNull);
      expect(await handle.steps(), [step]);
    });

    test('makes the name safe in the directory name only', () async {
      final handle = await newSession();

      final step = await newStep(handle, name: 'check a/b');

      only(
        p.join(handle.dir, 'steps'),
        '2026-10-03T10-00-01-482-check_a_b-(${step.id})',
      );
      expect((await handle.steps()).single.name, 'check a/b');
    });

    test('steps lists the steps in the order they were created', () async {
      final handle = await newSession();

      final collect = await newStep(handle, name: 'collect');
      final verdict = await newStep(handle, name: 'verdict');
      final fix = await newStep(handle, name: 'fix');

      expect(await handle.steps(), [collect, verdict, fix]);
    });

    test('names the steps in the order they were created, even within one '
        'millisecond', () async {
      final handle = await newSession(clock: () => start);

      final collect = await newStep(handle, name: 'collect');
      final verdict = await newStep(handle, name: 'verdict');
      final fix = await newStep(handle, name: 'fix');

      final steps = p.join(handle.dir, 'steps');
      expect(
        only(steps, '2026-10-03T10-00-00-482-collect-$anId').id,
        collect.id,
      );
      expect(
        only(steps, '2026-10-03T10-00-00-483-verdict-$anId').id,
        verdict.id,
      );
      expect(only(steps, '2026-10-03T10-00-00-484-fix-$anId').id, fix.id);
      expect(await handle.steps(), [collect, verdict, fix]);
    });

    test('gives each step its own millisecond when the clock moves by less '
        'than one', () async {
      final handle = await newSession(
        clock: tickingClock(tick: const Duration(microseconds: 100)),
      );

      final first = await newStep(handle);
      final second = await newStep(handle);

      final steps = p.join(handle.dir, 'steps');
      only(steps, '2026-10-03T10-00-00-482-collect-(${first.id})');
      only(steps, '2026-10-03T10-00-00-483-collect-(${second.id})');
    });

    test('steps leaves out a step that was never finished being '
        'created', () async {
      final handle = await newSession();
      final steps = [await newStep(handle)];
      final stepId = newId();
      final leftover = await Directory(
        p.join(handle.dir, 'steps', '.tmp-$stepId'),
      ).create();
      await File(p.join(leftover.path, 'step.json')).writeAsString(
        jsonEncode(
          Step(
            id: stepId,
            sessionId: handle.session.id,
            name: 'collect',
            key: 'collect#2@e3b0c44298fc1c14',
            after: null,
            place: null,
            outputId: null,
            log: 'step.log',
          ).toJson(),
        ),
      );

      expect(await handle.steps(), steps);
    });
  });

  group('appendEvent and events', () {
    test('write each event as one compact line and read them back', () async {
      final handle = await newSession();
      final step = await newStep(handle);
      final outputId = newId();
      final appended = <KnownEvent>[
        StepStarted(
          time: DateTime.utc(2026, 10, 3, 10, 1, 0, 5),
          stepId: step.id,
        ),
        StepFailed(
          time: DateTime.utc(2026, 10, 3, 10, 2),
          stepId: step.id,
          error: 'Exception: "no"',
          stack: '#0 main\n',
        ),
        SessionResumed(
          time: DateTime.utc(2026, 10, 3, 11),
          code: code,
          graphId: null,
        ),
        StepStarted(time: DateTime.utc(2026, 10, 3, 11, 1), stepId: step.id),
        StepFinished(
          time: DateTime.utc(2026, 10, 3, 11, 2),
          stepId: step.id,
          outputId: outputId,
        ),
        SessionFinished(
          time: DateTime.utc(2026, 10, 3, 11, 2, 0, 1),
          outputId: outputId,
        ),
      ];

      for (final event in appended) {
        await handle.appendEvent(event);
      }

      expect(
        read(journal(handle)),
        '{"time":"2026-10-03T10:00:00.482Z","event":"session-started",'
        '"code":"$code"}\n'
        '{"time":"2026-10-03T10:01:00.005Z","event":"step-started",'
        '"stepId":"${step.id}"}\n'
        '{"time":"2026-10-03T10:02:00.000Z","event":"step-failed",'
        '"stepId":"${step.id}",'
        r'"error":"Exception: \"no\"","stack":"#0 main\n"}'
        '\n'
        '{"time":"2026-10-03T11:00:00.000Z","event":"session-resumed",'
        '"code":"$code","graphId":null}\n'
        '{"time":"2026-10-03T11:01:00.000Z","event":"step-started",'
        '"stepId":"${step.id}"}\n'
        '{"time":"2026-10-03T11:02:00.000Z","event":"step-finished",'
        '"stepId":"${step.id}","outputId":"$outputId"}\n'
        '{"time":"2026-10-03T11:02:00.001Z","event":"session-finished",'
        '"outputId":"$outputId"}\n',
      );
      expect(await handle.events(), [isA<SessionStarted>(), ...appended]);
    });

    test('events gives a line it does not know as an UnknownEvent', () async {
      final handle = await newSession();
      final paused = {
        'time': '2026-10-03T10:01:00.000Z',
        'event': 'session-paused',
        'by': ['someone'],
      };
      File(journal(handle))
          .writeAsStringSync('${jsonEncode(paused)}\n', mode: FileMode.append);

      expect(await handle.events(), [
        isA<SessionStarted>(),
        UnknownEvent(paused),
      ]);
    });

    test('events leaves out an incomplete last line', () async {
      final handle = await newSession();
      final events = await handle.events();

      File(journal(handle))
          .writeAsStringSync('{"time":"2026-10-03T1', mode: FileMode.append);

      expect(await handle.events(), events);
    });

    test('events throws StoreCorruptedException with the path and number of a '
        'complete line that is not a JSON object', () async {
      final corruptLines = <List<int>>[
        utf8.encode('not json'),
        utf8.encode('[1]'),
        utf8.encode('"session-started"'),
        utf8.encode('null'),
        [],
        [0x7b, 0xff, 0x7d], // not UTF-8
      ];

      for (final corrupt in corruptLines) {
        final handle = await newSession();
        final valid = (await handle.events()).single;
        File(journal(handle)).writeAsBytesSync([
          ...corrupt,
          0x0a,
          ...utf8.encode('${jsonEncode(valid.toJson())}\n'),
        ], mode: FileMode.append);

        await expectLater(
          handle.events(),
          throwsA(
            isA<StoreCorruptedException>()
                .having((e) => e.path, 'path', journal(handle))
                .having((e) => e.line, 'line', 2),
          ),
          reason: utf8.decode(corrupt, allowMalformed: true),
        );
      }
    });
  });

  group('writeDocument and documentValue', () {
    test('write documents/<id>.json and read its value back', () async {
      final handle = await newSession(input: null);

      final id = await handle.writeDocument({'id': 'c1', 'path': 'lib/a.dart'});

      expect(isId(id), isTrue);
      expect(names(p.join(handle.dir, 'documents')), ['$id.json']);
      expect(read(p.join(handle.dir, 'documents', '$id.json')), '''
{
  "id": "$id",
  "sessionId": "${handle.session.id}",
  "value": {
    "id": "c1",
    "path": "lib/a.dart"
  }
}
''');
      expect(await handle.documentValue(id), {
        'id': 'c1',
        'path': 'lib/a.dart',
      });
      expect(dotEntries(handle.dir), isEmpty);
    });

    test('keep any JSON value, null included', () async {
      final handle = await newSession(input: null);
      final values = [
        null,
        true,
        3,
        2.5,
        'text',
        [
          1,
          {'a': null},
        ],
      ];

      final ids = [
        for (final value in values) await handle.writeDocument(value),
      ];

      expect(ids.toSet(), hasLength(values.length));
      expect([for (final id in ids) await handle.documentValue(id)], values);
    });
  });

  group('setStepOutput', () {
    test('rewrites step.json with the output and returns the step', () async {
      final handle = await newSession();
      final step = await newStep(handle, after: 'inspect#1@9f2c1a7b3d5e8f04');
      final outputId = await handle.writeDocument({'id': 'c1'});

      final finished = await handle.setStepOutput(step, outputId);

      expect(finished, step.withOutput(outputId));
      expect(read(p.join(stepDir(handle, step.id), 'step.json')), '''
{
  "id": "${step.id}",
  "sessionId": "${handle.session.id}",
  "name": "collect",
  "key": "collect#1@e3b0c44298fc1c14",
  "after": "inspect#1@9f2c1a7b3d5e8f04",
  "place": "lib/review.dart:12",
  "outputId": "$outputId",
  "log": "step.log"
}
''');
      expect(await handle.steps(), [finished]);
      expect(dotEntries(handle.dir), isEmpty);
    });

    test(
      'rewrites the step.json of a step of a session opened again',
      () async {
        final created = await newSession();
        final step = await newStep(created);
        await created.release();
        final opened = (await FsStore(p.dirname(created.dir))
            .openSession(created.session.id))!;

        final finished = await opened.setStepOutput(step, newId());

        expect(await opened.steps(), [finished]);
      },
    );
  });

  group('setStepAfter', () {
    test('rewrites step.json with the after and returns the step', () async {
      final handle = await newSession();
      final step = await newStep(handle, after: 'inspect#1@9f2c1a7b3d5e8f04');
      final finished = await handle.setStepOutput(step, newId());

      final again = await handle.setStepAfter(finished, null);

      expect(again, finished.withAfter(null));
      expect(
        Step.fromJson(
          jsonDecode(read(p.join(stepDir(handle, step.id), 'step.json')))
              as Map<String, Object?>,
        ),
        again,
      );
      expect(await handle.steps(), [again]);
      expect(dotEntries(handle.dir), isEmpty);
    });
  });

  group('a step finishing in the order of D3', () {
    test('has its output and step-finished before step.json gets the '
        'outputId', () async {
      final clock = tickingClock();
      final handle = await newSession(clock: clock);
      final step = await newStep(handle);
      final stepJson = p.join(stepDir(handle, step.id), 'step.json');
      await handle.appendEvent(StepStarted(time: clock(), stepId: step.id));

      final outputId = await handle.writeDocument('done');
      expect(await handle.documentValue(outputId), 'done');
      expect(Step.fromJson(_json(stepJson)).outputId, isNull);

      final finished = StepFinished(
        time: clock(),
        stepId: step.id,
        outputId: outputId,
      );
      await handle.appendEvent(finished);
      expect(await handle.events(), [
        SessionStarted(time: start, code: code),
        StepStarted(
          time: DateTime.utc(2026, 10, 3, 10, 0, 2, 482),
          stepId: step.id,
        ),
        StepFinished(
          time: DateTime.utc(2026, 10, 3, 10, 0, 3, 482),
          stepId: step.id,
          outputId: outputId,
        ),
      ]);
      expect(Step.fromJson(_json(stepJson)).outputId, isNull);

      await handle.setStepOutput(step, outputId);
      expect(Step.fromJson(_json(stepJson)).outputId, outputId);
      expect(
        p.basename(p.dirname(stepJson)),
        '2026-10-03T10-00-01-482-collect-${step.id}',
      );
    });
  });

  group('openLog', () {
    test('appends to step.log of the step, across opens', () async {
      final handle = await newSession();
      final step = await newStep(handle);
      final logFile = p.join(stepDir(handle, step.id), 'step.log');

      final first = handle.openLog(step.id);
      first.add(utf8.encode('started\n'));
      first.add(utf8.encode('crashed'));
      await first.close();
      final second = handle.openLog(step.id);
      second.add(utf8.encode('\nstarted again\n'));
      await second.close();

      expect(read(logFile), 'started\ncrashed\nstarted again\n');
    });

    test('of a step of a session opened again writes into its '
        'directory', () async {
      final created = await newSession();
      final step = await newStep(created);
      await created.release();
      final opened = (await FsStore(p.dirname(created.dir))
          .openSession(created.session.id))!;

      final log = opened.openLog(step.id)..add(utf8.encode('again\n'));
      await log.close();

      expect(read(p.join(stepDir(opened, step.id), 'step.log')), 'again\n');
    });

    test('flush makes the bytes added so far readable', () async {
      final handle = await newSession();
      final step = await newStep(handle);
      final logFile = p.join(stepDir(handle, step.id), 'step.log');
      final log = handle.openLog(step.id);
      addTearDown(log.close);

      log.add(utf8.encode('line 1\n'));
      await log.flush();

      expect(read(logFile), 'line 1\n');
    });

    test('a log it cannot open throws nothing, now or later: failed gives '
        'why', () async {
      final handle = await newSession();
      final step = await newStep(handle);
      // A directory where the file should be: it cannot be opened.
      final logFile = p.join(stepDir(handle, step.id), 'step.log');
      Directory(logFile).createSync();

      final log = handle.openLog(step.id);
      // Long enough for the open to have failed with nothing added.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      log.add(utf8.encode('lost\n'));
      await log.flush();
      await log.close();

      expect(
        await log.failed,
        isA<FileSystemException>().having((e) => e.path, 'path', logFile),
      );
    });

    test('writes what is added while a write is under way in one write, and '
        'tells how much is not written yet', () async {
      final handle = await newSession();
      final step = await newStep(handle);
      final file = _HeldWrites();
      final log = IOOverrides.runZoned(
        () => handle.openLog(step.id),
        createFile: (_) => _OpensTo(file),
      );

      log.add([1]);
      await pumpEventQueue();
      expect(file.writes, [
        [1],
      ], reason: 'the first write is under way');
      log
        ..add([2])
        ..add([3, 4])
        ..add([5]);
      expect(log.unwritten, 5);
      file.release();
      await log.flush();

      expect(file.writes, [
        [1],
        [2, 3, 4, 5],
      ]);
      expect(log.unwritten, 0);
      await log.close();
    });
  });

  group('a file that does not hold its model', () {
    test('is a FormatException that names the file', () async {
      final handle = await newSession();
      final step = await newStep(handle);
      final stepJson = p.join(stepDir(handle, step.id), 'step.json');
      await File(stepJson).writeAsString('{"id": 1}\n');

      await expectLater(
        handle.steps(),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            '$stepJson: id: expected a string',
          ),
        ),
      );
    });
  });

  group('a step the session does not have', () {
    test('is an argument error', () async {
      final handle = await newSession();
      final other = await newSession();
      final foreign = await newStep(other);

      expect(() => handle.openLog(newId()), throwsArgumentError);
      expect(() => handle.openLog(foreign.id), throwsArgumentError);
      expect(() => handle.setStepOutput(foreign, newId()), throwsArgumentError);
    });
  });

  group('a session whose directory is gone', () {
    // Removed while a process owns it. Building the directories again would
    // leave a session without session.json or a journal.
    test('createStep and writeDocument fail and make nothing', () async {
      final handle = await newSession();
      await Directory(handle.dir).delete(recursive: true);

      await expectLater(newStep(handle), throwsA(isA<FileSystemException>()));
      await expectLater(
        handle.writeDocument('lost'),
        throwsA(isA<FileSystemException>()),
      );
      await expectLater(
        handle.appendEvent(StepStarted(time: start, stepId: newId())),
        throwsA(isA<FileSystemException>()),
      );
      expect(Directory(handle.dir).existsSync(), isFalse);
    });
  });

  group('a session that is being removed', () {
    // `rm -rf` removes it depth first while a process still writes to it:
    // what it has not reached yet is still there.

    test(
      'appendEvent fails, and makes no journal, when there is none',
      () async {
        final handle = await newSession();
        File(journal(handle)).deleteSync();

        await expectLater(
          handle.appendEvent(StepStarted(time: start, stepId: newId())),
          throwsA(
            isA<PathNotFoundException>().having(
              (e) => e.path,
              'path',
              journal(handle),
            ),
          ),
        );
        expect(File(journal(handle)).existsSync(), isFalse);
      },
    );

    test('appendEvent fails once the session has no session.json', () async {
      final handle = await newSession();
      final sessionJson = p.join(handle.dir, 'session.json');
      File(sessionJson).deleteSync();

      await expectLater(
        handle.appendEvent(StepStarted(time: start, stepId: newId())),
        throwsA(
          isA<PathNotFoundException>().having(
            (e) => e.path,
            'path',
            sessionJson,
          ),
        ),
      );
    });

    test('createStep fails when the steps directory is gone', () async {
      final handle = await newSession();
      Directory(p.join(handle.dir, 'steps')).deleteSync();

      await expectLater(newStep(handle), throwsA(isA<FileSystemException>()));
      expect(Directory(p.join(handle.dir, 'steps')).existsSync(), isFalse);
    });

    test('the log of a step whose directory is gone fails, throwing '
        'nothing', () async {
      final handle = await newSession();
      final step = await newStep(handle);
      Directory(stepDir(handle, step.id)).deleteSync(recursive: true);

      final log = handle.openLog(step.id);
      log.add(utf8.encode('lost\n'));
      await log.close();

      expect(await log.failed, isA<PathNotFoundException>());
    });
  });
}

/// The JSON object in the file at [path].
Map<String, Object?> _json(String path) =>
    jsonDecode(read(path)) as Map<String, Object?>;

/// A file that opens to [file], whatever its path.
final class _OpensTo implements File {
  _OpensTo(this.file);

  final RandomAccessFile file;

  @override
  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) async => file;

  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// An open file that keeps what each write gave it, and holds every write
/// until [release].
final class _HeldWrites implements RandomAccessFile {
  final writes = <List<int>>[];
  final _released = Completer<void>();

  /// Lets the writes, held and to come, complete.
  void release() => _released.complete();

  @override
  Future<RandomAccessFile> writeFrom(
    List<int> buffer, [
    int start = 0,
    int? end,
  ]) async {
    writes.add(buffer.sublist(start, end));
    await _released.future;
    return this;
  }

  @override
  Future<void> close() async {}

  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
