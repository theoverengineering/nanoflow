import 'dart:convert';
import 'dart:io';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_reader/nanoflow_reader.dart';
import 'package:nanoflow_reader/src/fs_reader.dart' show followRuns;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support.dart';

void main() {
  group('changes', () {
    test('gives everything on disk: the session, its runs, steps, events and '
        'documents', () async {
      final runsDir = await newRunsDir();
      final fixture = ReadmeSession.write(runsDir);

      final feed = Feed(runsDir);
      await feed.settle();

      expect(feed.changes, unorderedEquals(fixture.changes));
      expect(feed.errors, isEmpty);
      expect(feed.changes.first, SessionAdded(fixture.session));
      for (final (run, events) in [
        (fixture.parent, fixture.parentEvents),
        (fixture.child, fixture.childEvents),
      ]) {
        final given = [
          for (final change in feed.changes)
            if (change case EventAdded(event: KnownEvent(:final runId))
                when runId == run.id)
              change,
        ];
        expect(given, [for (final event in events) EventAdded(event)]);
        expect(
          feed.changes.indexOf(RunAdded(run)),
          lessThan(feed.changes.indexOf(given.first)),
        );
      }
    });

    test('gives an event appended later, once', () async {
      final runsDir = await newRunsDir();
      final fixture = ReadmeSession.write(runsDir);
      final feed = Feed(runsDir);
      await feed.settle();
      final mark = feed.changes.length;

      final failed = RunFailed(
        runId: fixture.child.id,
        time: at(9),
        stepId: fixture.publishStep.id,
        error: 'exited with code 1',
      );
      append(fixture.childDir, line(failed));
      await feed.settle();
      await feed.settle();

      expect(feed.since(mark), [EventAdded(failed)]);
    });

    test('gives a half-written line only once it is complete', () async {
      final runsDir = await newRunsDir();
      final fixture = ReadmeSession.write(runsDir);
      final feed = Feed(runsDir);
      await feed.settle();
      final mark = feed.changes.length;
      final finished = RunFinished(runId: fixture.child.id, time: at(9));
      final text = line(finished);

      append(fixture.childDir, text.substring(0, 20));
      await feed.settle();
      expect(feed.since(mark), isEmpty);

      append(fixture.childDir, text.substring(20));
      await feed.settle();
      expect(feed.since(mark), [EventAdded(finished)]);
    });

    test('gives a complete line that is not an event as log-corrupted, with '
        'its number and text, and reads on', () async {
      final runsDir = await newRunsDir();
      final fixture = ReadmeSession.write(runsDir);
      final feed = Feed(runsDir);
      await feed.settle();
      final mark = feed.changes.length;
      final runId = fixture.child.id;
      final finished = RunFinished(runId: runId, time: at(9));
      final noTime = '{"runId":"$runId","event":"run-finished"}';

      append(fixture.childDir, 'not json\n[1]\n$noTime\n\n');
      appendBytes(p.join(fixture.childDir, eventsFileName), [0xff, 0x0a]);
      append(fixture.childDir, line(finished));
      await feed.settle();

      // The journal holds run-started and step-started before these.
      expect(feed.since(mark), [
        LogCorrupted(runId: runId, line: 3, text: 'not json'),
        LogCorrupted(runId: runId, line: 4, text: '[1]'),
        LogCorrupted(runId: runId, line: 5, text: noTime),
        LogCorrupted(runId: runId, line: 6, text: ''),
        LogCorrupted(runId: runId, line: 7, text: '\uFFFD'),
        EventAdded(finished),
      ]);
    });

    test('gives an event it does not know as an UnknownEvent', () async {
      final runsDir = await newRunsDir();
      final fixture = ReadmeSession.write(runsDir);
      final feed = Feed(runsDir);
      await feed.settle();
      final mark = feed.changes.length;
      final runId = fixture.child.id;
      final approved = {
        'runId': runId,
        'time': '2026-09-20T14:03:20.470Z',
        'event': 'human-approved',
        'by': 'anna',
      };
      final noStep = {
        'runId': runId,
        'time': '2026-09-20T14:03:21.470Z',
        'event': 'step-started',
      };

      append(fixture.childDir, '${jsonEncode(approved)}\n');
      append(fixture.childDir, '${jsonEncode(noStep)}\n');
      await feed.settle();

      expect(feed.since(mark), [
        EventAdded(UnknownEvent(approved)),
        EventAdded(UnknownEvent(noStep)),
      ]);
    });

    test('reads on without giving anything twice after --resume cuts off an '
        'incomplete last line', () async {
      final runsDir = await newRunsDir();
      final session = Session(id: newId(), graph: graph);
      final sessionDir = writeSession(runsDir, session);
      final run = Run(id: newId(), sessionId: session.id, parentId: null);
      final started = RunStarted(runId: run.id, time: at(0), node: 'collect');
      final runDir = writeRun(
        sessionDir,
        run,
        createdAt: at(0),
        events: [started],
      );
      final journal = p.join(runDir, eventsFileName);
      append(runDir, '{"runId":"${run.id}","time":');
      final feed = Feed(runsDir);
      await feed.settle();
      expect(feed.changes, [
        SessionAdded(session),
        RunAdded(run),
        EventAdded(started),
      ]);
      final mark = feed.changes.length;

      truncate(journal, line(started).length);
      final stepStarted = StepStarted(
        runId: run.id,
        time: at(5),
        stepId: newId(),
        node: 'collect',
      );
      append(runDir, '${line(stepStarted)}oops\n');
      await feed.settle();

      expect(feed.since(mark), [
        EventAdded(stepStarted),
        LogCorrupted(runId: run.id, line: 3, text: 'oops'),
      ]);
    });

    test('gives step-changed once step.json gets the outputId of its '
        'step-finished', () async {
      final runsDir = await newRunsDir();
      final fixture = ReadmeSession.write(runsDir);
      final feed = Feed(runsDir);
      await feed.settle();
      final mark = feed.changes.length;
      final output = Document(
        id: newId(),
        sessionId: fixture.session.id,
        value: 'published',
      );
      final finished = StepFinished(
        runId: fixture.child.id,
        time: at(9),
        stepId: fixture.publishStep.id,
        exitCode: 0,
        outputId: output.id,
      );

      // The engine's order (D5): document, step-finished, step.json.
      writeDocument(fixture.sessionDir, output);
      append(fixture.childDir, line(finished));
      await feed.settle();
      expect(
        feed.since(mark),
        unorderedEquals([
          DocumentAdded(sessionId: fixture.session.id, documentId: output.id),
          EventAdded(finished),
        ]),
      );
      final changedMark = feed.changes.length;

      final published = fixture.publishStep.withOutput(output.id);
      rewriteStep(fixture.publishDir, published);
      await feed.next<StepChanged>();
      await feed.settle();
      await feed.settle();

      expect(feed.since(changedMark), [StepChanged(published)]);
    });

    test('gives sessions, runs, steps and documents as they appear', () async {
      final runsDir = await newRunsDir();
      Directory(runsDir).createSync();
      final feed = Feed(runsDir);
      await feed.settle();
      expect(feed.changes, isEmpty);

      final session = Session(id: newId(), graph: graph);
      final sessionDir = writeSession(runsDir, session);
      await feed.settle();
      expect(feed.since(0), [SessionAdded(session)]);

      final run = Run(id: newId(), sessionId: session.id, parentId: null);
      final first = newStep(run.id);
      final started = RunStarted(runId: run.id, time: at(1), node: 'collect');
      final runDir = writeRun(
        sessionDir,
        run,
        createdAt: at(1),
        events: [started],
      );
      writeStep(runDir, first, node: 'collect', startedAt: at(1));
      await feed.settle();
      // A step may come before or after the event that starts it.
      expect(feed.since(1).first, RunAdded(run));
      expect(
        feed.since(1),
        unorderedEquals([RunAdded(run), StepAdded(first), EventAdded(started)]),
      );

      final second = newStep(run.id);
      final stepStarted = StepStarted(
        runId: run.id,
        time: at(2),
        stepId: second.id,
        node: 'is-empty',
      );
      writeStep(runDir, second, node: 'is-empty', startedAt: at(2));
      append(runDir, line(stepStarted));
      await feed.settle();
      expect(
        feed.since(4),
        unorderedEquals([StepAdded(second), EventAdded(stepStarted)]),
      );

      final document = Document(id: newId(), sessionId: session.id, value: 1);
      writeDocument(sessionDir, document);
      await feed.settle();
      expect(feed.since(6), [
        DocumentAdded(sessionId: session.id, documentId: document.id),
      ]);
      expect(feed.errors, isEmpty);
    });

    test('ignores sessions of other graphs and every name starting with a '
        'dot', () async {
      final runsDir = await newRunsDir();
      // Another graph whose name starts with this one's.
      ReadmeSession.write(runsDir, graphName: 'review-x');
      final session = Session(id: newId(), graph: graph);
      final sessionDir = writeSession(runsDir, session);
      final run = Run(id: newId(), sessionId: session.id, parentId: null);
      final runDir = writeRun(sessionDir, run, createdAt: at(1));
      // A session, a run, a step and a document being built.
      writeJson(
        p.join(building(runsDir), sessionFileName),
        Session(id: newId(), graph: graph).toJson(),
      );
      writeJson(
        p.join(building(sessionDir), runFileName),
        Run(id: newId(), sessionId: session.id, parentId: null).toJson(),
      );
      writeJson(
        p.join(building(p.join(runDir, stepsDirName)), stepFileName),
        newStep(run.id).toJson(),
      );
      final hidden = Document(id: newId(), sessionId: session.id, value: 1);
      File(p.join(sessionDir, documentsDirName, '.${hidden.id}.json.tmp-1'))
          .writeAsStringSync(jsonEncode(hidden.toJson()));
      File(p.join(sessionDir, documentsDirName, '.${hidden.id}.json'))
          .writeAsStringSync(jsonEncode(hidden.toJson()));

      final feed = Feed(runsDir);
      // Sessions of review-x sort after the marker of the first settle.
      await feed.settle();
      await feed.settle();

      expect(feed.changes, [SessionAdded(session), RunAdded(run)]);
      expect(feed.errors, isEmpty);
    });

    test('starts giving changes once runsDir is created', () async {
      final runsDir = await newRunsDir();
      final feed = Feed(runsDir);
      // Some polls find no runsDir; the test holds however many there are.
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final fixture = ReadmeSession.write(runsDir);
      await feed.settle();

      expect(feed.changes, unorderedEquals(fixture.changes));
      expect(feed.errors, isEmpty);
    });

    test('follows file system events without waiting for the poll', () async {
      final runsDir = await newRunsDir();
      final fixture = ReadmeSession.write(runsDir);
      final feed = Feed(runsDir, pollInterval: const Duration(hours: 1));
      await feed.next<DocumentAdded>();

      final finished = RunFinished(runId: fixture.child.id, time: at(9));
      append(fixture.childDir, line(finished));

      await feed.next<EventAdded>((change) => change.event == finished);
    });

    test('gives a file that is not its model as an error, once, and reads '
        'the rest', () async {
      final runsDir = await newRunsDir();
      final session = Session(id: newId(), graph: graph);
      final sessionDir = writeSession(runsDir, session);
      final good = Run(id: newId(), sessionId: session.id, parentId: null);
      writeRun(sessionDir, good, createdAt: at(1));
      final broken = Run(id: newId(), sessionId: session.id, parentId: null);
      final brokenFile = p.join(
        writeRun(sessionDir, broken, createdAt: at(2)),
        runFileName,
      );
      writeJson(brokenFile, {'id': broken.id});

      final feed = Feed(runsDir);
      await feed.settle();
      await feed.settle();

      expect(feed.changes, [SessionAdded(session), RunAdded(good)]);
      expect(feed.errors, [
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          '$brokenFile: sessionId: missing',
        ),
      ]);

      writeJson(brokenFile, broken.toJson());
      await feed.settle();
      expect(feed.changes.last, RunAdded(broken));
      expect(feed.errors, hasLength(1));
    });

    test(
      'gives a file it cannot read as an error, once, and reads the rest',
      () async {
        final runsDir = await newRunsDir();
        final session = Session(id: newId(), graph: graph);
        final sessionDir = writeSession(runsDir, session);
        final good = Run(id: newId(), sessionId: session.id, parentId: null);
        writeRun(sessionDir, good, createdAt: at(1));
        final locked = Run(id: newId(), sessionId: session.id, parentId: null);
        final lockedFile = p.join(
          writeRun(sessionDir, locked, createdAt: at(2)),
          runFileName,
        );
        Process.runSync('chmod', ['000', lockedFile]);

        final feed = Feed(runsDir);
        await feed.settle();
        await feed.settle();

        expect(feed.changes, [SessionAdded(session), RunAdded(good)]);
        expect(feed.errors, [
          isA<FileSystemException>().having((e) => e.path, 'path', lockedFile),
        ]);

        Process.runSync('chmod', ['644', lockedFile]);
        await feed.settle();
        expect(feed.changes.last, RunAdded(locked));
        expect(feed.errors, hasLength(1));
      },
      skip: skipAsRoot,
    );

    test('does not scan when a command writes its log', () async {
      final runsDir = await newRunsDir();
      final fixture = ReadmeSession.write(runsDir);
      final logFile = p.join(fixture.publishDir, logFileName);
      final marker = p.join(runsDir, 'marker');
      // The watcher also reports what changed just before it started: let
      // that be long enough ago.
      await Future<void>.delayed(const Duration(milliseconds: 500));
      // For each scan, whether the marker was there.
      final found = <bool>[];
      final scans = followRuns<void>(
        runsDir,
        const Duration(hours: 1),
        (out) async => found.add(File(marker).existsSync()),
      );
      final subscription = scans.listen((_) {});
      addTearDown(subscription.cancel);
      await eventually(() => found.isNotEmpty);

      for (var i = 0; i < 50; i++) {
        appendBytes(logFile, utf8.encode('line $i\n'));
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      File(marker).writeAsStringSync('');
      await eventually(() => found.contains(true));

      // Only the first scan, then the one the marker made.
      expect(found.takeWhile((there) => !there), [false]);
    });

    test('gives the newest session first', () async {
      final runsDir = await newRunsDir();
      final older = Session(id: newId(), graph: graph);
      final newer = Session(id: newId(), graph: graph);
      writeSession(runsDir, older, createdAt: at(0));
      writeSession(runsDir, newer, createdAt: at(60));

      final feed = Feed(runsDir);
      await feed.settle();

      expect(feed.changes, [SessionAdded(newer), SessionAdded(older)]);
    });

    test('reads a run that has ended once more, then no more: nothing is '
        'written to it after its last event', () async {
      final runsDir = await newRunsDir();
      final session = Session(id: newId(), graph: graph);
      final sessionDir = writeSession(runsDir, session);
      final run = Run(id: newId(), sessionId: session.id, parentId: null);
      final step = newStep(run.id);
      final runDir = writeRun(
        sessionDir,
        run,
        createdAt: at(0),
        events: [
          RunStarted(runId: run.id, time: at(0), node: 'collect'),
          StepStarted(
            runId: run.id,
            time: at(1),
            stepId: step.id,
            node: 'collect',
          ),
          StepFinished(
            runId: run.id,
            time: at(2),
            stepId: step.id,
            exitCode: 0,
            outputId: null,
          ),
          RunFinished(runId: run.id, time: at(3)),
        ],
      );
      final feed = Feed(runsDir);
      await feed.next<EventAdded>((change) => change.event is RunFinished);

      // As if the pass that read the last event had listed the steps just
      // before the engine put the step in place.
      writeStep(runDir, step, node: 'collect', startedAt: at(1));
      await feed.next<StepAdded>();
      await feed.settle();
      await feed.settle();
      final mark = feed.changes.length;

      append(runDir, line(RunFinished(runId: run.id, time: at(4))));
      writeStep(runDir, newStep(run.id), node: 'collect', startedAt: at(4));
      await feed.settle();
      await feed.settle();

      expect(feed.since(mark), isEmpty);
    });

    test('reads a session whose runs have all ended until it has found what '
        'their split made, then no more', () async {
      final runsDir = await newRunsDir();
      final session = Session(id: newId(), graph: graph);
      final sessionDir = writeSession(runsDir, session);
      final parent = Run(id: newId(), sessionId: session.id, parentId: null);
      writeRun(
        sessionDir,
        parent,
        createdAt: at(0),
        events: [
          RunStarted(runId: parent.id, time: at(0), node: 'collect'),
          RunSplit(runId: parent.id, time: at(1)),
        ],
      );
      final feed = Feed(runsDir);
      await feed.next<EventAdded>((change) => change.event is RunSplit);

      // As if the pass that read run-split had listed the runs just before
      // the engine put the child in place.
      final child = Run(
        id: newId(),
        sessionId: session.id,
        parentId: parent.id,
      );
      writeRun(
        sessionDir,
        child,
        createdAt: at(1),
        events: [
          RunStarted(runId: child.id, time: at(1), node: 'publish'),
          RunFailed(
            runId: child.id,
            time: at(2),
            stepId: newId(),
            error: 'exited with code 1',
          ),
        ],
      );
      await feed.next<EventAdded>((change) => change.event is RunFailed);
      for (var i = 0; i < 4; i++) {
        await feed.settle();
      }
      final mark = feed.changes.length;

      writeRun(
        sessionDir,
        Run(id: newId(), sessionId: session.id, parentId: parent.id),
        createdAt: at(3),
      );
      writeDocument(
        sessionDir,
        Document(id: newId(), sessionId: session.id, value: 1),
      );
      await feed.settle();
      await feed.settle();

      expect(feed.since(mark), isEmpty);
    });

    test('is a single-subscription stream', () async {
      final reader = FsReader(runsDir: await newRunsDir(), graphName: 'review');
      final subscription = reader.changes().listen((_) {});
      addTearDown(subscription.cancel);

      expect(() => reader.changes().listen((_) {}), throwsStateError);
    });
  });

  group('data on request', () {
    test('sessionGraph gives the graph the session holds', () async {
      final runsDir = await newRunsDir();
      final fixture = ReadmeSession.write(runsDir);
      final feed = Feed(runsDir);
      await feed.settle();

      expect(await feed.reader.sessionGraph(fixture.session.id), graph);
    });

    test('documentValue gives the value of a document', () async {
      final runsDir = await newRunsDir();
      final fixture = ReadmeSession.write(runsDir);
      final empty = Document(
        id: newId(),
        sessionId: fixture.session.id,
        value: null,
      );
      writeDocument(fixture.sessionDir, empty);
      final feed = Feed(runsDir);
      await feed.settle();

      expect(
        await feed.reader.documentValue(fixture.session.id, fixture.input.id),
        {'branch': 'main'},
      );
      expect(
        await feed.reader.documentValue(fixture.session.id, fixture.outcome.id),
        true,
      );
      expect(
        await feed.reader.documentValue(fixture.session.id, empty.id),
        isNull,
      );
    });

    test('finds a session, its documents and logs before the feed gives '
        'them', () async {
      final runsDir = await newRunsDir();
      final fixture = ReadmeSession.write(runsDir);
      File(p.join(fixture.publishDir, logFileName))
          .writeAsStringSync('publishing\n');
      final reader = FsReader(runsDir: runsDir, graphName: 'review');

      expect(await reader.sessionGraph(fixture.session.id), graph);
      expect(await reader.documentValue(fixture.session.id, fixture.input.id), {
        'branch': 'main',
      });
      final log = LogText(
        reader.stepLog(
          fixture.session.id,
          fixture.child.id,
          fixture.publishStep.id,
        ),
      );
      expect(await log.untilLength('publishing\n'), 'publishing\n');
    });

    test('throws for a session the graph does not have', () async {
      final runsDir = await newRunsDir();
      final other = ReadmeSession.write(runsDir, graphName: 'review-x');
      final reader = FsReader(runsDir: runsDir, graphName: 'review');

      await expectLater(
        reader.sessionGraph(other.session.id),
        throwsArgumentError,
      );
      await expectLater(
        reader.documentValue(newId(), other.input.id),
        throwsArgumentError,
      );
    });
  });

  group('stepLog', () {
    test(
      'gives the text there is, then what is appended, decoding a '
      'character split between writes and bytes that are not UTF-8',
      () async {
        final runsDir = await newRunsDir();
        final fixture = ReadmeSession.write(runsDir);
        final logFile = p.join(fixture.publishDir, logFileName);
        File(logFile).writeAsStringSync('hello\n');
        final feed = Feed(runsDir);
        await feed.settle();

        final log = LogText(
          feed.reader.stepLog(
            fixture.session.id,
            fixture.child.id,
            fixture.publishStep.id,
          ),
        );
        expect(await log.untilLength('hello\n'), 'hello\n');

        // 'é' is C3 A9 in UTF-8.
        appendBytes(logFile, [...utf8.encode('a'), 0xc3]);
        expect(await log.untilLength('hello\na'), 'hello\na');
        appendBytes(logFile, [0xa9, ...utf8.encode('b\n')]);
        expect(await log.untilLength('hello\naéb\n'), 'hello\naéb\n');
        // A command may write bytes that are not UTF-8.
        appendBytes(logFile, [0xff, ...utf8.encode('\n')]);
        expect(
          await log.untilLength('hello\naéb\n\uFFFD\n'),
          'hello\naéb\n\uFFFD\n',
        );
        expect(log.chunks, ['hello\n', 'a', 'éb\n', '\uFFFD\n']);
      },
    );

    test('gives nothing until command.log appears', () async {
      final runsDir = await newRunsDir();
      final fixture = ReadmeSession.write(runsDir);
      final feed = Feed(runsDir);
      await feed.settle();
      final log = LogText(
        feed.reader.stepLog(
          fixture.session.id,
          fixture.child.id,
          fixture.publishStep.id,
        ),
      );
      // Some polls find no command.log; the test holds however many there
      // are.
      await Future<void>.delayed(const Duration(milliseconds: 100));

      appendBytes(p.join(fixture.publishDir, logFileName), utf8.encode('up\n'));

      expect(await log.untilLength('up\n'), 'up\n');
      expect(log.chunks, ['up\n']);
    });

    test('gives an error for a step the run does not have', () async {
      final runsDir = await newRunsDir();
      final fixture = ReadmeSession.write(runsDir);
      final reader = FsReader(runsDir: runsDir, graphName: 'review');

      await expectLater(
        reader.stepLog(fixture.session.id, fixture.child.id, newId()),
        emitsInOrder([emitsError(isArgumentError), emitsDone]),
      );
      await expectLater(
        reader.stepLog(fixture.session.id, newId(), fixture.publishStep.id),
        emitsInOrder([emitsError(isArgumentError), emitsDone]),
      );
    });
  });

  group('paths', () {
    test('are null until the feed has given the entity, then point at it on '
        'disk', () async {
      final runsDir = await newRunsDir();
      final fixture = ReadmeSession.write(runsDir);
      final reader = FsReader(
        runsDir: runsDir,
        graphName: 'review',
        pollInterval: const Duration(milliseconds: 20),
      );
      final sessionId = fixture.session.id;
      final unknown = newId();

      expect(reader.sessionPath(sessionId), isNull);
      expect(reader.runPath(fixture.child.id), isNull);
      expect(reader.stepPath(fixture.publishStep.id), isNull);
      expect(reader.logPath(fixture.publishStep.id), isNull);
      expect(reader.documentPath(sessionId, fixture.input.id), isNull);

      await Feed.of(reader).settle();

      expect(reader.sessionPath(sessionId), fixture.sessionDir);
      expect(reader.runPath(fixture.parent.id), fixture.parentDir);
      expect(reader.runPath(fixture.child.id), fixture.childDir);
      expect(reader.stepPath(fixture.publishStep.id), fixture.publishDir);
      expect(
        reader.logPath(fixture.publishStep.id),
        p.join(fixture.publishDir, 'command.log'),
      );
      expect(
        reader.documentPath(sessionId, fixture.input.id),
        p.join(fixture.sessionDir, 'documents', '${fixture.input.id}.json'),
      );
      expect(reader.sessionPath(unknown), isNull);
      expect(reader.runPath(unknown), isNull);
      expect(reader.stepPath(unknown), isNull);
      expect(reader.logPath(unknown), isNull);
      expect(reader.documentPath(sessionId, unknown), isNull);
      expect(reader.documentPath(unknown, fixture.input.id), isNull);
    });
  });
}

/// A directory `.tmp-<id>` in [parent], like the ones the store builds
/// sessions, runs and steps in.
String building(String parent) =>
    (Directory(p.join(parent, '.tmp-${newId()}'))..createSync()).path;

/// The README's example session on disk: the input, collect, is-empty, a
/// split into a child run whose publish step is running.
final class ReadmeSession {
  ReadmeSession._(this.runsDir, this.graphName);

  /// Writes the session to [runsDir] as a session of [graphName].
  factory ReadmeSession.write(String runsDir, {String graphName = 'review'}) =>
      ReadmeSession._(runsDir, graphName).._write();

  final String runsDir;
  final String graphName;

  final Session session = Session(id: newId(), graph: graph);
  late final String sessionDir;

  late final Document input = _document({'branch': 'main'});
  late final Document collected = _document({'files': 3});
  late final Document outcome = _document(true);

  late final Run parent = Run(
    id: newId(),
    sessionId: session.id,
    parentId: null,
  );
  late final String parentDir;
  late final Step collectStep = Step(
    id: newId(),
    runId: parent.id,
    inputId: input.id,
    outputId: collected.id,
    log: logFileName,
  );
  late final Step isEmptyStep = Step(
    id: newId(),
    runId: parent.id,
    inputId: collected.id,
    outputId: outcome.id,
    log: logFileName,
  );
  late final List<Event> parentEvents = [
    RunStarted(runId: parent.id, time: at(0), node: 'collect'),
    StepStarted(
      runId: parent.id,
      time: at(1),
      stepId: collectStep.id,
      node: 'collect',
    ),
    StepFinished(
      runId: parent.id,
      time: at(2),
      stepId: collectStep.id,
      exitCode: 0,
      outputId: collected.id,
    ),
    StepStarted(
      runId: parent.id,
      time: at(3),
      stepId: isEmptyStep.id,
      node: 'is-empty',
    ),
    StepFinished(
      runId: parent.id,
      time: at(4),
      stepId: isEmptyStep.id,
      exitCode: 0,
      outputId: outcome.id,
    ),
    RunSplit(runId: parent.id, time: at(5)),
  ];

  late final Run child = Run(
    id: newId(),
    sessionId: session.id,
    parentId: parent.id,
  );
  late final String childDir;
  late final Step publishStep = newStep(child.id, inputId: collected.id);
  late final String publishDir;
  late final List<Event> childEvents = [
    RunStarted(runId: child.id, time: at(5), node: 'publish'),
    StepStarted(
      runId: child.id,
      time: at(6),
      stepId: publishStep.id,
      node: 'publish',
    ),
  ];

  /// Everything the feed gives for the session.
  List<Change> get changes => [
    SessionAdded(session),
    RunAdded(parent),
    StepAdded(collectStep),
    StepAdded(isEmptyStep),
    for (final event in parentEvents) EventAdded(event),
    RunAdded(child),
    StepAdded(publishStep),
    for (final event in childEvents) EventAdded(event),
    for (final document in [input, collected, outcome])
      DocumentAdded(sessionId: session.id, documentId: document.id),
  ];

  Document _document(Object? value) =>
      Document(id: newId(), sessionId: session.id, value: value);

  void _write() {
    sessionDir = writeSession(runsDir, session, graphName: graphName);
    for (final document in [input, collected, outcome]) {
      writeDocument(sessionDir, document);
    }
    parentDir = writeRun(
      sessionDir,
      parent,
      createdAt: at(0),
      events: parentEvents,
    );
    writeStep(parentDir, collectStep, node: 'collect', startedAt: at(0));
    writeStep(parentDir, isEmptyStep, node: 'is-empty', startedAt: at(3));
    childDir = writeRun(
      sessionDir,
      child,
      createdAt: at(5),
      events: childEvents,
    );
    publishDir = writeStep(
      childDir,
      publishStep,
      node: 'publish',
      startedAt: at(5),
    );
  }
}
