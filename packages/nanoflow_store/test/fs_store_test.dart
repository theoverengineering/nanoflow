import 'dart:convert';
import 'dart:io';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_store/nanoflow_store.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support.dart';

void main() {
  group('createSession', () {
    test('builds the README tree, with every file in its JSON form', () async {
      final runsDir = p.join(await tempDir(), 'runs');
      final store = FsStore(runsDir, clock: () => start);

      final handle = await store.createSession(
        graphName: 'review',
        graph: graph,
        startNodes: [(node: 'collect', takesInput: true)],
        input: (value: {'branch': 'main'}),
      );

      final session = only(runsDir, 'review-2026-09-20T14-03-11-$anId');
      final sessionId = session.id;
      expect(handle.session, Session(id: sessionId, graph: graph));
      expect(handle.dir, session.path);
      expect(names(session.path), [
        // The lock the engine that drives the session holds.
        '.engine.lock',
        matches('^2026-09-20T14-03-11-470-$anId\$'),
        'documents',
        'session.json',
      ]);
      expect(
        read(p.join(session.path, 'session.json')),
        sessionJson(sessionId),
      );

      final document = only(p.join(session.path, 'documents'), '$anId\\.json');
      expect(read(document.path), '''
{
  "id": "${document.id}",
  "sessionId": "$sessionId",
  "value": {
    "branch": "main"
  }
}
''');

      final run = only(session.path, '2026-09-20T14-03-11-470-$anId');
      expect(names(run.path), ['log.jsonl', 'run.json', 'steps']);
      expect(read(p.join(run.path, 'run.json')), '''
{
  "id": "${run.id}",
  "sessionId": "$sessionId",
  "parentId": null
}
''');
      expect(
        read(p.join(run.path, 'log.jsonl')),
        '{"runId":"${run.id}","time":"2026-09-20T14:03:11.470Z",'
        '"event":"run-started","node":"collect"}\n',
      );

      final step = only(
        p.join(run.path, 'steps'),
        '2026-09-20T14-03-11-470-collect-$anId',
      );
      expect(names(step.path), ['step.json']);
      expect(read(p.join(step.path, 'step.json')), '''
{
  "id": "${step.id}",
  "runId": "${run.id}",
  "inputId": "${document.id}",
  "outputId": null,
  "log": "command.log"
}
''');
    });

    test('names the session by its creation time, and each run and first '
        'step by the time each was created', () async {
      final runsDir = p.join(await tempDir(), 'runs');
      final store = FsStore(runsDir, clock: tickingClock());

      final handle = await store.createSession(
        graphName: 'review',
        graph: graph,
        startNodes: [
          (node: 'collect', takesInput: true),
          (node: 'notify', takesInput: false),
        ],
        input: (value: {'branch': 'main'}),
      );

      final session = only(runsDir, 'review-2026-09-20T14-03-11-$anId');
      expect(session.id, handle.session.id);
      final collect = only(session.path, '2026-09-20T14-03-12-470-$anId');
      final notify = only(session.path, '2026-09-20T14-03-14-470-$anId');
      only(
        p.join(collect.path, 'steps'),
        '2026-09-20T14-03-13-470-collect-$anId',
      );
      only(
        p.join(notify.path, 'steps'),
        '2026-09-20T14-03-15-470-notify-$anId',
      );
      expect(await handle.events(collect.id), [
        RunStarted(
          runId: collect.id,
          time: DateTime.utc(2026, 9, 20, 14, 3, 12, 470),
          node: 'collect',
        ),
      ]);
      expect(await handle.events(notify.id), [
        RunStarted(
          runId: notify.id,
          time: DateTime.utc(2026, 9, 20, 14, 3, 14, 470),
          node: 'notify',
        ),
      ]);
    });

    test(
      'builds the session under .tmp-<id> and renames it into place',
      () async {
        final runsDir = p.join(await tempDir(), 'runs');
        // What runsDir holds each time the clock is read: the clock is read
        // while the runs and steps of the session are being built.
        final seen = <List<String>>[];
        final store = FsStore(
          runsDir,
          clock: () {
            seen.add(Directory(runsDir).existsSync() ? names(runsDir) : []);
            return start;
          },
        );

        final handle = await store.createSession(
          graphName: 'review',
          graph: graph,
          startNodes: [
            (node: 'collect', takesInput: true),
            (node: 'notify', takesInput: false),
          ],
          input: (value: {'branch': 'main'}),
        );

        expect(seen, hasLength(greaterThan(1)));
        expect(seen.first, isEmpty);
        expect(seen.skip(1), everyElement(['.tmp-${handle.session.id}']));
        expect(names(runsDir), [p.basename(handle.dir)]);
      },
    );

    test('names the runs in the order they were created, even within one '
        'millisecond', () async {
      final runsDir = p.join(await tempDir(), 'runs');
      final store = FsStore(runsDir, clock: () => start);

      final handle = await store.createSession(
        graphName: 'review',
        graph: graph,
        startNodes: [
          (node: 'collect', takesInput: true),
          (node: 'notify', takesInput: false),
          (node: 'audit', takesInput: false),
        ],
        input: (value: {'branch': 'main'}),
      );

      final runIds = [
        for (final millisecond in [470, 471, 472])
          only(handle.dir, '2026-09-20T14-03-11-$millisecond-$anId').id,
      ];
      expect(
        [for (final id in runIds) await firstNode(handle, id)],
        ['collect', 'notify', 'audit'],
      );
      expect(await handle.events(runIds[1]), [
        RunStarted(
          runId: runIds[1],
          time: DateTime.utc(2026, 9, 20, 14, 3, 11, 471),
          node: 'notify',
        ),
      ]);
      expect([for (final run in await handle.runs()) run.id], runIds);
    });

    test('leaves no temporary entries behind', () async {
      final handle = await newSession(
        startNodes: [
          (node: 'collect', takesInput: true),
          (node: 'notify', takesInput: false),
        ],
      );

      final runsDir = p.dirname(handle.dir);
      expect(names(runsDir), [p.basename(handle.dir)]);
      expect(dotEntries(runsDir), isEmpty);
    });

    test('refers to the input document only from the first steps of start '
        'nodes that take input', () async {
      final handle = await newSession(
        startNodes: [
          (node: 'collect', takesInput: true),
          (node: 'notify', takesInput: false),
          (node: 'audit', takesInput: true),
        ],
        input: (value: {'branch': 'main'}),
      );

      final documents = names(p.join(handle.dir, 'documents'));
      expect(documents, [matches('^$anId\\.json\$')]);
      final inputId = p.basenameWithoutExtension(documents.single);
      expect(await handle.documentValue(inputId), {'branch': 'main'});

      final runs = await handle.runs();
      expect(runs.map((run) => run.parentId), [null, null, null]);
      expect(
        [for (final run in runs) await firstNode(handle, run.id)],
        ['collect', 'notify', 'audit'],
      );
      expect(
        [for (final run in runs) (await handle.steps(run.id)).single.inputId],
        [inputId, null, inputId],
      );
    });

    test('writes no document when there is no input', () async {
      final handle = await newSession(
        startNodes: [(node: 'collect', takesInput: true)],
        input: null,
      );

      expect(names(p.join(handle.dir, 'documents')), isEmpty);
      final run = (await handle.runs()).single;
      expect((await handle.steps(run.id)).single.inputId, isNull);
    });

    test('creates the runs directory when there is none', () async {
      final runsDir = p.join(await tempDir(), 'project', 'runs');

      final handle = await FsStore(runsDir).createSession(
        graphName: 'review',
        graph: graph,
        startNodes: [(node: 'collect', takesInput: false)],
      );

      expect(names(runsDir), [p.basename(handle.dir)]);
    });
  });

  group('openSession', () {
    test('finds a session by its id and reads it back', () async {
      final runsDir = p.join(await tempDir(), 'runs');
      final store = FsStore(runsDir, clock: tickingClock());
      final created = await store.createSession(
        graphName: 'review',
        graph: graph,
        startNodes: [(node: 'collect', takesInput: true)],
        input: (value: {'branch': 'main'}),
      );
      final other = await store.createSession(
        graphName: 'review-x',
        graph: graph,
        startNodes: [(node: 'collect', takesInput: false)],
      );

      final opened = (await FsStore(runsDir).openSession(created.session.id))!;

      expect(opened.session, created.session);
      expect(opened.dir, created.dir);
      final runs = await opened.runs();
      expect(runs, await created.runs());
      expect(
        await opened.steps(runs.single.id),
        await created.steps(runs.single.id),
      );
      expect(
        await opened.events(runs.single.id),
        await created.events(runs.single.id),
      );
      expect((await store.openSession(other.session.id))!.dir, other.dir);
    });

    test('returns null for an id no session has', () async {
      final handle = await newSession();
      final store = FsStore(p.dirname(handle.dir));

      expect(await store.openSession(newId()), isNull);
      expect(await store.openSession('not-an-id'), isNull);
    });

    test('returns null when there is no runs directory', () async {
      final store = FsStore(p.join(await tempDir(), 'runs'));

      expect(await store.openSession(newId()), isNull);
    });

    test('ignores a directory whose name starts with a dot', () async {
      final runsDir = p.join(await tempDir(), 'runs');
      final sessionId = newId();
      final unfinished = Directory(p.join(runsDir, '.tmp-$sessionId'));
      await unfinished.create(recursive: true);
      await File(p.join(unfinished.path, 'session.json'))
          .writeAsString(sessionJson(sessionId));

      expect(await FsStore(runsDir).openSession(sessionId), isNull);
    });

    test('leaves alone a run that was never finished being created', () async {
      final created = await newSession();
      final runs = await created.runs();
      final runId = newId();
      final leftover = await Directory(p.join(created.dir, '.tmp-$runId'))
          .create();
      await File(p.join(leftover.path, 'run.json')).writeAsString(
        jsonEncode(
          Run(
            id: runId,
            sessionId: created.session.id,
            parentId: runs.single.id,
          ).toJson(),
        ),
      );
      final journal = p.join(leftover.path, 'log.jsonl');
      await File(journal).writeAsString('{"runId":"$runId"');

      final opened = (await FsStore(p.dirname(created.dir))
          .openSession(created.session.id))!;

      expect(await opened.runs(), runs);
      expect(read(journal), '{"runId":"$runId"');
    });

    test('refuses a session another process drives, without touching it, '
        'and opens it once that process is gone', () async {
      final runsDir = p.join(await tempDir(), 'runs');
      final engine = await Process.start(Platform.resolvedExecutable, [
        'run',
        p.join('test', 'fixtures', 'drive_session.dart'),
        runsDir,
      ]);
      addTearDown(() => engine.kill(ProcessSignal.sigkill));
      engine.stderr.drain<void>().ignore();
      final id = await engine.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first;
      final session = only(runsDir, 'review-[0-9T-]{19}-($id)');
      final run = only(session.path, '[0-9T-]{23}-$anId');
      final journal = p.join(run.path, 'log.jsonl');
      // The engine is writing an event.
      File(journal).writeAsStringSync('{"runId":', mode: FileMode.append);
      final written = read(journal);

      await expectLater(
        FsStore(runsDir).openSession(id),
        throwsA(
          isA<SessionBusyException>()
              .having((e) => e.sessionId, 'sessionId', id)
              .having(
                (e) => '$e',
                'toString',
                contains('session $id is being run by another engine'),
              ),
        ),
      );
      expect(read(journal), written);

      // The system drops the lock of a process that dies.
      engine.kill(ProcessSignal.sigkill);
      await engine.exitCode;
      final opened = await FsStore(runsDir).openSession(id);
      expect(opened?.session.id, id);
      expect(read(journal), endsWith('"node":"collect"}\n'));
    });

    test('cuts an incomplete last line off each journal, so new events '
        'append cleanly', () async {
      final created = await newSession(
        startNodes: [
          (node: 'collect', takesInput: true),
          (node: 'notify', takesInput: false),
          (node: 'audit', takesInput: false),
        ],
      );
      final [collect, notify, audit] = await created.runs();
      final started = StepStarted(
        runId: collect.id,
        time: DateTime.utc(2026, 9, 20, 14, 4),
        stepId: (await created.steps(collect.id)).single.id,
        node: 'collect',
      );
      await created.appendEvent(started);
      final collectLog = p.join(runDir(created, collect.id), 'log.jsonl');
      final notifyLog = p.join(runDir(created, notify.id), 'log.jsonl');
      final auditLog = p.join(runDir(created, audit.id), 'log.jsonl');
      final collectText = read(collectLog);
      final notifyText = read(notifyLog);
      final auditText = read(auditLog);
      await File(collectLog).writeAsString(
        '{"runId":"${collect.id}","time":"2026-09-',
        mode: FileMode.append,
      );
      await File(notifyLog).writeAsString('{', mode: FileMode.append);

      final opened = (await FsStore(p.dirname(created.dir))
          .openSession(created.session.id))!;

      expect(read(collectLog), collectText);
      expect(read(notifyLog), notifyText);
      expect(read(auditLog), auditText);
      final finished = StepFinished(
        runId: collect.id,
        time: DateTime.utc(2026, 9, 20, 14, 5),
        stepId: started.stepId,
        exitCode: 0,
        outputId: null,
      );
      await opened.appendEvent(finished);
      expect(await opened.events(collect.id), [
        isA<RunStarted>(),
        started,
        finished,
      ]);
      expect(read(collectLog), '$collectText${_line(finished)}');
    });
  });
}

/// The line [event] takes in a journal.
String _line(Event event) => '${jsonEncode(event.toJson())}\n';
