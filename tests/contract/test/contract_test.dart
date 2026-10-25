// The contract of the storage of sessions (storage design §6.7): what every
// adapter does alike, through `SessionStore`, `OpenSession` and
// `SessionReader` — and `Flow` on top of them. Each test runs on each adapter.
import 'dart:convert';
import 'dart:io';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/places.dart';
import 'support/programs.dart';

/// The graph file a session keeps a snapshot of: a session stores whatever
/// map it is given.
const graph = <String, Object?>{
  'format': 2,
  'workflows': ['lib/review.dart#review'],
};

const code = 'sha256:7d3e9f0c';

/// The second [s] of 2026-10-03 10:00 UTC.
DateTime at(int s) => DateTime.utc(2026, 10, 3, 10, 0, s);

Future<OpenSession> _create(
  SessionStore store, {
  String workflow = 'review',
  ({Object? value})? input,
  String? id,
  Owner? owner,
}) async {
  final session = await store.createSession(
    workflow: workflow,
    graph: graph,
    input: input,
    code: code,
    id: id,
    owner: owner,
  );
  addTearDown(session.release);
  return session;
}

void main() {
  for (final scheme in schemes) {
    group(scheme, () => _contract(scheme));
  }
}

void _contract(String scheme) {
  late Place place;
  late SessionStore store;

  setUp(() {
    place = freshPlace(scheme);
    store = storeAt(place);
  });

  group('the store', () {
    test('creates a session whole: its fields, the input document and '
        'session-started; it is unfinished', () async {
      final session = await _create(store, input: (value: {'branch': 'main'}));

      final id = session.session.id;
      final inputId = session.session.inputId;
      expect(isId(id), isTrue);
      expect(
        session.session,
        Session(id: id, workflow: 'review', graph: graph, inputId: inputId),
      );
      expect(await session.documentValue(inputId!), {'branch': 'main'});
      expect(await session.events(), [
        isA<SessionStarted>().having((e) => e.code, 'code', code),
      ]);
      expect(await session.effects(), isEmpty);
      expect(await store.unfinishedSessions('review'), [id]);
      expect(await store.unfinishedSessions('publish'), isEmpty);
    });

    test('writes no input document without an input', () async {
      final session = await _create(store);

      expect(session.session.inputId, isNull);
    });

    test('takes the id it is given, and refuses one it has, writing '
        'nothing', () async {
      final id = newId();

      final session = await _create(store, id: id);

      expect(session.session.id, id);
      await expectLater(
        store.createSession(
          workflow: 'publish',
          graph: null,
          input: null,
          code: null,
          id: id,
        ),
        throwsA(
          isA<SessionExistsException>().having((e) => e.sessionId, 'id', id),
        ),
      );
      expect(await store.unfinishedSessions('publish'), isEmpty);
      expect(await store.unfinishedSessions('review'), [id]);
    });

    test('keeps the effects, the events and the documents written, and '
        'gives them back once the session is opened again', () async {
      final created = await _create(store);
      final collect = await created.createEffect(
        name: 'collect',
        key: 'collect#1@e3b0c44298fc1c14',
        after: null,
        place: 'lib/review.dart:12',
      );
      final started = EffectStarted(time: at(1), effectId: collect.id);
      await created.appendEvent(started);
      final outputId = await created.writeDocument({'files': 2});
      final finished = EffectFinished(
        time: at(2),
        effectId: collect.id,
        outputId: outputId,
      );
      await created.appendEvent(finished);
      final collected = await created.setEffectOutput(collect, outputId);
      final inspect = await created.createEffect(
        name: 'inspect',
        key: 'inspect#1@9f2c1a7b3d5e8f04',
        after: collect.key,
        place: null,
      );
      final moved = await created.setEffectAfter(inspect, null);
      await created.release();

      final opened = (await store.openSession(created.session.id))!;
      addTearDown(opened.release);

      expect(collected.outputId, outputId);
      expect(moved.after, isNull);
      expect(opened.session, created.session);
      expect((await opened.events()).skip(1), [started, finished]);
      expect(await opened.effects(), [collected, moved]);
      expect(await opened.documentValue(outputId), {'files': 2});
    });

    test('appends events given side by side in the order given', () async {
      final session = await _create(store);
      final events = [
        for (var i = 0; i < 20; i++)
          EffectStarted(time: at(i), effectId: newId()),
      ];

      await Future.wait([
        for (final event in events) session.appendEvent(event),
      ]);

      expect((await session.events()).skip(1), events);
    });

    test('lists the unfinished sessions of a workflow newest first, without '
        'those that finished or failed', () async {
      Future<OpenSession> next([String workflow = 'review']) async {
        // Apart in time: newest first is by the time of session-started.
        await Future<void>.delayed(const Duration(milliseconds: 5));
        return _create(store, workflow: workflow);
      }

      final first = await next();
      final finished = await next();
      await finished.appendEvent(SessionFinished(time: at(1), outputId: null));
      final failed = await next();
      await failed.appendEvent(
        SessionFailed(time: at(1), error: 'broken', stack: ''),
      );
      await next('publish');
      final last = await next();

      expect(await store.unfinishedSessions('review'), [
        last.session.id,
        first.session.id,
      ]);
    });

    test('opens no session it does not have', () async {
      expect(await store.openSession(newId()), isNull);
    });

    test('keeps what is added to the log of an effect, and an effect that '
        'runs again adds to it', () async {
      final session = await _create(store);
      final effect = await session.createEffect(
        name: 'collect',
        key: 'collect#1@e3b0c44298fc1c14',
        after: null,
        place: null,
      );

      final log = session.openLog(effect.id)..add(utf8.encode('one\n'));
      await log.close();
      final again = session.openLog(effect.id)..add(utf8.encode('two\n'));
      await again.flush();
      expect(again.unwritten, 0);
      await again.close();

      final text = StringBuffer();
      final reading = readerAt(place)
          .effectLog(session.session.id, effect.id)
          .listen(text.write);
      addTearDown(reading.cancel);
      await waitFor('the log', () => '$text' == 'one\ntwo\n');
      expect(() => session.openLog(newId()), throwsArgumentError);
    });
  });

  group('the owner', () {
    test('a session another process owns is busy; once that process lets it '
        'go, or dies, it opens', () async {
      final (:program, :sessionId) = await hold(place);

      await expectLater(
        store.openSession(sessionId, owner: thisProcess()),
        throwsA(isA<SessionBusyException>()),
      );
      expect(await program.ask('release'), 'ok');
      final opened = await store.openSession(sessionId, owner: thisProcess());
      await opened!.release();

      final second = await hold(place, open: sessionId);
      expect(second.sessionId, sessionId);
      await expectLater(
        store.openSession(sessionId, owner: thisProcess()),
        throwsA(isA<SessionBusyException>()),
      );
      await second.program.kill();
      final taken = await store.openSession(sessionId, owner: thisProcess());
      await taken!.release();
    }, skip: Platform.isMacOS ? false : 'only macOS tells a process is gone');

    test('a session this process owns is busy for another process, and for '
        'this isolate again, until it is let go', () async {
      final session = await _create(store, owner: thisProcess());
      final id = session.session.id;

      expect((await hold(place, open: id)).sessionId, 'busy');
      await expectLater(
        store.openSession(id),
        throwsA(isA<SessionBusyException>()),
      );

      await session.release();
      expect((await hold(place, open: id)).sessionId, id);
    });
  });

  group('the reader', () {
    test('gives a session another process writes as it goes: the session, '
        'its events in the order of its journal, the effect, the documents; '
        'nothing of the owner after the session finished', () async {
      final (:program, :sessionId) = await hold(place);
      final feed = Feed(readerAt(place));
      await feed.given(sessionId, 'session-added', (c) => c is SessionAdded);

      final effectId = await program.ask('effect collect');
      await feed.given(
        sessionId,
        'effect-started',
        (c) => c is EventAdded && c.event is EffectStarted,
      );
      expect(await program.ask('finish $effectId'), 'ok');
      await feed.given(
        sessionId,
        'the effect with its output',
        (c) => switch (c) {
          EffectAdded(:final effect) ||
          EffectChanged(:final effect) => effect.outputId != null,
          _ => false,
        },
      );
      expect(await program.ask('end'), 'ok');
      await feed.given(
        sessionId,
        'session-finished',
        (c) => c is EventAdded && c.event is SessionFinished,
      );
      await program.kill();
      await feed.settle();

      final changes = feed.of(sessionId);
      expect(feed.errors, isEmpty);
      expect(changes.first, isA<SessionAdded>());
      expect(
        [for (final event in eventsIn(changes)) event.name],
        [
          'session-started',
          'effect-started',
          'effect-finished',
          'session-finished',
        ],
      );
      final effects = [
        for (final change in changes)
          if (change
              case EffectAdded(:final effect) || EffectChanged(:final effect))
            effect,
      ];
      expect(effects.first.id, effectId);
      final outputId = effects.last.outputId!;
      expect(changes.whereType<DocumentAdded>(), hasLength(3));
      expect(
        await feed.reader.documentValue(sessionId, outputId),
        '$effectId done',
      );
      final afterEnd = changes.skipWhile(
        (c) => !(c is EventAdded && c.event is SessionFinished),
      );
      expect(afterEnd.whereType<OwnerChanged>(), isEmpty);
    });

    test('tells the owner alive while its process runs, and gone once the '
        'process is killed', () async {
      final (:program, :sessionId) = await hold(place);
      final feed = Feed(readerAt(place));

      await feed.given(
        sessionId,
        'its owner alive',
        (c) => c is OwnerChanged && c.alive == true,
      );
      final told = feed.of(sessionId).whereType<OwnerChanged>().last;
      expect(told.owner?.pid, program.process.pid);
      await program.kill();
      await feed.given(
        sessionId,
        'its owner gone',
        (c) => c is OwnerChanged && c.alive == false,
      );
    }, skip: Platform.isMacOS ? false : 'only macOS tells a process is gone');

    test('gives the log of an effect as another process writes it', () async {
      final (:program, :sessionId) = await hold(place);
      final effectId = await program.ask('effect collect');
      final text = StringBuffer();
      final reading = readerAt(place)
          .effectLog(sessionId, effectId)
          .listen(text.write);
      addTearDown(reading.cancel);

      expect(await program.ask('log $effectId one'), 'ok');
      await waitFor('the first line', () => '$text' == 'one\n');
      expect(await program.ask('log $effectId two'), 'ok');
      await waitFor('the second line', () => '$text' == 'one\ntwo\n');
    });
  });

  group('a flow', () {
    test('on the store, a session killed in an effect is taken on by another '
        'process without running the effects that finished again', () async {
      final work = Directory.systemTemp
          .createTempSync('nanoflow_contract_work_')
          .resolveSymbolicLinksSync();
      addTearDown(() => Directory(work).deleteSync(recursive: true));
      int runs(String effect) {
        final file = File(p.join(work, '$effect.runs'));
        return file.existsSync() ? file.lengthSync() : 0;
      }

      final first = await Program.start('held', [place, work, 'main']);
      final sessionId = await first.line();
      await waitFor('inspect to run', () => runs('inspect') == 1);
      await first.kill();
      File(p.join(work, 'go')).createSync();

      final second = await Program.start('held', [
        place,
        work,
        '--resume',
        sessionId,
      ]);
      expect(await second.line(), sessionId);
      expect(await second.line(), 'main collected, inspected, published');
      expect(await second.exitCode, 0);

      expect([runs('collect'), runs('inspect'), runs('publish')], [1, 2, 1]);
      final session = (await store.openSession(sessionId))!;
      addTearDown(session.release);
      expect(
        [for (final event in await session.events()) event.name],
        [
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
        ],
      );
      expect(await store.unfinishedSessions('held'), isEmpty);
    });
  });
}
