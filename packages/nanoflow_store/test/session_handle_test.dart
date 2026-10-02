import 'dart:convert';
import 'dart:io';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_store/nanoflow_store.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support.dart';

// newSession() reads the ticking clock three times: the session at 14:03:11,
// its run at 14:03:12 and the run's first step at 14:03:13. The next reading
// is 14:03:14.470.

void main() {
  group('runs', () {
    test('lists the runs in the order they were created', () async {
      final handle = await newSession(
        startNodes: [
          (node: 'publish', takesInput: false),
          (node: 'notify', takesInput: false),
        ],
      );
      final [publish, notify] = await handle.runs();
      final (child, _) = await handle.createRun(
        parentId: notify.id,
        node: 'fix',
        inputId: null,
      );

      expect(await handle.runs(), [publish, notify, child]);
      expect(
        [
          for (final run in await handle.runs())
            await firstNode(handle, run.id),
        ],
        ['publish', 'notify', 'fix'],
      );
    });
  });

  group('createRun', () {
    test('creates a run with its first step, run-started being its only '
        'event', () async {
      final handle = await newSession();
      final parent = (await handle.runs()).single;
      final inputId = newId();

      final (run, step) = await handle.createRun(
        parentId: parent.id,
        node: 'publish',
        inputId: inputId,
      );

      expect(isId(run.id), isTrue);
      expect(
        run,
        Run(id: run.id, sessionId: handle.session.id, parentId: parent.id),
      );
      expect(isId(step.id), isTrue);
      expect(
        step,
        Step(
          id: step.id,
          runId: run.id,
          inputId: inputId,
          outputId: null,
          log: 'command.log',
        ),
      );

      final runDir = only(handle.dir, '2026-09-20T14-03-14-470-$anId');
      expect(runDir.id, run.id);
      expect(names(runDir.path), ['log.jsonl', 'run.json', 'steps']);
      expect(read(p.join(runDir.path, 'run.json')), '''
{
  "id": "${run.id}",
  "sessionId": "${handle.session.id}",
  "parentId": "${parent.id}"
}
''');
      final stepDir = only(
        p.join(runDir.path, 'steps'),
        '2026-09-20T14-03-15-470-publish-$anId',
      );
      expect(stepDir.id, step.id);
      expect(names(stepDir.path), ['step.json']);
      expect(read(p.join(stepDir.path, 'step.json')), '''
{
  "id": "${step.id}",
  "runId": "${run.id}",
  "inputId": "$inputId",
  "outputId": null,
  "log": "command.log"
}
''');

      expect(await handle.events(run.id), [
        RunStarted(
          runId: run.id,
          time: DateTime.utc(2026, 9, 20, 14, 3, 14, 470),
          node: 'publish',
        ),
      ]);
      expect(await handle.steps(run.id), [step]);
      expect(await handle.runs(), [parent, run]);
      expect(dotEntries(handle.dir), isEmpty);
    });

    test('builds the run under .tmp-<id> and renames it into place', () async {
      final ticking = tickingClock();
      String? watched;
      // What the session directory holds each time the clock is read once it
      // is watched: the clock is read while the run's first step is built.
      final seen = <List<String>>[];
      final handle = await newSession(
        clock: () {
          if (watched case final dir?) seen.add(names(dir));
          return ticking();
        },
      );
      final parent = (await handle.runs()).single;
      final before = names(handle.dir);
      watched = handle.dir;

      final (run, _) = await handle.createRun(
        parentId: parent.id,
        node: 'publish',
        inputId: null,
      );

      expect(seen, hasLength(greaterThan(1)));
      expect(seen.first, before);
      expect(seen.skip(1), everyElement([...before, '.tmp-${run.id}']..sort()));
      expect(
        names(handle.dir),
        [...before, p.basename(runDir(handle, run.id))]..sort(),
      );
    });

    test('names runs in the order they were created, even within one '
        'millisecond', () async {
      // The session's first run takes 14:03:11.470.
      final handle = await newSession(clock: () => start);
      final root = (await handle.runs()).single;

      final children = [
        for (final node in ['publish', 'notify', 'fix'])
          (await handle.createRun(
            parentId: root.id,
            node: node,
            inputId: null,
          )).$1,
      ];

      for (final (i, child) in children.indexed) {
        final millisecond = 471 + i;
        expect(
          only(handle.dir, '2026-09-20T14-03-11-$millisecond-$anId').id,
          child.id,
        );
        expect(
          (await handle.events(child.id)).single,
          isA<RunStarted>().having(
            (e) => e.time,
            'time',
            DateTime.utc(2026, 9, 20, 14, 3, 11, millisecond),
          ),
        );
      }
      expect(await handle.runs(), [root, ...children]);
    });

    test('gives each run its own millisecond when the clock moves by less '
        'than one', () async {
      final handle = await newSession(
        clock: tickingClock(tick: const Duration(microseconds: 100)),
      );
      final root = (await handle.runs()).single;

      final (child, _) = await handle.createRun(
        parentId: root.id,
        node: 'publish',
        inputId: null,
      );

      only(handle.dir, '2026-09-20T14-03-11-470-(${root.id})');
      only(handle.dir, '2026-09-20T14-03-11-471-(${child.id})');
    });
  });

  group('createStep', () {
    test('adds a step directory with step.json and writes no event', () async {
      final handle = await newSession();
      final run = (await handle.runs()).single;
      final first = (await handle.steps(run.id)).single;
      final events = await handle.events(run.id);
      final inputId = newId();

      final step = await handle.createStep(
        runId: run.id,
        node: 'is-empty',
        inputId: inputId,
      );

      expect(isId(step.id), isTrue);
      expect(
        step,
        Step(
          id: step.id,
          runId: run.id,
          inputId: inputId,
          outputId: null,
          log: 'command.log',
        ),
      );
      final stepDir = only(
        p.join(runDir(handle, run.id), 'steps'),
        '2026-09-20T14-03-14-470-is-empty-$anId',
      );
      expect(stepDir.id, step.id);
      expect(names(stepDir.path), ['step.json']);
      expect(read(p.join(stepDir.path, 'step.json')), '''
{
  "id": "${step.id}",
  "runId": "${run.id}",
  "inputId": "$inputId",
  "outputId": null,
  "log": "command.log"
}
''');
      expect(await handle.steps(run.id), [first, step]);
      expect(await handle.events(run.id), events);
      expect(dotEntries(handle.dir), isEmpty);
    });

    test(
      'steps lists the steps of a run in the order they were created',
      () async {
        final handle = await newSession();
        final run = (await handle.runs()).single;
        final collect = (await handle.steps(run.id)).single;

        final verdict = await handle.createStep(
          runId: run.id,
          node: 'verdict',
          inputId: null,
        );
        final fix = await handle.createStep(
          runId: run.id,
          node: 'fix',
          inputId: null,
        );

        expect(await handle.steps(run.id), [collect, verdict, fix]);
      },
    );

    test('names the steps of a run in the order they were created, even '
        'within one millisecond', () async {
      final handle = await newSession(clock: () => start);
      final run = (await handle.runs()).single;
      final collect = (await handle.steps(run.id)).single;

      final verdict = await handle.createStep(
        runId: run.id,
        node: 'verdict',
        inputId: null,
      );
      final fix = await handle.createStep(
        runId: run.id,
        node: 'fix',
        inputId: null,
      );

      final steps = p.join(runDir(handle, run.id), 'steps');
      expect(
        only(steps, '2026-09-20T14-03-11-470-collect-$anId').id,
        collect.id,
      );
      expect(
        only(steps, '2026-09-20T14-03-11-471-verdict-$anId').id,
        verdict.id,
      );
      expect(only(steps, '2026-09-20T14-03-11-472-fix-$anId').id, fix.id);
      expect(await handle.steps(run.id), [collect, verdict, fix]);
    });

    test('steps leaves out a step that was never finished being '
        'created', () async {
      final handle = await newSession();
      final run = (await handle.runs()).single;
      final steps = await handle.steps(run.id);
      final stepId = newId();
      final leftover = await Directory(
        p.join(runDir(handle, run.id), 'steps', '.tmp-$stepId'),
      ).create();
      await File(p.join(leftover.path, 'step.json')).writeAsString(
        jsonEncode(
          Step(
            id: stepId,
            runId: run.id,
            inputId: null,
            outputId: null,
            log: 'command.log',
          ).toJson(),
        ),
      );

      expect(await handle.steps(run.id), steps);
    });
  });

  group('appendEvent and events', () {
    test('write each event as one compact line and read them back', () async {
      final handle = await newSession();
      final run = (await handle.runs()).single;
      final step = (await handle.steps(run.id)).single;
      final outputId = newId();
      final appended = [
        StepStarted(
          runId: run.id,
          time: DateTime.utc(2026, 9, 20, 14, 4, 0, 5),
          stepId: step.id,
          node: 'collect',
        ),
        StepFinished(
          runId: run.id,
          time: DateTime.utc(2026, 9, 20, 14, 5),
          stepId: step.id,
          exitCode: 0,
          outputId: outputId,
        ),
        RunFailed(
          runId: run.id,
          time: DateTime.utc(2026, 9, 20, 14, 5, 0, 1),
          stepId: step.id,
          error: 'no target for outcome "maybe"',
        ),
      ];

      for (final event in appended) {
        await handle.appendEvent(event);
      }

      expect(
        read(p.join(runDir(handle, run.id), 'log.jsonl')),
        '{"runId":"${run.id}","time":"2026-09-20T14:03:12.470Z",'
        '"event":"run-started","node":"collect"}\n'
        '{"runId":"${run.id}","time":"2026-09-20T14:04:00.005Z",'
        '"event":"step-started","stepId":"${step.id}","node":"collect"}\n'
        '{"runId":"${run.id}","time":"2026-09-20T14:05:00.000Z",'
        '"event":"step-finished","stepId":"${step.id}","exitCode":0,'
        '"outputId":"$outputId"}\n'
        '{"runId":"${run.id}","time":"2026-09-20T14:05:00.001Z",'
        '"event":"run-failed","stepId":"${step.id}",'
        r'"error":"no target for outcome \"maybe\""}'
        '\n',
      );
      expect(await handle.events(run.id), [isA<RunStarted>(), ...appended]);
    });

    test('keep an event of an unknown kind as it was', () async {
      final handle = await newSession();
      final run = (await handle.runs()).single;
      final paused = UnknownEvent({
        'runId': run.id,
        'time': '2026-09-20T14:04:00.000Z',
        'event': 'run-paused',
        'by': ['someone'],
      });

      await handle.appendEvent(paused);

      expect(await handle.events(run.id), [isA<RunStarted>(), paused]);
    });

    test('events leaves out an incomplete last line', () async {
      final handle = await newSession();
      final run = (await handle.runs()).single;
      final events = await handle.events(run.id);

      await File(p.join(runDir(handle, run.id), 'log.jsonl'))
          .writeAsString('{"runId":"${run.id}","ti', mode: FileMode.append);

      expect(await handle.events(run.id), events);
    });

    test('events throws StoreCorruptedException with the path and number of a '
        'complete line that is not a JSON object', () async {
      final handle = await newSession();
      final valid = (await handle.events((await handle.runs()).single.id))
          .single;
      final corruptLines = <List<int>>[
        utf8.encode('not json'),
        utf8.encode('[1]'),
        utf8.encode('"run-started"'),
        utf8.encode('null'),
        [],
        [0x7b, 0xff, 0x7d], // not UTF-8
      ];

      for (final corrupt in corruptLines) {
        final (run, _) = await handle.createRun(
          parentId: null,
          node: 'collect',
          inputId: null,
        );
        final journal = p.join(runDir(handle, run.id), 'log.jsonl');
        await File(journal).writeAsBytes([
          ...corrupt,
          0x0a,
          ...utf8.encode('${jsonEncode(valid.toJson())}\n'),
        ], mode: FileMode.append);

        await expectLater(
          handle.events(run.id),
          throwsA(
            isA<StoreCorruptedException>()
                .having((e) => e.path, 'path', journal)
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
      final run = (await handle.runs()).single;
      final step = (await handle.steps(run.id)).single;
      final outputId = await handle.writeDocument({'id': 'c1'});

      final finished = await handle.setStepOutput(step, outputId);

      expect(finished, step.withOutput(outputId));
      expect(read(p.join(stepDir(handle, run.id, step.id), 'step.json')), '''
{
  "id": "${step.id}",
  "runId": "${run.id}",
  "inputId": "${step.inputId}",
  "outputId": "$outputId",
  "log": "command.log"
}
''');
      expect(await handle.steps(run.id), [finished]);
      expect(dotEntries(handle.dir), isEmpty);
    });
  });

  group('openLog', () {
    test('appends to command.log of the step, across opens', () async {
      final handle = await newSession();
      final run = (await handle.runs()).single;
      final step = (await handle.steps(run.id)).single;
      final logFile = p.join(stepDir(handle, run.id, step.id), 'command.log');

      final first = handle.openLog(run.id, step.id);
      first.add(utf8.encode('started\n'));
      first.add(utf8.encode('crashed'));
      await first.close();
      final second = handle.openLog(run.id, step.id);
      second.add(utf8.encode('\nstarted again\n'));
      await second.close();

      expect(read(logFile), 'started\ncrashed\nstarted again\n');
    });

    test('flush makes the bytes added so far readable', () async {
      final handle = await newSession();
      final run = (await handle.runs()).single;
      final step = (await handle.steps(run.id)).single;
      final logFile = p.join(stepDir(handle, run.id, step.id), 'command.log');
      final log = handle.openLog(run.id, step.id);
      addTearDown(log.close);

      log.add(utf8.encode('line 1\n'));
      await log.flush();

      expect(read(logFile), 'line 1\n');
    });

    test('a log it cannot open throws nothing, now or later: failed gives '
        'why', () async {
      final handle = await newSession();
      final run = (await handle.runs()).single;
      final step = (await handle.steps(run.id)).single;
      // A directory where the file should be: it cannot be opened.
      final logFile = p.join(stepDir(handle, run.id, step.id), 'command.log');
      Directory(logFile).createSync();

      final log = handle.openLog(run.id, step.id);
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
  });

  group('a file that does not hold its model', () {
    test('is a FormatException that names the file', () async {
      final handle = await newSession();
      final run = (await handle.runs()).single;
      final step = (await handle.steps(run.id)).single;
      final runJson = p.join(runDir(handle, run.id), 'run.json');
      final stepJson = p.join(stepDir(handle, run.id, step.id), 'step.json');
      await File(runJson).writeAsString('[]\n');
      await File(stepJson).writeAsString('{"id": 1}\n');

      await expectLater(
        handle.runs(),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            '$runJson: expected a JSON object',
          ),
        ),
      );
      await expectLater(
        handle.steps(run.id),
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

  group('a run the session does not have', () {
    test('is an argument error', () async {
      final handle = await newSession();
      final unknown = newId();

      expect(() => handle.events(unknown), throwsArgumentError);
      expect(() => handle.steps(unknown), throwsArgumentError);
      expect(
        () => handle.createStep(runId: unknown, node: 'fix', inputId: null),
        throwsArgumentError,
      );
      expect(
        () => handle.appendEvent(
          RunFinished(runId: unknown, time: DateTime.utc(2026)),
        ),
        throwsArgumentError,
      );
      expect(() => handle.openLog(unknown, newId()), throwsArgumentError);
    });
  });

  group('a session whose directory is gone', () {
    // Removed while an engine drives it. Building the directories again
    // would leave a session without session.json and runs without run.json
    // or run-started.
    test('createStep and createRun fail and make nothing', () async {
      final handle = await newSession();
      final run = (await handle.runs()).single;
      // An engine has the run's directory looked up by now.
      await handle.events(run.id);
      await Directory(handle.dir).delete(recursive: true);

      await expectLater(
        handle.createStep(runId: run.id, node: 'publish', inputId: null),
        throwsA(isA<FileSystemException>()),
      );
      await expectLater(
        handle.createRun(parentId: run.id, node: 'publish', inputId: null),
        throwsA(isA<FileSystemException>()),
      );
      expect(Directory(handle.dir).existsSync(), isFalse);
    });
  });
}
