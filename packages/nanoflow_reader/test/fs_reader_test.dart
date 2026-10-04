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
    test('gives everything on disk: the session, its effects, events and '
        'documents', () async {
      final runsDir = await newRunsDir();
      final fixture = SpecSession.write(runsDir);

      final feed = Feed(runsDir);
      await feed.settle();

      expect(feed.changes, unorderedEquals(fixture.changes));
      expect(feed.errors, isEmpty);
      expect(feed.changes.first, SessionAdded(fixture.session));
      expect(
        [
          for (final change in feed.changes)
            if (change is EventAdded) change,
        ],
        [
          for (final event in fixture.events)
            EventAdded(sessionId: fixture.session.id, event: event),
        ],
      );
    });

    test('gives an event appended later, once', () async {
      final runsDir = await newRunsDir();
      final fixture = SpecSession.write(runsDir);
      final feed = Feed(runsDir);
      await feed.settle();
      final mark = feed.changes.length;

      final failed = EffectFailed(
        time: at(9),
        effectId: fixture.publish.id,
        error: 'Exception: boom',
        stack: '#0 main\n',
      );
      append(fixture.sessionDir, line(failed));
      await feed.settle();
      await feed.settle();

      expect(feed.since(mark), [fixture.added(failed)]);
    });

    test('gives a half-written line only once it is complete', () async {
      final runsDir = await newRunsDir();
      final fixture = SpecSession.write(runsDir);
      final feed = Feed(runsDir);
      await feed.settle();
      final mark = feed.changes.length;
      final finished = SessionFinished(time: at(9), outputId: null);
      final text = line(finished);

      append(fixture.sessionDir, text.substring(0, 20));
      await feed.settle();
      expect(feed.since(mark), isEmpty);

      append(fixture.sessionDir, text.substring(20));
      await feed.settle();
      expect(feed.since(mark), [fixture.added(finished)]);
    });

    test('gives a complete line that is not an event as log-corrupted, once, '
        'with its number and text, and reads on', () async {
      final runsDir = await newRunsDir();
      final fixture = SpecSession.write(runsDir);
      final feed = Feed(runsDir);
      await feed.settle();
      final mark = feed.changes.length;
      final sessionId = fixture.session.id;
      final finished = SessionFinished(time: at(9), outputId: null);
      const noTime = '{"event":"session-finished","outputId":null}';
      const numberEvent = '{"time":"2026-10-03T10:00:09.482Z","event":7}';
      final first = fixture.events.length + 1;

      append(fixture.sessionDir, 'not json\n[1]\n$noTime\n$numberEvent\n\n');
      appendBytes(p.join(fixture.sessionDir, eventsFileName), [0xff, 0x0a]);
      append(fixture.sessionDir, line(finished));
      await feed.settle();
      await feed.settle();

      expect(feed.since(mark), [
        LogCorrupted(sessionId: sessionId, line: first, text: 'not json'),
        LogCorrupted(sessionId: sessionId, line: first + 1, text: '[1]'),
        LogCorrupted(sessionId: sessionId, line: first + 2, text: noTime),
        LogCorrupted(sessionId: sessionId, line: first + 3, text: numberEvent),
        LogCorrupted(sessionId: sessionId, line: first + 4, text: ''),
        LogCorrupted(sessionId: sessionId, line: first + 5, text: '�'),
        fixture.added(finished),
      ]);
    });

    test('gives an event it does not know as an UnknownEvent', () async {
      final runsDir = await newRunsDir();
      final fixture = SpecSession.write(runsDir);
      final feed = Feed(runsDir);
      await feed.settle();
      final mark = feed.changes.length;
      final approved = {
        'time': '2026-10-03T10:00:20.482Z',
        'event': 'human-approved',
        'by': 'anna',
      };
      final noEffect = {
        'time': '2026-10-03T10:00:21.482Z',
        'event': 'effect-started',
      };

      append(fixture.sessionDir, '${jsonEncode(approved)}\n');
      append(fixture.sessionDir, '${jsonEncode(noEffect)}\n');
      await feed.settle();

      expect(feed.since(mark), [
        fixture.added(UnknownEvent(approved)),
        fixture.added(UnknownEvent(noEffect)),
      ]);
    });

    test('reads on without giving anything twice after resume cuts off an '
        'incomplete last line', () async {
      final runsDir = await newRunsDir();
      final session = newSession();
      final started = SessionStarted(time: at(0), code: null);
      final sessionDir = writeSession(runsDir, session, events: [started]);
      final journal = p.join(sessionDir, eventsFileName);
      append(sessionDir, '{"time":');
      final feed = Feed(runsDir);
      await feed.settle();
      expect(feed.changes, [
        SessionAdded(session),
        EventAdded(sessionId: session.id, event: started),
        noOwner(session.id),
      ]);
      final mark = feed.changes.length;

      truncate(journal, line(started).length);
      final resumed = SessionResumed(time: at(5), code: null, graphId: null);
      append(sessionDir, '${line(resumed)}oops\n');
      await feed.settle();

      expect(feed.since(mark), [
        EventAdded(sessionId: session.id, event: resumed),
        LogCorrupted(sessionId: session.id, line: 3, text: 'oops'),
      ]);
    });

    test('gives effect-changed once effect.json gets the outputId of its '
        'effect-finished', () async {
      final runsDir = await newRunsDir();
      final fixture = SpecSession.write(runsDir);
      final feed = Feed(runsDir);
      await feed.settle();
      final mark = feed.changes.length;
      final output = Document(
        id: newId(),
        sessionId: fixture.session.id,
        value: 'published',
      );
      final finished = EffectFinished(
        time: at(9),
        effectId: fixture.publish.id,
        outputId: output.id,
      );

      // The order of D3: document, effect-finished, effect.json.
      writeDocument(fixture.sessionDir, output);
      append(fixture.sessionDir, line(finished));
      await feed.settle();
      expect(
        feed.since(mark),
        unorderedEquals([
          DocumentAdded(sessionId: fixture.session.id, documentId: output.id),
          fixture.added(finished),
        ]),
      );
      final changedMark = feed.changes.length;

      final published = fixture.publish.withOutput(output.id);
      rewriteEffect(fixture.publishDir, published);
      await feed.next<EffectChanged>();
      await feed.settle();
      await feed.settle();

      expect(feed.since(changedMark), [EffectChanged(published)]);
    });

    test(
      'gives effect-changed when an effect that runs again in its record gets '
      'another after, and then its new outputId',
      () async {
        final runsDir = await newRunsDir();
        final session = newSession();
        final first = Document(id: newId(), sessionId: session.id, value: 1);
        final collect = newEffect(session.id).withOutput(first.id);
        final sessionDir = writeSession(
          runsDir,
          session,
          events: [
            SessionStarted(time: at(0), code: 'sha256:a'),
            EffectStarted(time: at(1), effectId: collect.id),
            EffectFinished(
              time: at(2),
              effectId: collect.id,
              outputId: first.id,
            ),
            SessionResumed(time: at(3), code: 'sha256:b', graphId: null),
          ],
        );
        writeDocument(sessionDir, first);
        final collectDir = writeEffect(sessionDir, collect, startedAt: at(1));
        final feed = Feed(runsDir);
        await feed.settle();
        final mark = feed.changes.length;

        // The order of D3 for a rerun that follows another effect:
        // effect-started, then effect.json with the new after.
        final rerun = EffectStarted(time: at(4), effectId: collect.id);
        append(sessionDir, line(rerun));
        await feed.next<EventAdded>((change) => change.event == rerun);
        final moved = collect.withAfter('other#1@e3b0c44298fc1c14');
        rewriteEffect(collectDir, moved);
        await feed.next<EffectChanged>();
        await feed.settle();
        await feed.settle();
        expect(feed.since(mark), [
          EventAdded(sessionId: session.id, event: rerun),
          EffectChanged(moved),
        ]);
        final finishedMark = feed.changes.length;

        // Then document, effect-finished, effect.json with the new outputId.
        final second = Document(id: newId(), sessionId: session.id, value: 2);
        final finished = EffectFinished(
          time: at(5),
          effectId: collect.id,
          outputId: second.id,
        );
        writeDocument(sessionDir, second);
        append(sessionDir, line(finished));
        await feed.next<EventAdded>((change) => change.event == finished);
        final done = moved.withOutput(second.id);
        rewriteEffect(collectDir, done);
        await feed.next<EffectChanged>((change) => change.effect == done);
        await feed.settle();
        await feed.settle();
        expect(
          feed.since(finishedMark),
          unorderedEquals([
            EventAdded(sessionId: session.id, event: finished),
            DocumentAdded(sessionId: session.id, documentId: second.id),
            EffectChanged(done),
          ]),
        );
      },
    );

    test('gives a session, its effects, events and documents as they '
        'appear', () async {
      final runsDir = await newRunsDir();
      Directory(runsDir).createSync();
      final feed = Feed(runsDir);
      await feed.settle();
      expect(feed.changes, isEmpty);

      final session = newSession();
      final started = SessionStarted(time: at(0), code: null);
      final sessionDir = writeSession(runsDir, session, events: [started]);
      await feed.settle();
      expect(feed.since(0), [
        SessionAdded(session),
        EventAdded(sessionId: session.id, event: started),
        noOwner(session.id),
      ]);

      final effect = newEffect(session.id);
      final effectStarted = EffectStarted(time: at(1), effectId: effect.id);
      writeEffect(sessionDir, effect, startedAt: at(1));
      append(sessionDir, line(effectStarted));
      await feed.settle();
      // An effect may come before or after the event that starts it.
      expect(
        feed.since(3),
        unorderedEquals([
          EffectAdded(effect),
          EventAdded(sessionId: session.id, event: effectStarted),
        ]),
      );

      final document = Document(id: newId(), sessionId: session.id, value: 1);
      writeDocument(sessionDir, document);
      await feed.settle();
      expect(feed.since(5), [
        DocumentAdded(sessionId: session.id, documentId: document.id),
      ]);
      expect(feed.errors, isEmpty);
    });

    test('gives the sessions of every workflow and ignores every name '
        'starting with a dot and every other entry of runs', () async {
      final runsDir = await newRunsDir();
      final review = newSession();
      final apply = newSession(workflow: 'apply-x');
      final sessionDir = writeSession(runsDir, review);
      writeSession(runsDir, apply, createdAt: at(1));
      // A session, an effect and a document being built.
      writeJson(
        p.join(building(runsDir), sessionFileName),
        newSession().toJson(),
      );
      writeJson(
        p.join(building(p.join(sessionDir, effectsDirName)), effectFileName),
        newEffect(review.id).toJson(),
      );
      final hidden = Document(id: newId(), sessionId: review.id, value: 1);
      File(p.join(sessionDir, documentsDirName, '.${hidden.id}.json.tmp-1'))
          .writeAsStringSync(jsonEncode(hidden.toJson()));
      File(p.join(sessionDir, documentsDirName, '.${hidden.id}.json'))
          .writeAsStringSync(jsonEncode(hidden.toJson()));
      // Not session directories.
      Directory(p.join(runsDir, 'notes')).createSync();
      File(p.join(runsDir, 'README')).writeAsStringSync('');
      Directory(p.join(runsDir, '.${p.basename(sessionDir)}')).createSync();

      final feed = Feed(runsDir);
      await feed.settle();
      await feed.settle();

      expect(feed.changes, [
        SessionAdded(apply),
        noOwner(apply.id),
        SessionAdded(review),
        noOwner(review.id),
      ]);
      expect(feed.errors, isEmpty);
    });

    test('starts giving changes once runsDir is created', () async {
      final runsDir = await newRunsDir();
      final feed = Feed(runsDir);
      // Some polls find no runsDir; the test holds however many there are.
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final fixture = SpecSession.write(runsDir);
      await feed.settle();

      expect(feed.changes, unorderedEquals(fixture.changes));
      expect(feed.errors, isEmpty);
    });

    test('follows file system events without waiting for the poll', () async {
      final runsDir = await newRunsDir();
      final fixture = SpecSession.write(runsDir);
      final feed = Feed(runsDir, pollInterval: const Duration(hours: 1));
      await feed.next<DocumentAdded>();

      final finished = SessionFinished(time: at(9), outputId: null);
      append(fixture.sessionDir, line(finished));

      await feed.next<EventAdded>((change) => change.event == finished);
    });

    test('gives a file that is not its model as an error, once, and reads '
        'the rest', () async {
      final runsDir = await newRunsDir();
      final session = newSession();
      final sessionDir = writeSession(runsDir, session);
      final good = newEffect(session.id, name: 'good');
      writeEffect(sessionDir, good, startedAt: at(1));
      final broken = newEffect(session.id, name: 'broken');
      final brokenFile = p.join(
        writeEffect(sessionDir, broken, startedAt: at(2)),
        effectFileName,
      );
      writeJson(brokenFile, {'id': broken.id});

      final feed = Feed(runsDir);
      await feed.settle();
      await feed.settle();

      expect(feed.changes, [
        SessionAdded(session),
        EffectAdded(good),
        noOwner(session.id),
      ]);
      expect(feed.errors, [
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          '$brokenFile: sessionId: missing',
        ),
      ]);

      writeJson(brokenFile, broken.toJson());
      await feed.settle();
      expect(feed.changes.last, EffectAdded(broken));
      expect(feed.errors, hasLength(1));
    });

    test(
      'gives a file it cannot read as an error, once, and reads the rest',
      () async {
        final runsDir = await newRunsDir();
        final session = newSession();
        final sessionDir = writeSession(runsDir, session);
        final good = newEffect(session.id, name: 'good');
        writeEffect(sessionDir, good, startedAt: at(1));
        final locked = newEffect(session.id, name: 'locked');
        final lockedFile = p.join(
          writeEffect(sessionDir, locked, startedAt: at(2)),
          effectFileName,
        );
        Process.runSync('chmod', ['000', lockedFile]);

        final feed = Feed(runsDir);
        await feed.settle();
        await feed.settle();

        expect(feed.changes, [
          SessionAdded(session),
          EffectAdded(good),
          noOwner(session.id),
        ]);
        expect(feed.errors, [
          isA<FileSystemException>().having((e) => e.path, 'path', lockedFile),
        ]);

        Process.runSync('chmod', ['644', lockedFile]);
        await feed.settle();
        expect(feed.changes.last, EffectAdded(locked));
        expect(feed.errors, hasLength(1));
      },
      skip: skipAsRoot,
    );

    test('does not scan when an effect writes its log', () async {
      final runsDir = await newRunsDir();
      final fixture = SpecSession.write(runsDir);
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

    test('gives the newest session first, whatever its workflow', () async {
      final runsDir = await newRunsDir();
      final older = newSession(workflow: 'apply');
      final newer = newSession(workflow: 'review');
      final newest = newSession(workflow: 'audit');
      writeSession(runsDir, older, createdAt: at(0));
      writeSession(runsDir, newer, createdAt: at(60));
      writeSession(runsDir, newest, createdAt: at(120));

      final feed = Feed(runsDir);
      await feed.settle();

      expect(feed.changes, [
        SessionAdded(newest),
        noOwner(newest.id),
        SessionAdded(newer),
        noOwner(newer.id),
        SessionAdded(older),
        noOwner(older.id),
      ]);
    });

    test('reads a session that has ended once more, then no more: nothing '
        'is written to it after its last event', () async {
      final runsDir = await newRunsDir();
      final session = newSession();
      final effect = newEffect(session.id);
      final sessionDir = writeSession(
        runsDir,
        session,
        events: [
          SessionStarted(time: at(0), code: null),
          EffectStarted(time: at(1), effectId: effect.id),
          EffectFinished(time: at(2), effectId: effect.id, outputId: null),
          SessionFinished(time: at(3), outputId: null),
        ],
      );
      final feed = Feed(runsDir);
      await feed.next<EventAdded>((change) => change.event is SessionFinished);

      // As if the pass that read the last event had listed the effects just
      // before the effect was put in place.
      writeEffect(sessionDir, effect, startedAt: at(1));
      await feed.next<EffectAdded>();
      await feed.settle();
      await feed.settle();
      final mark = feed.changes.length;

      append(sessionDir, line(SessionFinished(time: at(4), outputId: null)));
      writeEffect(sessionDir, newEffect(session.id), startedAt: at(4));
      writeDocument(
        sessionDir,
        Document(id: newId(), sessionId: session.id, value: 1),
      );
      await feed.settle();
      await feed.settle();

      expect(feed.since(mark), isEmpty);
    });

    test('is a single-subscription stream', () async {
      final reader = FsReader(runsDir: await newRunsDir());
      final subscription = reader.changes().listen((_) {});
      addTearDown(subscription.cancel);

      expect(() => reader.changes().listen((_) {}), throwsStateError);
    });
  });

  group('data on request', () {
    test('documentValue gives the value of a document', () async {
      final runsDir = await newRunsDir();
      final fixture = SpecSession.write(runsDir);
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
        await feed.reader.documentValue(
          fixture.session.id,
          fixture.snapshot.id,
        ),
        graph,
      );
      expect(
        await feed.reader.documentValue(fixture.session.id, empty.id),
        isNull,
      );
    });

    test('finds a session, its documents and logs before the feed gives '
        'them', () async {
      final runsDir = await newRunsDir();
      final fixture = SpecSession.write(runsDir);
      File(p.join(fixture.publishDir, logFileName))
          .writeAsStringSync('publishing\n');
      final reader = FsReader(runsDir: runsDir);

      expect(await reader.documentValue(fixture.session.id, fixture.input.id), {
        'branch': 'main',
      });
      final log = LogText(
        reader.effectLog(fixture.session.id, fixture.publish.id),
      );
      expect(await log.untilLength('publishing\n'), 'publishing\n');
    });

    test('throws for a session runs does not have', () async {
      final runsDir = await newRunsDir();
      final fixture = SpecSession.write(runsDir);
      final reader = FsReader(runsDir: runsDir);

      await expectLater(
        reader.documentValue(newId(), fixture.input.id),
        throwsArgumentError,
      );
    });
  });

  group('effectLog', () {
    test(
      'gives the text there is, then what is appended, decoding a '
      'character split between writes and bytes that are not UTF-8',
      () async {
        final runsDir = await newRunsDir();
        final fixture = SpecSession.write(runsDir);
        final logFile = p.join(fixture.publishDir, logFileName);
        File(logFile).writeAsStringSync('hello\n');
        final feed = Feed(runsDir);
        await feed.settle();

        final log = LogText(
          feed.reader.effectLog(fixture.session.id, fixture.publish.id),
        );
        expect(await log.untilLength('hello\n'), 'hello\n');

        // 'é' is C3 A9 in UTF-8.
        appendBytes(logFile, [...utf8.encode('a'), 0xc3]);
        expect(await log.untilLength('hello\na'), 'hello\na');
        appendBytes(logFile, [0xa9, ...utf8.encode('b\n')]);
        expect(await log.untilLength('hello\naéb\n'), 'hello\naéb\n');
        // A program may write bytes that are not UTF-8.
        appendBytes(logFile, [0xff, ...utf8.encode('\n')]);
        expect(await log.untilLength('hello\naéb\n�\n'), 'hello\naéb\n�\n');
        expect(log.chunks, ['hello\n', 'a', 'éb\n', '�\n']);
      },
    );

    test('gives nothing until effect.log appears', () async {
      final runsDir = await newRunsDir();
      final fixture = SpecSession.write(runsDir);
      final feed = Feed(runsDir);
      await feed.settle();
      final log = LogText(
        feed.reader.effectLog(fixture.session.id, fixture.publish.id),
      );
      // Some polls find no effect.log; the test holds however many there are.
      await Future<void>.delayed(const Duration(milliseconds: 100));

      appendBytes(p.join(fixture.publishDir, logFileName), utf8.encode('up\n'));

      expect(await log.untilLength('up\n'), 'up\n');
      expect(log.chunks, ['up\n']);
    });

    test('gives an error for an effect the session does not have', () async {
      final runsDir = await newRunsDir();
      final fixture = SpecSession.write(runsDir);
      final reader = FsReader(runsDir: runsDir);

      await expectLater(
        reader.effectLog(fixture.session.id, newId()),
        emitsInOrder([emitsError(isArgumentError), emitsDone]),
      );
      await expectLater(
        reader.effectLog(newId(), fixture.publish.id),
        emitsInOrder([emitsError(isArgumentError), emitsDone]),
      );
    });
  });

  group('paths', () {
    test('are null until the feed has given the entity, then point at it on '
        'disk', () async {
      final runsDir = await newRunsDir();
      final fixture = SpecSession.write(runsDir);
      final reader = FsReader(
        runsDir: runsDir,
        pollInterval: const Duration(milliseconds: 20),
      );
      final sessionId = fixture.session.id;
      final unknown = newId();

      expect(reader.sessionPath(sessionId), isNull);
      expect(reader.effectPath(fixture.publish.id), isNull);
      expect(reader.logPath(fixture.publish.id), isNull);
      expect(reader.documentPath(sessionId, fixture.input.id), isNull);

      await Feed.of(reader).settle();

      expect(reader.sessionPath(sessionId), fixture.sessionDir);
      expect(reader.effectPath(fixture.publish.id), fixture.publishDir);
      expect(
        reader.logPath(fixture.publish.id),
        p.join(fixture.publishDir, 'effect.log'),
      );
      expect(
        reader.documentPath(sessionId, fixture.input.id),
        p.join(fixture.sessionDir, 'documents', '${fixture.input.id}.json'),
      );
      expect(reader.sessionPath(unknown), isNull);
      expect(reader.effectPath(unknown), isNull);
      expect(reader.logPath(unknown), isNull);
      expect(reader.documentPath(sessionId, unknown), isNull);
      expect(reader.documentPath(unknown, fixture.input.id), isNull);
    });
  });
}

/// A directory `.tmp-<id>` in [parent], like the ones the store builds
/// sessions and effects in.
String building(String parent) =>
    (Directory(p.join(parent, '.tmp-${newId()}'))..createSync()).path;

/// A session on disk with every kind of event but the last: `collect`
/// finished, `inspect` started, the process died, the session resumed on
/// other code, `inspect` started again and failed, and `publish` runs.
final class SpecSession {
  SpecSession._(this.runsDir);

  /// Writes the session to [runsDir].
  factory SpecSession.write(String runsDir) => SpecSession._(runsDir).._write();

  final String runsDir;

  late final Session session = Session(
    id: _sessionId,
    workflow: 'review',
    graph: graph,
    inputId: input.id,
  );
  final String _sessionId = newId();
  late final String sessionDir;

  late final Document input = _document({'branch': 'main'});
  late final Document collected = _document({'files': 3});
  late final Document snapshot = _document(graph);

  late final Effect collect = newEffect(
    session.id,
    name: 'collect',
  ).withOutput(collected.id);
  late final Effect inspect = newEffect(
    session.id,
    name: 'inspect',
    after: collect.key,
  );
  late final Effect publish = newEffect(
    session.id,
    name: 'publish',
    after: collect.key,
  );
  late final String publishDir;

  late final List<Event> events = [
    SessionStarted(time: at(0), code: 'sha256:a'),
    EffectStarted(time: at(1), effectId: collect.id),
    EffectFinished(time: at(2), effectId: collect.id, outputId: collected.id),
    EffectStarted(time: at(3), effectId: inspect.id),
    SessionResumed(time: at(4), code: 'sha256:b', graphId: snapshot.id),
    EffectStarted(time: at(5), effectId: inspect.id),
    EffectFailed(
      time: at(6),
      effectId: inspect.id,
      error: 'boom',
      stack: '#0\n',
    ),
    EffectStarted(time: at(7), effectId: publish.id),
  ];

  /// The change that gives [event] of this session.
  EventAdded added(Event event) =>
      EventAdded(sessionId: session.id, event: event);

  /// Everything the feed gives for the session: its journal goes on, and
  /// its `.owner.lock` names no owner.
  List<Change> get changes => [
    SessionAdded(session),
    for (final effect in [collect, inspect, publish]) EffectAdded(effect),
    for (final event in events) added(event),
    for (final document in [input, collected, snapshot])
      DocumentAdded(sessionId: session.id, documentId: document.id),
    noOwner(session.id),
  ];

  Document _document(Object? value) =>
      Document(id: newId(), sessionId: _sessionId, value: value);

  void _write() {
    sessionDir = writeSession(runsDir, session, events: events);
    for (final document in [input, collected, snapshot]) {
      writeDocument(sessionDir, document);
    }
    writeEffect(sessionDir, collect, startedAt: at(1));
    writeEffect(sessionDir, inspect, startedAt: at(3));
    publishDir = writeEffect(sessionDir, publish, startedAt: at(7));
  }
}
