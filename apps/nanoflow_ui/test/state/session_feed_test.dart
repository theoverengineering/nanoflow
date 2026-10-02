import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_reader/nanoflow_reader.dart';
import 'package:nanoflow_ui/state/session_feed.dart';
import 'package:path/path.dart' as p;

const _graph = <String, Object?>{
  'start': 'collect',
  'nodes': {
    'collect': {'command': 'nodes/collect/run.sh'},
  },
};

final DateTime _t0 = DateTime.utc(2026, 9, 21, 12, 3, 11, 470);

DateTime _at(int seconds) => _t0.add(Duration(seconds: seconds));

const _session = Session(id: 'a1b2-session', graph: _graph);
const _root = Run(id: 'k7f2-run', sessionId: 'a1b2-session', parentId: null);
const _child = Run(
  id: 'e5f6-run',
  sessionId: 'a1b2-session',
  parentId: 'k7f2-run',
);
const _collect = Step(
  id: 'collect-step',
  runId: 'k7f2-run',
  inputId: 'input-doc',
  outputId: null,
  log: 'command.log',
);

RunStarted _started(String runId, String node, int at) =>
    RunStarted(runId: runId, time: _at(at), node: node);

StepStarted _stepStarted(String runId, String stepId, String node, int at) =>
    StepStarted(runId: runId, time: _at(at), stepId: stepId, node: node);

void main() {
  group('with a change stream', () {
    late StreamController<Change> changes;
    late SessionFeed feed;
    late int notified;

    /// A feed of [changes] under fake time; [body] runs in it.
    void run(
      void Function(FakeAsync async) body, {
      String? Function(String runId)? runPath,
    }) => fakeAsync((async) {
      changes = StreamController<Change>();
      feed = SessionFeed(
        changes.stream,
        runPath: runPath ?? (id) => '/runs/session/$id',
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

    test('keeps sessions with their runs, steps, events and documents', () {
      run((async) {
        give(async, [
          const SessionAdded(_session),
          const RunAdded(_root),
          const StepAdded(_collect),
          EventAdded(_started(_root.id, 'collect', 0)),
          EventAdded(_stepStarted(_root.id, _collect.id, 'collect', 1)),
          const DocumentAdded(sessionId: 'a1b2-session', documentId: 'doc'),
        ]);

        final session = feed.session('a1b2-session')!;
        expect(session.session, _session);
        expect(session.documents, {'doc'});
        final run = session.runs['k7f2-run']!;
        expect(run.run, _root);
        expect(run.steps, {'collect-step': _collect});
        expect(run.events, [
          _started(_root.id, 'collect', 0),
          _stepStarted(_root.id, _collect.id, 'collect', 1),
        ]);
        expect(run.state.status, RunStatus.running);
        expect(run.state.steps.single.node, 'collect');
        expect(feed.sessions.keys, ['a1b2-session']);
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
          const RunAdded(_root),
          const StepAdded(_collect),
          StepChanged(_collect.withOutput('out-doc')),
        ]);
        expect(
          feed
              .session(_session.id)!
              .runs[_root.id]!
              .steps[_collect.id]!
              .outputId,
          'out-doc',
        );
      });
    });

    test('a step-started before its step-added counts at once', () {
      run((async) {
        give(async, [
          const SessionAdded(_session),
          const RunAdded(_root),
          EventAdded(_started(_root.id, 'collect', 0)),
          EventAdded(_stepStarted(_root.id, _collect.id, 'collect', 1)),
        ]);
        final run = feed.session(_session.id)!.runs[_root.id]!;
        expect(run.steps, isEmpty);
        expect(run.state.steps.single.stepId, _collect.id);

        give(async, [const StepAdded(_collect)]);
        expect(run.steps.keys, [_collect.id]);
      });
    });

    test('a run, step, event or document given before what it belongs to '
        'waits for it', () {
      run((async) {
        give(async, [
          EventAdded(_started(_child.id, 'notify', 5)),
          const RunAdded(_child),
          const DocumentAdded(sessionId: 'a1b2-session', documentId: 'doc'),
          const StepAdded(_collect),
          EventAdded(_started(_root.id, 'collect', 0)),
        ]);
        expect(feed.sessions, isEmpty);

        give(async, [const SessionAdded(_session), const RunAdded(_root)]);
        final session = feed.session(_session.id)!;
        expect(session.runs.keys, [_child.id, _root.id]);
        expect(session.documents, {'doc'});
        expect(session.runs[_root.id]!.steps.keys, [_collect.id]);
        expect(session.runs[_root.id]!.events, [
          _started(_root.id, 'collect', 0),
        ]);
        expect(session.runs[_child.id]!.events, [
          _started(_child.id, 'notify', 5),
        ]);
      });
    });

    test('a journal line that is not an event marks its run Log read '
        'incompletely', () {
      run((async) {
        give(async, [
          const SessionAdded(_session),
          const RunAdded(_root),
          EventAdded(_started(_root.id, 'collect', 0)),
          const LogCorrupted(runId: 'k7f2-run', line: 2, text: '{"runId": 1}'),
        ]);
        final run = feed.session(_session.id)!.runs[_root.id]!;
        expect(run.incomplete, isTrue);
        expect(run.problems, ['line 2 is not an event: {"runId": 1}']);
        expect(run.events, [_started(_root.id, 'collect', 0)]);
      });
    });

    test('an event this version does not read marks its run Log read '
        'incompletely and is skipped', () {
      run((async) {
        final unknown = UnknownEvent(const {
          'runId': 'k7f2-run',
          'time': '2026-09-21T12:03:12.000Z',
          'event': 'run-paused',
        });
        give(async, [
          const SessionAdded(_session),
          const RunAdded(_root),
          EventAdded(_started(_root.id, 'collect', 0)),
          EventAdded(unknown),
          EventAdded(_stepStarted(_root.id, _collect.id, 'collect', 1)),
        ]);
        final run = feed.session(_session.id)!.runs[_root.id]!;
        expect(run.incomplete, isTrue);
        expect(run.problems.single, contains('run-paused'));
        expect(run.state.steps.single.stepId, _collect.id);
      });
    });

    test('a run without problems was read completely', () {
      run((async) {
        give(async, [
          const SessionAdded(_session),
          const RunAdded(_root),
          EventAdded(_started(_root.id, 'collect', 0)),
        ]);
        expect(feed.session(_session.id)!.runs[_root.id]!.incomplete, isFalse);
      });
    });

    test('a file of a run that cannot be read marks the run Log read '
        'incompletely', () {
      run((async) {
        give(async, [const SessionAdded(_session), const RunAdded(_root)]);
        changes
          ..addError(
            const FormatException(
              '/runs/session/k7f2-run/steps/x/step.json: id: missing',
            ),
          )
          ..addError(
            const FileSystemException(
              'Cannot open file',
              '/runs/session/k7f2-run/log.jsonl',
            ),
          );
        async.flushMicrotasks();
        final run = feed.session(_session.id)!.runs[_root.id]!;
        expect(run.problems, [
          '/runs/session/k7f2-run/steps/x/step.json: id: missing',
          '/runs/session/k7f2-run/log.jsonl: Cannot open file',
        ]);
        expect(feed.problems, isEmpty);
      });
    });

    test('a file error that comes before its run marks the run once it '
        'comes', () {
      run((async) {
        changes.addError(
          const FormatException('/runs/session/k7f2-run/run.json: id: missing'),
        );
        async.flushMicrotasks();
        expect(feed.problems, ['/runs/session/k7f2-run/run.json: id: missing']);

        give(async, [const SessionAdded(_session), const RunAdded(_root)]);
        expect(feed.session(_session.id)!.runs[_root.id]!.incomplete, isTrue);
        expect(feed.problems, isEmpty);
      });
    });

    test('a file error of no run is a problem of the feed', () {
      run((async) {
        give(async, [const SessionAdded(_session), const RunAdded(_root)]);
        changes.addError(
          const FormatException('/runs/session/session.json: id: missing'),
        );
        async.flushMicrotasks();
        expect(feed.problems, ['/runs/session/session.json: id: missing']);
        expect(feed.session(_session.id)!.runs[_root.id]!.incomplete, isFalse);
      });
    });

    test('a burst of changes is announced once', () {
      run((async) {
        give(async, [const SessionAdded(_session), const RunAdded(_root)]);
        for (var i = 0; i < 1000; i++) {
          changes.add(
            EventAdded(_stepStarted(_root.id, 'step-$i', 'collect', i)),
          );
        }
        async.flushMicrotasks();
        expect(notified, 0);
        async.elapse(const Duration(milliseconds: 50));
        expect(notified, 1);
        expect(
          feed.session(_session.id)!.runs[_root.id]!.state.steps,
          hasLength(1000),
        );
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

  test('reads what an FsReader finds on disk', () async {
    final dir = await Directory.systemTemp.createTemp('nanoflow_feed_test');
    addTearDown(() => dir.delete(recursive: true));
    final runs = p.join(dir.path, 'runs');
    final ids = (
      session: newId(),
      run: newId(),
      step: newId(),
      document: newId(),
    );
    final sessionDir = p.join(runs, sessionDirName('review', _t0, ids.session));
    final runDir = p.join(sessionDir, runDirName(_t0, ids.run));
    final stepDir = p.join(
      runDir,
      stepsDirName,
      stepDirName(_at(1), 'collect', ids.step),
    );
    Directory(stepDir).createSync(recursive: true);
    Directory(p.join(sessionDir, documentsDirName)).createSync();
    final session = Session(id: ids.session, graph: _graph);
    final run = Run(id: ids.run, sessionId: ids.session, parentId: null);
    final step = Step(
      id: ids.step,
      runId: ids.run,
      inputId: ids.document,
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
    _writeJson(p.join(runDir, runFileName), run.toJson());
    _writeJson(p.join(stepDir, stepFileName), step.toJson());
    File(p.join(runDir, eventsFileName)).writeAsStringSync(
      [
        jsonEncode(_started(ids.run, 'collect', 0).toJson()),
        'not json',
        jsonEncode(_stepStarted(ids.run, ids.step, 'collect', 1).toJson()),
      ].map((line) => '$line\n').join(),
    );

    final reader = FsReader(runsDir: runs, graphName: 'review');
    final feed = SessionFeed.read(reader);
    addTearDown(feed.dispose);
    // Documents come last in a pass over a session.
    await _until(
      () =>
          feed.session(ids.session)?.documents.contains(ids.document) ?? false,
    );

    final data = feed.session(ids.session)!;
    expect(data.session, session);
    expect(data.documents, {ids.document});
    final runData = data.runs[ids.run]!;
    expect(runData.steps, {ids.step: step});
    expect(runData.state.steps.single.node, 'collect');
    expect(runData.problems, ['line 2 is not an event: not json']);

    // A step.json that is not a step marks the run whose directory has it.
    final broken = p.join(
      runDir,
      stepsDirName,
      stepDirName(_at(9), 'collect', newId()),
    );
    Directory(broken).createSync();
    File(p.join(broken, stepFileName)).writeAsStringSync('{}\n');
    await _until(() => runData.problems.length == 2);
    expect(runData.problems.last, startsWith(p.join(broken, stepFileName)));
  });
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
