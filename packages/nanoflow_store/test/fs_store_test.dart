import 'dart:convert';
import 'dart:io';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_store/nanoflow_store.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support.dart';

void main() {
  group('createSession', () {
    test('builds the spec tree, with every file in its JSON form', () async {
      final runsDir = p.join(await tempDir(), 'runs');
      final store = FsStore(runsDir, clock: () => start);

      final handle = await store.createSession(
        workflow: 'review',
        graph: graph,
        input: (value: {'branch': 'main'}),
        code: code,
      );

      final session = only(runsDir, 'review-2026-10-03T10-00-00-$anId');
      final sessionId = session.id;
      final document = only(p.join(session.path, 'documents'), '$anId\\.json');
      expect(
        handle.session,
        Session(
          id: sessionId,
          workflow: 'review',
          graph: graph,
          inputId: document.id,
        ),
      );
      expect(handle.dir, session.path);
      expect(names(session.path), [
        // The lock the process that owns the session holds.
        '.owner.lock',
        'documents',
        'log.jsonl',
        'session.json',
        'steps',
      ]);
      expect(
        read(p.join(session.path, 'session.json')),
        sessionJson(sessionId, inputId: document.id),
      );
      expect(read(document.path), '''
{
  "id": "${document.id}",
  "sessionId": "$sessionId",
  "value": {
    "branch": "main"
  }
}
''');
      expect(
        read(p.join(session.path, 'log.jsonl')),
        '{"time":"2026-10-03T10:00:00.482Z","event":"session-started",'
        '"code":"$code"}\n',
      );
      expect(names(p.join(session.path, 'steps')), isEmpty);
      expect(await handle.events(), [SessionStarted(time: start, code: code)]);
      expect(await handle.steps(), isEmpty);
      expect(await handle.documentValue(document.id), {'branch': 'main'});
    });

    test('writes no input document, and null for a missing graph, input and '
        'code', () async {
      final runsDir = p.join(await tempDir(), 'runs');
      final store = FsStore(runsDir, clock: () => start);

      final handle = await store.createSession(
        workflow: 'review',
        graph: null,
        input: null,
        code: null,
      );

      expect(
        handle.session,
        Session(
          id: handle.session.id,
          workflow: 'review',
          graph: null,
          inputId: null,
        ),
      );
      expect(names(p.join(handle.dir, 'documents')), isEmpty);
      expect(read(p.join(handle.dir, 'session.json')), '''
{
  "id": "${handle.session.id}",
  "workflow": "review",
  "graph": null,
  "inputId": null
}
''');
      expect(
        read(p.join(handle.dir, 'log.jsonl')),
        '{"time":"2026-10-03T10:00:00.482Z","event":"session-started",'
        '"code":null}\n',
      );
    });

    test('keeps an input of null as a document', () async {
      final handle = await newSession(input: (value: null));

      final inputId = handle.session.inputId!;
      expect(names(p.join(handle.dir, 'documents')), ['$inputId.json']);
      expect(await handle.documentValue(inputId), isNull);
    });

    test(
      'builds the session under .tmp-<id> and renames it into place',
      () async {
        final runsDir = p.join(await tempDir(), 'runs');
        // What runsDir holds while the input document is being written.
        final probe = _Probe(() => names(runsDir));

        final handle = await FsStore(runsDir).createSession(
          workflow: 'review',
          graph: graph,
          input: (value: probe),
          code: code,
        );

        expect(probe.seen, [
          ['.tmp-${handle.session.id}'],
        ]);
        expect(names(runsDir), [p.basename(handle.dir)]);
        expect(dotEntries(runsDir), isEmpty);
      },
    );

    test('names the session after its workflow, made safe', () async {
      final runsDir = p.join(await tempDir(), 'runs');

      final handle = await FsStore(runsDir, clock: () => start).createSession(
        workflow: r'review$2',
        graph: null,
        input: null,
        code: null,
      );

      expect(
        p.basename(handle.dir),
        'review_2-2026-10-03T10-00-00-${handle.session.id}',
      );
      expect(handle.session.workflow, r'review$2');
    });

    test('creates the runs directory when there is none', () async {
      final runsDir = p.join(await tempDir(), 'project', 'runs');

      final handle = await FsStore(runsDir).createSession(
        workflow: 'review',
        graph: graph,
        input: null,
        code: code,
      );

      expect(names(runsDir), [p.basename(handle.dir)]);
    });
  });

  group('openSession', () {
    test('finds a session by its id and reads it back', () async {
      final runsDir = p.join(await tempDir(), 'runs');
      final store = FsStore(runsDir, clock: tickingClock());
      final created = await store.createSession(
        workflow: 'review',
        graph: graph,
        input: (value: {'branch': 'main'}),
        code: code,
      );
      final step = await newStep(created);
      await created.appendEvent(
        StepStarted(
          time: start.add(const Duration(minutes: 1)),
          stepId: step.id,
        ),
      );
      final other = await store.createSession(
        workflow: 'review-x',
        graph: graph,
        input: null,
        code: code,
      );
      await created.release();
      await other.release();

      final opened = (await FsStore(runsDir).openSession(created.session.id))!;

      expect(opened.session, created.session);
      expect(opened.dir, created.dir);
      expect(await opened.steps(), [step]);
      expect(await opened.events(), await created.events());
      expect(await opened.documentValue(created.session.inputId!), {
        'branch': 'main',
      });
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
          .writeAsString(sessionJson(sessionId, inputId: null));

      expect(await FsStore(runsDir).openSession(sessionId), isNull);
    });

    test(
      'throws the FileSystemException of a session it cannot read',
      () async {
        final created = await newSession();
        await created.release();
        Process.runSync('chmod', ['000', created.dir]);
        addTearDown(() => Process.runSync('chmod', ['700', created.dir]));

        await expectLater(
          FsStore(p.dirname(created.dir)).openSession(created.session.id),
          throwsA(isA<FileSystemException>()),
        );
      },
    );

    test('refuses a session another process owns, without touching it, and '
        'opens it once that process is gone', () async {
      final runsDir = p.join(await tempDir(), 'runs');
      final owner = await Process.start(Platform.resolvedExecutable, [
        'run',
        p.join('test', 'fixtures', 'own_session.dart'),
        runsDir,
      ]);
      addTearDown(() => owner.kill(ProcessSignal.sigkill));
      owner.stderr.drain<void>().ignore();
      final id = await owner.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first;
      final session = only(runsDir, 'review-[0-9T-]{19}-($id)');
      final log = p.join(session.path, 'log.jsonl');
      // The owner is writing an event.
      File(log).writeAsStringSync('{"time":', mode: FileMode.append);
      final written = read(log);

      await expectLater(
        FsStore(runsDir).openSession(id),
        throwsA(
          isA<SessionBusyException>()
              .having((e) => e.sessionId, 'sessionId', id)
              .having(
                (e) => '$e',
                'toString',
                contains('another process owns the session $id'),
              ),
        ),
      );
      expect(read(log), written);
      // Listing unfinished sessions takes no lock.
      expect(await FsStore(runsDir).unfinishedSessions('review'), [id]);

      // The system drops the lock of a process that dies.
      owner.kill(ProcessSignal.sigkill);
      await owner.exitCode;
      final opened = await FsStore(runsDir).openSession(id);
      expect(opened?.session.id, id);
      expect(read(log), endsWith('"event":"session-started","code":null}\n'));
    });

    test('refuses a session this process owns already, and keeps owning it, '
        'until it lets it go', () async {
      final runsDir = p.join(await tempDir(), 'runs');
      final store = FsStore(runsDir);
      final created = await store.createSession(
        workflow: 'review',
        graph: null,
        input: null,
        code: null,
      );
      final id = created.session.id;

      await expectLater(
        store.openSession(id),
        throwsA(
          isA<SessionBusyException>().having(
            (e) => e.sessionId,
            'sessionId',
            id,
          ),
        ),
      );
      expect(await ownerCheck(runsDir, id), 'busy');

      await created.release();
      final opened = (await FsStore(runsDir).openSession(id))!;
      await expectLater(
        FsStore(runsDir).openSession(id),
        throwsA(isA<SessionBusyException>()),
      );
      expect(await ownerCheck(runsDir, id), 'busy');

      await opened.release();
      expect(await ownerCheck(runsDir, id), 'opened');
    });

    test('cuts an incomplete last line off the journal, so new events append '
        'cleanly', () async {
      final created = await newSession();
      final step = await newStep(created);
      final started = StepStarted(
        time: DateTime.utc(2026, 10, 3, 10, 1),
        stepId: step.id,
      );
      await created.appendEvent(started);
      final complete = read(journal(created));
      File(journal(created)).writeAsStringSync(
        '{"time":"2026-10-03T10:02:00.000Z","event":"step-fini',
        mode: FileMode.append,
      );
      await created.release();

      final opened = (await FsStore(p.dirname(created.dir))
          .openSession(created.session.id))!;

      expect(read(journal(created)), complete);
      final finished = StepFinished(
        time: DateTime.utc(2026, 10, 3, 10, 3),
        stepId: step.id,
        outputId: null,
      );
      await opened.appendEvent(finished);
      expect(await opened.events(), [isA<SessionStarted>(), started, finished]);
      expect(read(journal(created)), '$complete${_line(finished)}');
    });
  });

  group('unfinishedSessions', () {
    test('lists the sessions of the workflow with no last event, newest '
        'first', () async {
      final runsDir = p.join(await tempDir(), 'runs');
      // A minute between sessions, so that each has its own second.
      final store = FsStore(
        runsDir,
        clock: tickingClock(tick: const Duration(minutes: 1)),
      );
      Future<SessionHandle> create(String workflow) => store.createSession(
        workflow: workflow,
        graph: null,
        input: null,
        code: code,
      );
      final oldest = await create('review');
      final finished = await create('review');
      final otherWorkflow = await create('review-x');
      final failed = await create('review');
      final newest = await create('review');
      final resumed = await create('review');
      final later = DateTime.utc(2026, 10, 4);
      await finished.appendEvent(SessionFinished(time: later, outputId: null));
      await failed.appendEvent(
        SessionFailed(time: later, error: 'boom', stack: ''),
      );
      await resumed.appendEvent(
        SessionResumed(time: later, code: code, graphId: null),
      );

      expect(await store.unfinishedSessions('review'), [
        resumed.session.id,
        newest.session.id,
        oldest.session.id,
      ]);
      expect(await store.unfinishedSessions('review-x'), [
        otherWorkflow.session.id,
      ]);
      expect(await store.unfinishedSessions('publish'), isEmpty);
    });

    test('orders sessions created within one second by their '
        'session-started', () async {
      final runsDir = p.join(await tempDir(), 'runs');
      final store = FsStore(
        runsDir,
        clock: tickingClock(tick: const Duration(milliseconds: 1)),
      );
      final ids = [
        for (var i = 0; i < 5; i++)
          (await store.createSession(
            workflow: 'review',
            graph: null,
            input: null,
            code: null,
          )).session.id,
      ];

      expect(await store.unfinishedSessions('review'), ids.reversed);
    });

    test('takes a session whose last event is still being written as '
        'unfinished', () async {
      final handle = await newSession();
      File(journal(handle)).writeAsStringSync(
        '{"time":"2026-10-04T00:00:00.000Z","event":"session-finished",',
        mode: FileMode.append,
      );

      expect(
        await FsStore(p.dirname(handle.dir)).unfinishedSessions('review'),
        [handle.session.id],
      );
    });

    test('skips sessions it cannot read', () async {
      final runsDir = p.join(await tempDir(), 'runs');
      final store = FsStore(
        runsDir,
        clock: tickingClock(tick: const Duration(minutes: 1)),
      );
      Future<SessionHandle> create() => store.createSession(
        workflow: 'review',
        graph: null,
        input: null,
        code: null,
      );
      final good = await create();
      final noSessionJson = await create();
      final brokenSessionJson = await create();
      final noJournal = await create();
      final corruptJournal = await create();
      File(p.join(noSessionJson.dir, 'session.json')).deleteSync();
      File(p.join(brokenSessionJson.dir, 'session.json'))
          .writeAsStringSync('{"id": 1}\n');
      File(journal(noJournal)).deleteSync();
      File(journal(corruptJournal))
          .writeAsStringSync('not json\n', mode: FileMode.append);
      // A session being built.
      Directory(p.join(runsDir, '.tmp-${newId()}')).createSync();

      expect(await store.unfinishedSessions('review'), [good.session.id]);
    });

    test('is empty when there is no runs directory', () async {
      final store = FsStore(p.join(await tempDir(), 'runs'));

      expect(await store.unfinishedSessions('review'), isEmpty);
    });
  });
}

/// The line [event] takes in a journal.
String _line(Event event) => '${jsonEncode(event.toJson())}\n';

/// A value that, when it is written as JSON, notes what [look] sees.
final class _Probe {
  _Probe(this.look);

  final List<String> Function() look;

  final List<List<String>> seen = [];

  Object? toJson() {
    seen.add(look());
    return 'probe';
  }
}
