import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_ui/state/body_path.dart';
import 'package:nanoflow_ui/state/freshness.dart';
import 'package:nanoflow_ui/state/graph_model.dart';
import 'package:nanoflow_ui/state/outcomes.dart';
import 'package:nanoflow_ui/state/session_feed.dart';
import 'package:nanoflow_ui/state/session_view.dart';
import 'package:path/path.dart' as p;

import '../layout/support.dart' show loadGraphFile, withEffectFirst;
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
    Journal('a1b2-session')..effect('collect', 1),
    Journal('c3d4-session', workflow: 'release', startedAt: 10)
      ..effect('plan', 11),
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

    test('a chosen session that leaves the workflow as the graph file '
        'changes gives way to the newest session of the workflow', () {
      run((async) {
        give(async, twoWorkflows());
        model.showSession('a1b2-session');
        graphFile.graph = GraphFile.fromJson({
          ...graphFileJson(),
          'workflows': ['lib/release.dart#release'],
        });
        expect(model.workflow!.name, 'release');
        expect(model.selection.sessionId, 'c3d4-session');
      });
    });
  });

  group('workflows the graph file does not have', () {
    /// A snapshot of a graph file that had the deploy workflow.
    final withDeploy = {
      ...graphFileJson(),
      'workflows': ['lib/deploy.dart#deploy'],
      'functions': {
        'lib/deploy.dart#deploy': {
          'name': 'deploy',
          'place': 'lib/deploy.dart:3',
          'body': {'nodes': <Object?>[], 'edges': <Object?>[]},
        },
      },
    };

    /// Review session a1b2, and deploy sessions d1 (with a snapshot that has
    /// deploy) and the newer d2 (without a snapshot).
    List<Change> sessions() => changesOf([
      Journal('a1b2-session'),
      Journal(
        'd1d1-session',
        workflow: 'deploy',
        graph: withDeploy,
        startedAt: 20,
      ),
      Journal(
        'd2d2-session',
        workflow: 'deploy',
        snapshot: false,
        startedAt: 30,
      ),
    ]);

    const unknownNote = GraphNote(
      '2 sessions of a workflow not in nanoflow.graph.json',
      lines: ['deploy'],
      text: notInGraphFileDetail,
    );
    final notInFile = GraphNote(
      workflowNotInFile('deploy', 'nanoflow.graph.json'),
      text: graphFileMayBeStale,
    );

    test('are noted over any other workflow, and listed after the file\'s '
        'own', () {
      run((async) {
        give(async, sessions());
        expect(
          [for (final w in model.workflows) (w.name, w.inGraphFile)],
          [('review', true), ('release', true), ('deploy', false)],
        );
        expect(
          [for (final s in model.sessions(at(746))) s.id],
          ['a1b2-session'],
        );
        expect(model.canvas.notes, [unknownNote]);
        model.selection.showCurrentGraph();
        expect(model.canvas.notes, [unknownNote]);
      });
    });

    test('chosen, list their sessions; each is drawn on its own snapshot, '
        'else not at all', () {
      run((async) {
        give(async, sessions());
        model.selectWorkflow('deploy');
        expect(
          [for (final s in model.sessions(at(746))) s.id],
          ['d2d2-session', 'd1d1-session'],
        );
        expect(model.selection.sessionId, 'd2d2-session');
        expect(model.canvas.workflow, isNull);
        expect(model.canvas.placeholder, noWorkflowNamed('deploy'));
        expect(model.canvas.notes, [
          const GraphNote(sessionHasNoSnapshot, text: noSnapshotDetail),
          notInFile,
        ]);

        model.showSession('d1d1-session');
        expect(model.canvas.workflow!.id, 'lib/deploy.dart#deploy');
        expect(model.canvas.placeholder, isNull);
        expect(model.canvas.notes, [notInFile]);

        model.selection.showCurrentGraph();
        expect(model.canvas.workflow, isNull);
        expect(model.canvas.placeholder, noWorkflowNamed('deploy'));
        expect(model.canvas.notes, [notInFile]);
      });
    });

    test('one chosen stays chosen by its name once describe writes it to '
        'the graph file', () {
      run((async) {
        give(async, sessions());
        model.selectWorkflow('deploy');
        graphFile.graph = GraphFile.fromJson({
          ...graphFileJson(),
          'workflows': [
            'lib/review.dart#review',
            'lib/release.dart#release',
            'lib/deploy.dart#deploy',
          ],
          'functions': {
            ...graphFileJson()['functions']! as Map<String, Object?>,
            ...withDeploy['functions']! as Map<String, Object?>,
          },
        });
        expect(model.workflow!.id, 'lib/deploy.dart#deploy');
        expect(model.workflow!.inGraphFile, isTrue);
        expect(model.selection.sessionId, 'd2d2-session');
        model.selection.showCurrentGraph();
        expect(model.canvas.workflow!.id, 'lib/deploy.dart#deploy');
      });
    });

    test('are counted in the note as they read: a workflow, or how many', () {
      List<GraphNote> notes(Map<String, int> notInGraph) => workflowNotes(
        file: '/p/$graphFileName',
        workflow: null,
        notInGraph: notInGraph,
      );
      expect(
        notes({'deploy': 1}).single.title,
        '1 session of a workflow not in nanoflow.graph.json',
      );
      expect(
        notes({'build': 1, 'deploy': 2}).single.title,
        '3 sessions of 2 workflows not in nanoflow.graph.json',
      );
    });
  });

  group('the levels of the graph', () {
    final release = loadGraphFile('release');
    const publish = Opened('5', functionId: 'lib/publish.dart#publish');

    List<String> titles() => [
      for (final level in model.canvas.levels) level.title,
    ];

    /// Sessions of release, on its graph, and of review.
    List<Change> sessions() => changesOf([
      Journal('r1r1-session', workflow: 'release', graph: release.toJson()),
      Journal(
        'r2r2-session',
        workflow: 'release',
        graph: release.toJson(),
        startedAt: 10,
      ),
      Journal('a1b2-session', graph: release.toJson(), startedAt: 20),
    ]);

    test('start at the workflow\'s body, and go down into what is opened '
        'and back up to a crumb', () {
      run((async) {
        graphFile.graph = release;
        expect(titles(), ['release']);
        expect(model.canvas.body, release.functions.values.last.body);

        notified = 0;
        model.open(publish);
        expect(notified, greaterThan(0));
        expect(titles(), ['release', 'publish()']);
        expect(
          model.canvas.body,
          release.functions['lib/publish.dart#publish']!.body,
        );
        // Nothing opens from an effect: the levels stay.
        model.open(const Opened('1'));
        expect(titles(), ['release', 'publish()']);

        model.openLevel(0);
        expect(titles(), ['release']);
      });
    });

    test('stay as another session of the workflow is shown, on its graph', () {
      run((async) {
        graphFile.graph = release;
        give(async, sessions());
        expect(model.selection.sessionId, 'r2r2-session');
        model.open(publish);
        model.showSession('r1r1-session');
        expect(model.canvas.ofSession, isTrue);
        expect(titles(), ['release', 'publish()']);
        model.selection.showCurrentGraph();
        expect(titles(), ['release', 'publish()']);
      });
    });

    test('go as deep as the graph has them, and open on from there', () {
      run((async) {
        graphFile.graph = release;
        model.open(publish);
        // describe wrote the file again without the call.
        final json = release.toJson();
        final body =
            ((json['functions']! as Map)['lib/release.dart#release']!
                    as Map)['body']!
                as Map;
        (body['nodes']! as List).removeWhere((n) => (n as Map)['id'] == '5');
        graphFile.graph = GraphFile.fromJson(json);
        expect(titles(), ['release']);
        graphFile.graph = release;
        expect(titles(), ['release', 'publish()']);
      });
    });

    test('start again at the top of another workflow chosen, or of the '
        'same', () {
      run((async) {
        graphFile.graph = GraphFile.fromJson({
          ...release.toJson(),
          'workflows': ['lib/release.dart#release', 'lib/publish.dart#publish'],
        });
        model.open(publish);
        model.selectWorkflow('lib/publish.dart#publish');
        expect(titles(), ['publish']);
        model.selectWorkflow('lib/release.dart#release');
        expect(titles(), ['release']);
        model.open(publish);
        model.selectWorkflow('lib/release.dart#release');
        expect(titles(), ['release']);
      });
    });

    test('are none without a workflow to draw', () {
      run((async) {
        graphFile.graph = null;
        expect(model.canvas.levels, isEmpty);
        expect(model.canvas.body, isNull);
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
        reviewEffect: 'gather',
      );
      give(async, changesOf([other, shown]));
      expect(read, isEmpty);

      expect(model.sessionView(at(746))!.graph.graph, isNull);
      async.elapse(const Duration(milliseconds: 100));
      expect(read, ['snapshot']);
      final graph = model.sessionView(at(746))!.graph;
      expect(
        graph.graph,
        reviewGraphFile(fingerprint: 'sha256:resumed', reviewEffect: 'gather'),
      );
      expect(graph.code, CodeCheck.matches);
      expect(model.canvas.file, graph.graph);
    });
  });

  test('reads the last snapshot of every session listed, and no earlier '
      'one: each card tells how its code stands without being shown', () {
    run((async) {
      final other = Journal('olde-session', startedAt: -600)
        ..resume(-550, graphId: 'first-snapshot', code: 'sha256:first')
        ..resume(-500, graphId: 'old-snapshot', code: 'sha256:old');
      final shown = Journal('a1b2-session')
        ..resume(10, graphId: 'snapshot', code: 'sha256:resumed');
      // Described before the code it was resumed on was.
      documents['old-snapshot'] = graphFileJson(fingerprint: 'sha256:first');
      documents['snapshot'] = graphFileJson(fingerprint: 'sha256:resumed');
      give(async, changesOf([other, shown]));

      model.sessions(at(746));
      async.elapse(const Duration(milliseconds: 100));

      expect(read, unorderedEquals(['old-snapshot', 'snapshot']));
      expect(
        {for (final s in model.sessions(at(746))) s.id: s.code},
        {
          'a1b2-session': CodeCheck.matches,
          'olde-session': CodeCheck.otherCode,
        },
      );
      expect(model.selection.sessionId, 'a1b2-session');
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
        ..effect('collect', 1, end: 149)
        ..effect('inspect', 150);
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
      model.selectEffect('a1b2-collect-0');
      expect(model.sessionView(nextSecond), isNot(same(again)));
      expect(model.sessionView(nextSecond)!.effectId, 'a1b2-collect-0');
    });
  });

  test('follows a running session as its new effects come', () {
    run((async) {
      final session = Journal('a1b2-session')..effect('collect', 1);
      give(async, session.changes);
      expect(model.selection.effectId, 'a1b2-collect-0');
      final next = session.effect('inspect', 700);
      give(async, [
        EffectAdded(session.effects.last),
        EventAdded(sessionId: session.id, event: session.events.last),
      ]);
      expect(model.selection.effectId, next);
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

  test('close stops its feed and completes once the feed has stopped; '
      'dispose may follow', () {
    fakeAsync((async) {
      final stopped = Completer<void>();
      final changes = StreamController<Change>(onCancel: () => stopped.future);
      final graphFile = FixedGraphFile();
      final model = GraphModel(
        graphFile: graphFile,
        freshness: FixedFreshness(graphFile),
        feed: SessionFeed(changes.stream),
        outcomes: Outcomes((_, _) async => null),
        files: FakeFiles(),
      );
      var closed = false;

      unawaited(model.close().then((_) => closed = true));
      async.flushMicrotasks();
      expect(changes.hasListener, isFalse);
      expect(closed, isFalse);

      stopped.complete();
      async.flushMicrotasks();
      expect(closed, isTrue);
      model.dispose();
      expect(graphFile.disposed, isTrue);
    });
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

    test('a file gone before any graph was read keeps none', () {
      final canvas = fileCanvas(
        file: '/p/nanoflow.graph.json',
        graph: null,
        workflowId: null,
        fileMissing: true,
      );
      expect(canvas.notes, [
        const GraphNote(
          fileUnavailable,
          danger: true,
          text: 'nanoflow.graph.json is gone.',
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
              'message': 'effects in a closure passed on are not drawn',
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
            'lib/review.dart:40  effects in a closure passed on are not drawn',
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

    test('lists the effects that are not on the graph: at no effect node, or '
        'without a place (spec §9 «Эффекты на графе»)', () {
      final session = Journal('a1b2-session')
        ..effect('collect', 1, end: 2, place: 'lib/review.dart:22')
        ..effect('gather', 2, end: 3, place: 'lib/review.dart:30')
        ..effect('loose', 3);
      expect(sessionCanvas(session.data, graphOf(session)).notes, [
        const GraphNote(
          '2 effects not on the graph',
          lines: ['gather  lib/review.dart:30', 'loose  no place'],
          text:
              'They match no effect on the graph: the code may differ from '
              'the one it was read from.',
        ),
      ]);
    });

    test('lists five effects not on the graph, and says how many more', () {
      final session = Journal('a1b2-session');
      for (var i = 0; i < 7; i++) {
        session.effect('gather', i, end: i + 1, place: 'lib/old.dart:$i');
      }
      final note = sessionCanvas(session.data, graphOf(session)).notes.single;
      expect(note.title, '7 effects not on the graph');
      expect(note.lines, [
        for (var i = 0; i < 5; i++) 'gather  lib/old.dart:$i',
        'and 2 more',
      ]);
    });

    test('says nothing of effects not on the graph while the graph has no '
        'workflow to put them on', () {
      final session = Journal('a1b2-session', workflow: 'deploy')
        ..effect('loose', 1, end: 2, place: 'lib/deploy.dart:3');
      final canvas = sessionCanvas(session.data, graphOf(session));
      expect(canvas.placeholder, noWorkflowNamed('deploy'));
      expect(canvas.notes, isEmpty);
    });

    test('has the effect nodes of its workflow', () {
      final session = Journal('a1b2-session');
      final canvas = sessionCanvas(session.data, graphOf(session));
      expect(
        [for (final node in canvas.places.nodes) node.place],
        ['lib/review.dart:22'],
      );
    });
  });

  group('a session with copies', () {
    /// inPlace over core and tool: core done, tool on verify.
    List<Change> copies() => changesOf([
      Journal('a1b2-session', workflow: 'inPlace', graph: copiesGraphJson())
        ..effect('plan', 1, end: 2, place: copiesAt(4), key: 'p', after: null)
        ..effect('upload', 3, end: 4, place: copiesAt(7), key: 'uc', after: 'p')
        ..effect('upload', 3, end: 5, place: copiesAt(7), key: 'ut', after: 'p')
        ..effect(
          'verify',
          6,
          end: 7,
          place: copiesAt(8),
          key: 'vc',
          after: 'uc',
        )
        ..effect('verify', 8, place: copiesAt(8), key: 'vt', after: 'ut'),
    ]);

    void open(FakeAsync async) {
      graphFile.graph = copiesGraphFile();
      give(async, copies());
      model.open(const Opened('2'));
    }

    test('shows every copy of the copies drawn until one is chosen', () {
      run((async) {
        open(async);
        final view = model.sessionView(at(746))!;
        expect(view.frames.single.copies, hasLength(2));
        expect(view.frames.single.selected, isNull);
        expect(view.logs.header.text, '5 effects');
      });
    });

    test('a chosen copy shows its effects, its last selected', () {
      run((async) {
        open(async);
        final tool = model.sessionView(at(746))!.frames.single.copies[1];
        model.selectCopy(1, tool.id);
        final view = model.sessionView(at(746))!;
        expect(view.frames.single.selected!.number, 2);
        expect(view.logs.header.text, 'pkg 2 · 2 effects');
        expect(model.selection.effectId, 'a1b2-verify-4');
        model.selectCopy(1, null);
        expect(model.sessionView(at(746))!.frames.single.selected, isNull);
      });
    });

    test('a chosen copy is followed: its new effects are selected, those of '
        'other copies are not', () {
      run((async) {
        open(async);
        final tool = model.sessionView(at(746))!.frames.single.copies[1];
        model.selectCopy(1, tool.id);
        expect(model.selection.following, isTrue);
        EffectAdded record(String name, String key, String after) =>
            EffectAdded(
              Effect(
                id: 'a1b2-$name-$key',
                sessionId: 'a1b2-session',
                name: name,
                key: key,
                after: after,
                place: copiesAt(name == 'tag' ? 9 : 8),
                outputId: null,
                log: logFileName,
              ),
            );
        EventAdded started(String effectId, num time) => EventAdded(
          sessionId: 'a1b2-session',
          event: EffectStarted(time: at(time), effectId: effectId),
        );
        // Core's tag: another copy.
        give(async, [record('tag', 'tc', 'vc'), started('a1b2-tag-tc', 20)]);
        expect(model.selection.effectId, 'a1b2-verify-4');
        // Tool's tag: the copy chosen.
        give(async, [record('tag', 'tt', 'vt'), started('a1b2-tag-tt', 21)]);
        expect(model.selection.effectId, 'a1b2-tag-tt');
      });
    });

    test('the chosen copies are forgotten for another session', () {
      run((async) {
        open(async);
        final tool = model.sessionView(at(746))!.frames.single.copies[1];
        model.selectCopy(1, tool.id);
        give(
          async,
          changesOf([
            Journal(
              'b2c3-session',
              workflow: 'inPlace',
              graph: copiesGraphJson(),
              startedAt: 20,
            ),
          ]),
        );
        model.showSession('b2c3-session');
        model.showSession('a1b2-session');
        expect(model.sessionView(at(746))!.frames.single.selected, isNull);
      });
    });

    test('a click on a node selects its last effect among those shown; on '
        'a node without one, nothing', () {
      run((async) {
        open(async);
        model.clickNode('1');
        expect(model.selection.effectId, 'a1b2-upload-2');
        model.clickNode('3');
        expect(model.selection.effectId, 'a1b2-upload-2');
      });
    });

    test('a double click on an effect node opens its last effect', () {
      run((async) {
        open(async);
        final verify = model.canvas.body!.node('2')! as EffectNode;
        expect(model.visitToOpen(verify)!.effectId, 'a1b2-verify-4');
        final details = model.detailsOf(verify, 'a1b2-verify-3', at(746));
        expect(details.visitText, 'Visit 1 of 2');
        expect(details.copy, 'pkg 1');
      });
    });
  });

  group('nodes expanded in place (decision 6)', () {
    final release = loadGraphFile('release');
    const publish = Opened('5', functionId: 'lib/publish.dart#publish');

    List<String> frames() => [
      for (final frame in model.canvas.frames) frame.level.title,
    ];

    test('a node expands in the level drawn, and collapses back', () {
      run((async) {
        graphFile.graph = release;
        notified = 0;
        model.expandNode(const [], publish);
        expect(notified, greaterThan(0));
        expect(frames(), ['publish()']);
        expect(model.canvas.frames.single.path, const [publish]);
        model.collapseNode(const [], '5');
        expect(frames(), isEmpty);
      });
    });

    test('stay as another session or Current graph is shown, and go for '
        'another workflow', () {
      run((async) {
        graphFile.graph = GraphFile.fromJson({
          ...release.toJson(),
          'workflows': ['lib/release.dart#release', 'lib/publish.dart#publish'],
        });
        give(
          async,
          changesOf([
            Journal(
              'r1r1-session',
              workflow: 'release',
              graph: release.toJson(),
            ),
            Journal(
              'r2r2-session',
              workflow: 'release',
              graph: release.toJson(),
              startedAt: 10,
            ),
          ]),
        );
        model.expandNode(const [], publish);
        model.showSession('r1r1-session');
        expect(frames(), ['publish()']);
        model.selection.showCurrentGraph();
        expect(frames(), ['publish()']);

        model.selectWorkflow('lib/release.dart#release');
        expect(frames(), ['publish()'], reason: 'the same workflow');
        model.selectWorkflow('lib/publish.dart#publish');
        model.selectWorkflow('lib/release.dart#release');
        expect(frames(), isEmpty);

        model.expandNode(const [], publish);
        graphFile.graph = GraphFile.fromJson(graphFile.graph!.toJson());
        expect(frames(), ['publish()'], reason: 'written again the same');
      });
    });

    test('follow their nodes into a graph file written again, as the levels '
        'opened do: an edit numbers the nodes anew', () {
      run((async) {
        const releaseId = 'lib/release.dart#release';
        const publishId = 'lib/publish.dart#publish';
        graphFile.graph = release;
        model.expandNode(const [], publish);
        model.expandNode(const [publish], const Opened('4'));
        expect(frames(), ['publish()']);

        // An effect added at the start of release: publish's call is 6 now.
        graphFile.graph = withEffectFirst(release, releaseId, 'prepare');
        const moved = Opened('6', functionId: publishId);
        expect(frames(), ['publish()']);
        expect(model.canvas.frames.single.path, const [moved]);

        model.open(moved);
        expect(model.canvas.path, const [moved]);
        // And one at the start of publish: still opened, the level drawn.
        graphFile.graph = withEffectFirst(
          withEffectFirst(release, releaseId, 'prepare'),
          publishId,
          'sign',
        );
        expect(model.canvas.path, const [moved]);

        // A graph file without the call: the level closes.
        final json = release.toJson();
        final body =
            ((json['functions']! as Map)[releaseId]! as Map)['body']! as Map;
        body['nodes'] = [
          for (final node in body['nodes']! as List)
            if ((node as Map)['id'] != '5') node,
        ];
        body['edges'] = [
          for (final edge in body['edges']! as List)
            if ((edge as Map)['from'] != '5' && edge['to'] != '5') edge,
        ];
        graphFile.graph = GraphFile.fromJson(json);
        expect(model.canvas.path, isEmpty);
        expect(frames(), isEmpty);
      });
    });

    group('in a session with copies', () {
      const copies = Opened('2');

      void open(FakeAsync async) {
        graphFile.graph = copiesGraphFile();
        give(
          async,
          changesOf([
            Journal(
                'a1b2-session',
                workflow: 'inPlace',
                graph: copiesGraphJson(),
              )
              ..effect(
                'plan',
                1,
                end: 2,
                place: copiesAt(4),
                key: 'p',
                after: null,
              )
              ..effect(
                'upload',
                3,
                end: 4,
                place: copiesAt(7),
                key: 'uc',
                after: 'p',
              )
              ..effect(
                'upload',
                3,
                end: 5,
                place: copiesAt(7),
                key: 'ut',
                after: 'p',
              )
              ..effect(
                'verify',
                6,
                end: 7,
                place: copiesAt(8),
                key: 'vc',
                after: 'uc',
              )
              ..effect('verify', 8, place: copiesAt(8), key: 'vt', after: 'ut'),
          ]),
        );
        model.expandNode(const [], copies);
      }

      test('a copy chosen in the frame is the one opening it shows; Logs '
          'and the selection follow it', () {
        run((async) {
          open(async);
          var view = model.sessionView(at(746))!;
          final tool = view.scopeOf(const [copies])!.copies!.copies[1];
          model.selectCopyAt(const [copies], tool.id);
          view = model.sessionView(at(746))!;
          expect(view.scopeOf(const [copies])!.copies!.selected!.number, 2);
          expect(view.logs.header.text, 'pkg 2 · 2 effects');
          expect(model.selection.effectId, 'a1b2-verify-4');

          model.open(copies);
          view = model.sessionView(at(746))!;
          expect(view.frames.single.selected!.number, 2);
          model.openLevel(0);
          model.selectCopyAt(const [copies], null);
          expect(model.sessionView(at(746))!.logs.header.text, '5 effects');
        });
      });

      test(
        'a click on a node in the frame selects its last effect among '
        'those the frame shows; a double click on an effect there opens it',
        () {
          run((async) {
            open(async);
            final core = model
                .sessionView(at(746))!
                .scopeOf(const [copies])!
                .copies!
                .copies
                .first;
            model.clickNode('2', path: const [copies]);
            expect(model.selection.effectId, 'a1b2-verify-4');
            model.selectCopyAt(const [copies], core.id);
            model.clickNode('2', path: const [copies]);
            expect(model.selection.effectId, 'a1b2-verify-3');
            final verify =
                model.canvas.frames.single.level.body.node('2')! as EffectNode;
            expect(
              model.visitToOpen(verify, path: const [copies])!.effectId,
              'a1b2-verify-3',
            );
          });
        },
      );

      test('a node in a frame opens one level down from the frame', () {
        run((async) {
          graphFile.graph = copiesGraphFile();
          model.selectWorkflow('lib/copies.dart#viaCall');
          model.expandNode(const [], const Opened('1'));
          model.open(
            const Opened('1', functionId: 'lib/copies.dart#publish'),
            from: const [Opened('1')],
          );
          expect(
            [for (final level in model.canvas.levels) level.title],
            ['viaCall', 'pkg in packages', 'publish()'],
          );
        });
      });
    });
  });

  test('opens a graph file whose runs/ has a session of a workflow it does '
      'not have: noted, and reachable', () async {
    final dir = await Directory.systemTemp.createTemp('nanoflow_model_test');
    addTearDown(() => dir.delete(recursive: true));
    final file = p.join(dir.path, graphFileName);
    File(file).writeAsStringSync(jsonEncode(graphFileJson()));
    final review = newId();
    final deploy = newId();
    for (final (id, workflow) in [(review, 'review'), (deploy, 'deploy')]) {
      final sessionDir = p.join(
        runsDirOf(dir.path),
        sessionDirName(workflow, t0, id),
      );
      Directory(sessionDir).createSync(recursive: true);
      File(p.join(sessionDir, sessionFileName)).writeAsStringSync(
        jsonEncode(
          Session(
            id: id,
            workflow: workflow,
            graph: graphFileJson(),
            inputId: null,
          ).toJson(),
        ),
      );
      File(p.join(sessionDir, eventsFileName)).writeAsStringSync(
        '${jsonEncode(SessionStarted(time: t0, code: reviewCode).toJson())}\n',
      );
    }

    final model = GraphModel.open(file);
    addTearDown(model.dispose);
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    bool started(String id) => model.feed.session(id)?.state.startedAt != null;
    while (!started(review) ||
        !started(deploy) ||
        model.selection.sessionId == null ||
        model.workflow == null) {
      if (DateTime.now().isAfter(deadline)) fail('waited too long');
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(model.selection.sessionId, review);
    expect(model.canvas.notes, [
      const GraphNote(
        '1 session of a workflow not in nanoflow.graph.json',
        lines: ['deploy'],
        text: notInGraphFileDetail,
      ),
    ]);

    model.selectWorkflow('deploy');
    expect(model.selection.sessionId, deploy);
    expect(model.canvas.placeholder, noWorkflowNamed('deploy'));
    expect(model.canvas.notes, [
      GraphNote(
        workflowNotInFile('deploy', graphFileName),
        text: graphFileMayBeStale,
      ),
    ]);
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
