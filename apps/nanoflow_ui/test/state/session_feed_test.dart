import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_reader/nanoflow_reader.dart';
import 'package:nanoflow_ui/state/session_feed.dart';
import 'package:path/path.dart' as p;

import 'support.dart';

const _session = Session(
  id: 'a1b2-session',
  workflow: 'review',
  graph: null,
  inputId: null,
);
const _collect = Step(
  id: 'collect-step',
  sessionId: 'a1b2-session',
  name: 'collect',
  key: 'collect#1@0000000000000000',
  after: null,
  place: 'lib/review.dart:22',
  outputId: null,
  log: 'step.log',
);
const _inspect = Step(
  id: 'inspect-step',
  sessionId: 'a1b2-session',
  name: 'inspect',
  key: 'inspect#1@0000000000000000',
  after: 'collect#1@0000000000000000',
  place: 'lib/review.dart:24',
  outputId: null,
  log: 'step.log',
);

SessionStarted _started(num at_) => SessionStarted(time: at(at_), code: null);

StepStarted _stepStarted(String stepId, num at_) =>
    StepStarted(time: at(at_), stepId: stepId);

EventAdded _event(Event event) =>
    EventAdded(sessionId: _session.id, event: event);

void main() {
  group('with a change stream', () {
    late StreamController<Change> changes;
    late SessionFeed feed;
    late int notified;

    /// A feed of [changes] under fake time; [body] runs in it.
    void run(void Function(FakeAsync async) body) => fakeAsync((async) {
      changes = StreamController<Change>();
      feed = SessionFeed(
        changes.stream,
        sessionPath: (id) => '/runs/review-2026-09-21T12-03-11-$id',
      );
      notified = 0;
      feed.addListener(() => notified++);
      body(async);
      feed.dispose();
      async.flushMicrotasks();
    });

    void give(FakeAsync async, Iterable<Change> list) {
      list.forEach(changes.add);
      async.flushMicrotasks();
    }

    test('keeps sessions with their steps, events and documents', () {
      run((async) {
        give(async, [
          const SessionAdded(_session),
          const StepAdded(_collect),
          _event(_started(0)),
          _event(_stepStarted(_collect.id, 1)),
          const DocumentAdded(sessionId: 'a1b2-session', documentId: 'doc'),
        ]);

        final session = feed.session('a1b2-session')!;
        expect(session.session, _session);
        expect(session.documents, {'doc'});
        expect(session.steps, {'collect-step': _collect});
        expect(session.events, [_started(0), _stepStarted(_collect.id, 1)]);
        expect(session.state.status, SessionStatus.running);
        expect(session.state.startedAt, at(0));
        expect(session.state.steps.single.stepId, _collect.id);
        expect(feed.sessions.keys, ['a1b2-session']);
      });
    });

    test('gives the steps in the order of their first step-started', () {
      run((async) {
        give(async, [
          const SessionAdded(_session),
          const StepAdded(_inspect),
          const StepAdded(_collect),
          _event(_started(0)),
          _event(_stepStarted(_collect.id, 1)),
          _event(_stepStarted(_inspect.id, 2)),
          _event(_stepStarted(_collect.id, 3)),
        ]);
        final session = feed.session(_session.id)!;
        expect(session.steps.keys, [_inspect.id, _collect.id]);
        expect(session.stepsInOrder, [_collect, _inspect]);
      });
    });

    test('tells of each document as it is added', () {
      run((async) {
        final added = <DocumentAdded>[];
        feed.documentsAdded.listen(added.add);
        give(async, [
          const DocumentAdded(sessionId: 'a1b2-session', documentId: 'doc'),
          const SessionAdded(_session),
          const DocumentAdded(sessionId: 'a1b2-session', documentId: 'out'),
        ]);
        expect(added, const [
          DocumentAdded(sessionId: 'a1b2-session', documentId: 'doc'),
          DocumentAdded(sessionId: 'a1b2-session', documentId: 'out'),
        ]);
      });
    });

    test('a step-changed gives the step its outputId', () {
      run((async) {
        give(async, [
          const SessionAdded(_session),
          const StepAdded(_collect),
          StepChanged(_collect.withOutput('out-doc')),
        ]);
        expect(
          feed.session(_session.id)!.steps[_collect.id]!.outputId,
          'out-doc',
        );
      });
    });

    test('gives the state of a step by its id, as the journal read so far '
        'has it', () {
      run((async) {
        give(async, [
          const SessionAdded(_session),
          _event(_started(0)),
          _event(_stepStarted(_collect.id, 1)),
        ]);
        final session = feed.session(_session.id)!;
        expect(session.stateOf(_collect.id), same(session.state.steps.single));
        expect(session.stateOf(_inspect.id), isNull);

        give(async, [_event(_stepStarted(_inspect.id, 2))]);
        expect(session.stateOf(_inspect.id), same(session.state.steps.last));
        expect(session.stateOf(_inspect.id)!.startedAt, at(2));
      });
    });

    test('a step-started before its step-added counts at once', () {
      run((async) {
        give(async, [
          const SessionAdded(_session),
          _event(_started(0)),
          _event(_stepStarted(_collect.id, 1)),
        ]);
        final session = feed.session(_session.id)!;
        expect(session.steps, isEmpty);
        expect(session.stepsInOrder, isEmpty);
        expect(session.state.steps.single.stepId, _collect.id);

        give(async, [const StepAdded(_collect)]);
        expect(session.steps.keys, [_collect.id]);
        expect(session.stepsInOrder, [_collect]);
      });
    });

    test('a step, event, document or problem given before its session '
        'waits for it', () {
      run((async) {
        give(async, [
          _event(_started(0)),
          const DocumentAdded(sessionId: 'a1b2-session', documentId: 'doc'),
          const StepAdded(_collect),
          StepChanged(_collect.withOutput('out-doc')),
          const LogCorrupted(sessionId: 'a1b2-session', line: 2, text: '{'),
        ]);
        expect(feed.sessions, isEmpty);

        give(async, [const SessionAdded(_session)]);
        final session = feed.session(_session.id)!;
        expect(session.documents, {'doc'});
        expect(session.steps.values.single.outputId, 'out-doc');
        expect(session.events, [_started(0)]);
        expect(session.problems, ['line 2 is not an event: {']);
      });
    });

    test('a journal line that is not an event marks its session Log read '
        'incompletely', () {
      run((async) {
        give(async, [
          const SessionAdded(_session),
          _event(_started(0)),
          const LogCorrupted(
            sessionId: 'a1b2-session',
            line: 2,
            text: '{"time": 1}',
          ),
        ]);
        final session = feed.session(_session.id)!;
        expect(session.incomplete, isTrue);
        expect(session.problems, ['line 2 is not an event: {"time": 1}']);
        expect(session.events, [_started(0)]);
      });
    });

    test('an event this version does not read marks its session Log read '
        'incompletely and is skipped', () {
      run((async) {
        final unknown = UnknownEvent(const {
          'time': '2026-09-21T12:03:12.000Z',
          'event': 'session-paused',
        });
        give(async, [
          const SessionAdded(_session),
          _event(_started(0)),
          _event(unknown),
          _event(_stepStarted(_collect.id, 1)),
        ]);
        final session = feed.session(_session.id)!;
        expect(session.incomplete, isTrue);
        expect(session.problems.single, contains('session-paused'));
        expect(session.events, [_started(0), _stepStarted(_collect.id, 1)]);
        expect(session.state.steps.single.stepId, _collect.id);
      });
    });

    test('a session without problems was read completely', () {
      run((async) {
        give(async, [const SessionAdded(_session), _event(_started(0))]);
        expect(feed.session(_session.id)!.incomplete, isFalse);
      });
    });

    test('a file of a session that cannot be read marks the session Log '
        'read incompletely', () {
      run((async) {
        const dir = '/runs/review-2026-09-21T12-03-11-a1b2-session';
        give(async, [const SessionAdded(_session)]);
        changes
          ..addError(const FormatException('$dir/steps/x/step.json: id: x'))
          ..addError(
            const FileSystemException('Cannot open file', '$dir/log.jsonl'),
          );
        async.flushMicrotasks();
        expect(feed.session(_session.id)!.problems, [
          '$dir/steps/x/step.json: id: x',
          '$dir/log.jsonl: Cannot open file',
        ]);
        expect(feed.problems, isEmpty);
      });
    });

    test('a file error that comes before its session marks the session once '
        'it comes', () {
      run((async) {
        const dir = '/runs/review-2026-09-21T12-03-11-a1b2-session';
        changes.addError(const FormatException('$dir/session.json: id: x'));
        async.flushMicrotasks();
        expect(feed.problems, ['$dir/session.json: id: x']);

        give(async, [const SessionAdded(_session)]);
        expect(feed.session(_session.id)!.incomplete, isTrue);
        expect(feed.problems, isEmpty);
      });
    });

    test('a file error of no session is a problem of the feed', () {
      run((async) {
        give(async, [const SessionAdded(_session)]);
        changes.addError(const FormatException('/runs/x/session.json: id: x'));
        async.flushMicrotasks();
        expect(feed.problems, ['/runs/x/session.json: id: x']);
        expect(feed.session(_session.id)!.incomplete, isFalse);
      });
    });

    test('a burst of changes is announced once', () {
      run((async) {
        give(async, [const SessionAdded(_session)]);
        notified = 0;
        for (var i = 0; i < 1000; i++) {
          changes.add(_event(_stepStarted('step-$i', i)));
        }
        async.flushMicrotasks();
        expect(notified, 0);
        async.elapse(const Duration(milliseconds: 50));
        expect(notified, 1);
        expect(feed.session(_session.id)!.state.steps, hasLength(1000));
      });
    });

    test('dispose stops listening to the changes', () {
      fakeAsync((async) {
        final changes = StreamController<Change>();
        SessionFeed(changes.stream).dispose();
        async.flushMicrotasks();
        expect(changes.hasListener, isFalse);
      });
    });
  });

  test(
    'reads what an FsReader finds in runs/ next to the graph file',
    () async {
      final dir = await Directory.systemTemp.createTemp('nanoflow_feed_test');
      addTearDown(() => dir.delete(recursive: true));
      final runs = runsDirOf(dir.path);
      final ids = (session: newId(), step: newId(), document: newId());
      final sessionDir = p.join(
        runs,
        sessionDirName('review', t0, ids.session),
      );
      final stepDir = p.join(
        sessionDir,
        stepsDirName,
        stepDirName(at(1), 'collect', ids.step),
      );
      Directory(stepDir).createSync(recursive: true);
      Directory(p.join(sessionDir, documentsDirName)).createSync();
      final session = Session(
        id: ids.session,
        workflow: 'review',
        graph: graphFileJson(),
        inputId: null,
      );
      final step = Step(
        id: ids.step,
        sessionId: ids.session,
        name: 'collect',
        key: 'collect#1@0000000000000000',
        after: null,
        place: 'lib/review.dart:22',
        outputId: null,
        log: logFileName,
      );
      _writeJson(p.join(sessionDir, sessionFileName), session.toJson());
      _writeJson(
        p.join(sessionDir, documentsDirName, documentFileName(ids.document)),
        Document(
          id: ids.document,
          sessionId: ids.session,
          value: 'main',
        ).toJson(),
      );
      _writeJson(p.join(stepDir, stepFileName), step.toJson());
      File(p.join(sessionDir, eventsFileName)).writeAsStringSync(
        [
          jsonEncode(SessionStarted(time: t0, code: reviewCode).toJson()),
          'not json',
          jsonEncode(StepStarted(time: at(1), stepId: ids.step).toJson()),
        ].map((line) => '$line\n').join(),
      );

      final reader = FsReader(runsDir: runs);
      final feed = SessionFeed.read(reader);
      addTearDown(feed.dispose);
      // Documents come last in a pass over a session.
      await _until(
        () =>
            feed.session(ids.session)?.documents.contains(ids.document) ??
            false,
      );

      final data = feed.session(ids.session)!;
      expect(data.session, session);
      expect(data.documents, {ids.document});
      expect(data.steps, {ids.step: step});
      expect(data.state.steps.single.stepId, ids.step);
      expect(data.state.codes, [reviewCode]);
      expect(data.problems, ['line 2 is not an event: not json']);

      // A step.json that is not a step marks the session whose directory has
      // it.
      final broken = p.join(
        sessionDir,
        stepsDirName,
        stepDirName(at(9), 'collect', newId()),
      );
      Directory(broken).createSync();
      File(p.join(broken, stepFileName)).writeAsStringSync('{}\n');
      await _until(() => data.problems.length == 2);
      expect(data.problems.last, startsWith(p.join(broken, stepFileName)));
    },
  );
}

void _writeJson(String path, Object? json) => File(path)
    .writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(json)}\n');

/// Waits until [done] holds, looking every few milliseconds.
Future<void> _until(bool Function() done) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) fail('waited too long');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
