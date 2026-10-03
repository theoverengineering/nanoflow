import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_ui/state/freshness.dart';
import 'package:nanoflow_ui/state/graph_model.dart';
import 'package:nanoflow_ui/state/outcomes.dart';
import 'package:nanoflow_ui/state/session_feed.dart';
import 'package:nanoflow_ui/state/session_view.dart';
import 'package:path/path.dart' as p;

import 'support.dart';

void main() {
  late StreamController<Change> changes;
  late FixedGraphFile graphFile;
  late FixedFreshness freshness;
  late Map<String, Object?> documents;
  late List<String> read;
  late GraphModel model;
  late int notified;

  void run(void Function(FakeAsync async) body) => fakeAsync((async) {
    changes = StreamController<Change>();
    graphFile = FixedGraphFile(reviewGraphFile());
    freshness = FixedFreshness(graphFile);
    documents = {};
    read = [];
    model = GraphModel(
      graphFile: graphFile,
      freshness: freshness,
      feed: SessionFeed(changes.stream),
      outcomes: Outcomes((_, documentId) async {
        read.add(documentId);
        if (!documents.containsKey(documentId)) {
          throw FormatException('$documentId.json: not there');
        }
        return documents[documentId];
      }),
      files: FakeFiles(),
      // The graph is opened at 14:20.
      now: () => at(1009),
    );
    notified = 0;
    model.addListener(() => notified++);
    body(async);
    model.dispose();
    async.flushMicrotasks();
  });

  void give(FakeAsync async, Iterable<Change> list) {
    list.forEach(changes.add);
    async.elapse(const Duration(milliseconds: 100));
  }

  /// Sessions of both workflows: review a1b2 and the newer release c3d4.
  List<Change> twoWorkflows() => changesOf([
    Journal('a1b2-session')..step('collect', 1),
    Journal('c3d4-session', workflow: 'release', startedAt: 10)
      ..step('plan', 11),
  ]);

  group('the workflows', () {
    test('are those of the graph file; the first is selected', () {
      run((async) {
        expect(
          [for (final w in model.workflows) w.name],
          ['review', 'release'],
        );
        expect(model.workflow!.id, 'lib/review.dart#review');
      });
    });

    test('list the sessions of the selected one, and select the newest of '
        'those', () {
      run((async) {
        give(async, twoWorkflows());
        expect(
          [for (final s in model.sessions(at(746))) s.id],
          ['a1b2-session'],
        );
        expect(model.selection.sessionId, 'a1b2-session');
      });
    });

    test('another one selected lists its sessions, and opens the newest '
        'of them', () {
      run((async) {
        give(async, twoWorkflows());
        model.showSession('a1b2-session');
        model.selectWorkflow('lib/release.dart#release');
        expect(model.workflow!.name, 'release');
        expect(
          [for (final s in model.sessions(at(746))) s.id],
          ['c3d4-session'],
        );
        expect(model.selection.sessionId, 'c3d4-session');
      });
    });

    test('one the graph file no longer has gives way to its first', () {
      run((async) {
        model.selectWorkflow('lib/release.dart#release');
        graphFile.graph = GraphFile.fromJson({
          ...graphFileJson(),
          'workflows': ['lib/review.dart#review'],
        });
        expect(model.workflow!.name, 'review');
      });
    });

    test('while no graph file has been read: every session is listed', () {
      run((async) {
        graphFile.graph = null;
        give(async, twoWorkflows());
        expect(model.workflows, isEmpty);
        expect(model.workflow, isNull);
        expect(model.sessions(at(746)), hasLength(2));
        expect(model.selection.sessionId, 'c3d4-session');

        graphFile.graph = reviewGraphFile();
        expect(model.sessions(at(746)), hasLength(1));
        expect(model.selection.sessionId, 'a1b2-session');
      });
    });
  });

  test('without sessions selects Current graph', () {
    run((async) {
      async.elapse(const Duration(milliseconds: 100));
      expect(model.selection.currentGraph, isTrue);
      expect(model.selectedSession, isNull);
      expect(model.sessionView(at(746)), isNull);
    });
  });

  test('reads the snapshot of the session it shows, and of no other', () {
    run((async) {
      final other = Journal('olde-session', startedAt: -600)
        ..resume(-500, graphId: 'old-snapshot');
      final shown = Journal('a1b2-session')
        ..resume(10, graphId: 'snapshot', code: 'sha256:resumed');
      documents['snapshot'] = graphFileJson(
        fingerprint: 'sha256:resumed',
        reviewStep: 'gather',
      );
      give(async, changesOf([other, shown]));
      expect(read, isEmpty);

      expect(model.sessionView(at(746))!.graph.graph, isNull);
      async.elapse(const Duration(milliseconds: 100));
      expect(read, ['snapshot']);
      final graph = model.sessionView(at(746))!.graph;
      expect(
        graph.graph,
        reviewGraphFile(fingerprint: 'sha256:resumed', reviewStep: 'gather'),
      );
      expect(graph.code, CodeCheck.matches);
      expect(model.canvas.file, graph.graph);
    });
  });

  test('a snapshot that cannot be read is read again once the feed gives '
      'its document', () {
    run((async) {
      give(
        async,
        changesOf([Journal('a1b2-session')..resume(10, graphId: 's')]),
      );
      model.sessionView(at(746));
      async.elapse(const Duration(milliseconds: 100));
      expect(model.canvas.placeholder, unreadableSessionGraph);

      documents['s'] = graphFileJson();
      give(async, const [
        DocumentAdded(sessionId: 'a1b2-session', documentId: 's'),
      ]);
      model.sessionView(at(746));
      async.elapse(const Duration(milliseconds: 100));
      expect(read, ['s', 's']);
      expect(model.canvas.placeholder, isNull);
      expect(model.canvas.workflow!.name, 'review');
    });
  });

  test('computes what it shows once per change and second', () {
    run((async) {
      final session = Journal('a1b2-session')
        ..step('collect', 1, end: 149)
        ..step('inspect', 150);
      give(async, session.changes);
      final now = at(746);
      final view = model.sessionView(now);
      final sessions = model.sessions(now);
      final canvas = model.canvas;
      final sameSecond = now.add(const Duration(milliseconds: 400));
      expect(model.sessionView(sameSecond), same(view));
      expect(model.sessions(sameSecond), same(sessions));
      expect(model.canvas, same(canvas));

      final nextSecond = now.add(const Duration(seconds: 1));
      expect(model.sessionView(nextSecond), isNot(same(view)));
      expect(model.sessions(nextSecond), isNot(same(sessions)));

      final again = model.sessionView(nextSecond);
      model.selectStep('a1b2-collect-0');
      expect(model.sessionView(nextSecond), isNot(same(again)));
      expect(model.sessionView(nextSecond)!.stepId, 'a1b2-collect-0');
    });
  });

  test('follows a running session as its new steps come', () {
    run((async) {
      final session = Journal('a1b2-session')..step('collect', 1);
      give(async, session.changes);
      expect(model.selection.stepId, 'a1b2-collect-0');
      final next = session.step('inspect', 700);
      give(async, [
        StepAdded(session.steps.last),
        EventAdded(sessionId: session.id, event: session.events.last),
      ]);
      expect(model.selection.stepId, next);
    });
  });

  test('tells its listeners of changes of the feed, the selection, the '
      'graph file and its freshness', () {
    run((async) {
      give(async, changesOf([Journal('a1b2-session')]));
      expect(notified, greaterThan(0));
      for (final change in <void Function()>[
        model.selection.showCurrentGraph,
        () => graphFile.error = 'broken',
        () => freshness.freshness = const Freshness(stale: true, changed: []),
      ]) {
        notified = 0;
        change();
        expect(notified, 1);
      }
    });
  });

  test('disposes what it owns', () {
    final graphFile = FixedGraphFile();
    GraphModel(
      graphFile: graphFile,
      freshness: FixedFreshness(graphFile),
      feed: SessionFeed(const Stream.empty()),
      outcomes: Outcomes((_, _) async => null),
      files: FakeFiles(),
    ).dispose();
    expect(graphFile.disposed, isTrue);
  });

  group('the canvas of Current graph', () {
    test('draws the selected workflow of the graph file', () {
      final canvas = fileCanvas(
        file: '/p/nanoflow.graph.json',
        graph: reviewGraphFile(),
        workflowId: 'lib/release.dart#release',
      );
      expect(canvas.file, reviewGraphFile());
      expect(canvas.workflow!.name, 'release');
      expect(canvas.ofSession, isFalse);
      expect(canvas.placeholder, isNull);
      expect(canvas.notes, isEmpty);
    });

    test('says No valid graph yet until a graph file has been read', () {
      final canvas = fileCanvas(
        file: '/p/nanoflow.graph.json',
        graph: null,
        workflowId: null,
        error: 'Unexpected end of input at line 1, column 14',
      );
      expect(canvas.workflow, isNull);
      expect(canvas.placeholder, noValidGraphYet);
      expect(canvas.notes, [
        const GraphNote(
          'nanoflow.graph.json cannot be read',
          danger: true,
          lines: ['Unexpected end of input at line 1, column 14'],
        ),
      ]);
    });

    test('says so when the graph file has no workflows', () {
      final graph = GraphFile.fromJson({...graphFileJson(), 'workflows': []});
      final canvas = fileCanvas(
        file: '/p/nanoflow.graph.json',
        graph: graph,
        workflowId: null,
      );
      expect(canvas.placeholder, noWorkflows);
    });

    test('notes a file that is gone or cannot be read, over the last graph '
        'read', () {
      final canvas = fileCanvas(
        file: '/p/nanoflow.graph.json',
        graph: reviewGraphFile(),
        workflowId: 'lib/review.dart#review',
        fileMissing: true,
        error: 'workflows: missing',
      );
      expect(canvas.workflow!.name, 'review');
      expect(canvas.notes, [
        const GraphNote(
          fileUnavailable,
          danger: true,
          text:
              'nanoflow.graph.json is gone; the canvas keeps the last graph '
              'read from it.',
        ),
        const GraphNote(
          'nanoflow.graph.json cannot be read',
          danger: true,
          lines: ['workflows: missing'],
          text: lastGraphShown,
        ),
      ]);
    });

    test('notes a graph that may not match the code, with what changed', () {
      final canvas = fileCanvas(
        file: '/p/nanoflow.graph.json',
        graph: reviewGraphFile(),
        workflowId: 'lib/review.dart#review',
        freshness: const Freshness(
          stale: true,
          changed: ['lib/review.dart', 'review'],
        ),
      );
      expect(canvas.notes, [
        const GraphNote(
          graphMayNotMatchCode,
          lines: ['lib/review.dart', 'review'],
          text: changedSinceWritten,
        ),
      ]);
      expect(
        fileCanvas(
          file: '/p/nanoflow.graph.json',
          graph: reviewGraphFile(),
          workflowId: 'lib/review.dart#review',
          freshness: const Freshness(stale: false, changed: []),
        ).notes,
        isEmpty,
      );
    });

    test('lists the warnings of the graph file', () {
      final canvas = fileCanvas(
        file: '/p/nanoflow.graph.json',
        graph: reviewGraphFile(
          warnings: [
            {
              'place': 'lib/review.dart:40',
              'message': 'steps in a closure passed on are not drawn',
            },
            {'place': null, 'message': 'a catch is not drawn'},
          ],
        ),
        workflowId: 'lib/review.dart#review',
      );
      expect(canvas.notes, [
        const GraphNote(
          '2 warnings in nanoflow.graph.json',
          lines: [
            'lib/review.dart:40  steps in a closure passed on are not drawn',
            'a catch is not drawn',
          ],
        ),
      ]);
    });
  });

  group('the canvas of a session', () {
    SessionGraph graphOf(Journal session, {GraphFile? graphFile}) =>
        sessionGraphOf(
          session.data,
          documents: outcomesOf(const {}),
          graphFile: graphFile ?? reviewGraphFile(fingerprint: 'sha256:now'),
        );

    test('draws its workflow on its graph, without notes when its code '
        'matches', () {
      final session = Journal('a1b2-session');
      final canvas = sessionCanvas(session.data, graphOf(session));
      expect(canvas.file, reviewGraphFile());
      expect(canvas.workflow!.name, 'review');
      expect(canvas.ofSession, isTrue);
      expect(canvas.placeholder, isNull);
      expect(canvas.notes, isEmpty);
    });

    test('notes a session that ran on other code', () {
      final session = Journal('a1b2-session')..resume(10, code: 'sha256:x');
      expect(sessionCanvas(session.data, graphOf(session)).notes, [
        const GraphNote(sessionRanOnOtherCode, text: otherCodeDetail),
      ]);
    });

    test('notes a session whose code was not checked', () {
      final session = Journal('a1b2-session', code: null);
      expect(sessionCanvas(session.data, graphOf(session)).notes, [
        const GraphNote(sessionCodeNotChecked, text: notCheckedDetail),
      ]);
    });

    test('notes a session without a snapshot, drawn on the graph file', () {
      final session = Journal('a1b2-session', snapshot: false);
      final canvas = sessionCanvas(session.data, graphOf(session));
      expect(canvas.file, reviewGraphFile(fingerprint: 'sha256:now'));
      expect(canvas.notes, [
        const GraphNote(sessionHasNoSnapshot, text: noSnapshotDetail),
        const GraphNote(sessionRanOnOtherCode, text: otherCodeDetail),
      ]);
    });

    test('says when its graph cannot be read', () {
      final session = Journal('a1b2-session', graph: {'start': 'collect'});
      final canvas = sessionCanvas(session.data, graphOf(session));
      expect(canvas.file, isNull);
      expect(canvas.placeholder, unreadableSessionGraph);
    });

    test('says when its graph has no function of its workflow', () {
      final session = Journal('a1b2-session', workflow: 'deploy');
      final canvas = sessionCanvas(session.data, graphOf(session));
      expect(canvas.workflow, isNull);
      expect(canvas.placeholder, noWorkflowNamed('deploy'));
    });
  });

  test('opens a graph file: its graph, and the sessions in runs/ next to '
      'it', () async {
    final dir = await Directory.systemTemp.createTemp('nanoflow_model_test');
    addTearDown(() => dir.delete(recursive: true));
    final file = p.join(dir.path, graphFileName);
    File(file).writeAsStringSync(jsonEncode(graphFileJson()));
    final id = newId();
    final sessionDir = p.join(
      runsDirOf(dir.path),
      sessionDirName('review', t0, id),
    );
    Directory(sessionDir).createSync(recursive: true);
    File(p.join(sessionDir, sessionFileName)).writeAsStringSync(
      jsonEncode(
        Session(
          id: id,
          workflow: 'review',
          graph: null,
          inputId: null,
        ).toJson(),
      ),
    );
    File(p.join(sessionDir, eventsFileName)).writeAsStringSync(
      '${jsonEncode(SessionStarted(time: t0, code: null).toJson())}\n',
    );

    final model = GraphModel.open(file);
    addTearDown(model.dispose);
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (model.selection.sessionId == null || model.workflow == null) {
      if (DateTime.now().isAfter(deadline)) fail('waited too long');
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(model.workflow!.name, 'review');
    expect(model.selection.sessionId, id);
    expect(model.canvas.notes, [
      const GraphNote(sessionHasNoSnapshot, text: noSnapshotDetail),
      const GraphNote(sessionCodeNotChecked, text: notCheckedDetail),
    ]);
  });
}
