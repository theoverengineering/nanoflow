import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_sqlite/nanoflow_sqlite.dart';
import 'package:nanoflow_ui/state/body_path.dart';
import 'package:nanoflow_ui/state/freshness.dart';
import 'package:nanoflow_ui/state/graph_model.dart';
import 'package:nanoflow_ui/state/outcomes.dart';
import 'package:nanoflow_ui/state/session_feed.dart';
import 'package:nanoflow_ui/state/session_view.dart';
import 'package:nanoflow_ui/state/store_place.dart';
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

  /// Runs [body] on a fresh model, opened on the session [session] when
  /// given, as the app is started with `--session`.
  void run(void Function(FakeAsync async) body, {String? session}) =>
      fakeAsync((async) {
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
          session: session,
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

  group('the session the app was started on', () {
    test('is selected once the feed gives it, though it started after the '
        'graph opened; none is selected before', () {
      run(session: 'e5f6-session', (async) {
        give(async, twoWorkflows());
        expect(model.selection.currentGraph, isTrue);

        give(
          async,
          changesOf([
            Journal('e5f6-session', startedAt: 2000)..effect('collect', 2001),
          ]),
        );

        expect(model.selection.sessionId, 'e5f6-session');
      });
    });

    test("one of another graph gives way to the newest of the graph's", () {
      run(session: 'c3d4-session', (async) {
        give(async, twoWorkflows());
        expect(model.selection.sessionId, 'a1b2-session');
      });
    });

    test('once selected, gives way to what the user chooses', () {
      run(session: 'a1b2-session', (async) {
        give(async, twoWorkflows());
        expect(model.selection.sessionId, 'a1b2-session');

        model.selection.showCurrentGraph();
        give(
          async,
          changesOf([
            Journal('e5f6-session', startedAt: 2000)..effect('collect', 2001),
          ]),
        );

        expect(model.selection.currentGraph, isTrue);
      });
    });
  });

  group('the workflow', () {
    test("is the graph file's graph, drawn", () {
      run((async) {
        expect(model.workflow!.id, 'lib/review.dart#review');
        expect(model.mainGraph, same(model.workflow));
        expect(model.calledGraph, isNull);
      });
    });

    test('lists its sessions, not those of other graphs, and selects the '
        'newest', () {
      run((async) {
        give(async, twoWorkflows());
        expect(
          [for (final s in model.sessions(at(746))) s.id],
          ['a1b2-session'],
        );
        expect(model.selection.sessionId, 'a1b2-session');
      });
    });

    test('while no graph file has been read: every session is listed', () {
      run((async) {
        graphFile.graph = null;
        give(async, twoWorkflows());
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

  test('sessions of other graphs are neither listed nor noted: runs/ has '
      'those of every graph of the package', () {
    run((async) {
      give(
        async,
        changesOf([
          Journal('a1b2-session'),
          Journal('d1d1-session', workflow: 'deploy', startedAt: 20),
        ]),
      );
      expect([for (final s in model.sessions(at(746))) s.id], ['a1b2-session']);
      expect(model.canvas.notes, isEmpty);
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

    test('start again at the top as a called graph opens or closes', () {
      run((async) {
        graphFile.graph = release;
        model.open(publish);
        model.openAsGraph('lib/publish.dart#publish');
        expect(titles(), ['publish']);
        model.open(const Opened('1'));
        model.closeCalledGraph();
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

  group('a called graph opened as the main graph (open-as-graph design)', () {
    // chain calls carry from implement, and task's body is one call of it.
    final chain = loadGraphFile('chain');
    const carry = 'lib/task_graph.dart#carry';
    const lead = Opened('1', functionId: 'lib/chain.dart#lead');
    const implement = Opened('9', functionId: 'lib/chain.dart#implement');
    const work = Opened('3', functionId: 'lib/task_graph.dart#work');

    List<String> titles() => [
      for (final level in model.canvas.levels) level.title,
    ];

    /// The sessions listed, newest first, with whose they are.
    List<(String, String?)> listed() => [
      for (final s in model.sessions(at(746))) (s.id, s.fromText),
    ];

    /// Sessions on chain's graph: chain c1c1 ran carry — status in admit,
    /// coder in work —, chain c2c2 did not, and task t1t1 did.
    List<Change> sessions() => changesOf([
      Journal('c1c1-session', workflow: 'chain', graph: chain.toJson())
        ..effect('workspace', 1, end: 2, place: 'lib/chain.dart:36')
        ..effect('next task', 2, end: 3, place: 'lib/chain.dart:570')
        ..effect('status', 3, end: 4, place: 'lib/task_graph.dart:66')
        ..effect('coder', 4, end: 5, place: 'lib/task_graph.dart:139')
        ..effect('next task', 5, end: 6, place: 'lib/chain.dart:570'),
      Journal(
        'c2c2-session',
        workflow: 'chain',
        graph: chain.toJson(),
        startedAt: 10,
      )..effect('workspace', 11, end: 12, place: 'lib/chain.dart:36'),
      Journal(
        't1t1-session',
        workflow: 'task',
        graph: chain.toJson(),
        startedAt: 20,
      )..effect('status', 21, end: 22, place: 'lib/task_graph.dart:66'),
    ]);

    /// The release fixture with publish, which release calls, a workflow
    /// too: what an older snapshot had.
    final both = GraphFile.fromJson({
      ...loadGraphFile('release').toJson(),
      'workflows': ['lib/release.dart#release', 'lib/publish.dart#publish'],
    });
    const publish = 'lib/publish.dart#publish';

    /// Sessions on [both]: publish p1p1, release r1r1 that ran publish,
    /// release r2r2 that did not.
    List<Change> publishSessions() => changesOf([
      Journal('p1p1-session', workflow: 'publish', graph: both.toJson())
        ..effect('upload', 1, end: 2, place: 'lib/publish.dart:12'),
      Journal(
          'r1r1-session',
          workflow: 'release',
          graph: both.toJson(),
          startedAt: 10,
        )
        ..effect('plan', 11, end: 12, place: 'lib/release.dart:16')
        ..effect('upload', 12, end: 13, place: 'lib/publish.dart:12'),
      Journal(
        'r2r2-session',
        workflow: 'release',
        graph: both.toJson(),
        startedAt: 20,
      )..effect('plan', 21, end: 22, place: 'lib/release.dart:16'),
    ]);

    test('is drawn from its top, its name the first title; the levels '
        'opened and the nodes expanded go, as it opens and as it closes', () {
      run((async) {
        graphFile.graph = chain;
        model.open(lead);
        model.open(implement);
        notified = 0;
        model.openAsGraph(carry);
        expect(notified, greaterThan(0));
        expect(model.workflow!.id, 'lib/chain.dart#chain');
        expect(model.calledGraph!.id, carry);
        expect(model.mainGraph!.id, carry);
        expect(titles(), ['carry']);
        expect(model.canvas.body, chain.functions[carry]!.body);

        model.open(work);
        expect(titles(), ['carry', 'work()']);
        model.openLevel(0);
        model.expandNode(const [], work);
        expect(model.canvas.frames, hasLength(1));
        model.closeCalledGraph();
        expect(model.calledGraph, isNull);
        expect(titles(), ['chain']);
        model.openAsGraph(carry);
        expect(model.canvas.frames, isEmpty);
      });
    });

    test('lists every session it ran in, newest first: those of workflows '
        'that call it in which an effect is in its body, saying from '
        'which, and not those in which none is', () {
      run((async) {
        graphFile.graph = chain;
        give(async, sessions());
        model.openAsGraph(carry);
        expect(listed(), [
          ('t1t1-session', 'from task'),
          ('c1c1-session', 'from chain'),
        ]);
      });
    });

    test('lists its own sessions too, which say nothing of whose they '
        "are; closed, the workflow's are listed again", () {
      run((async) {
        graphFile.graph = loadGraphFile('release');
        give(async, publishSessions());
        model.openAsGraph(publish);
        expect(listed(), [
          ('r1r1-session', 'from release'),
          ('p1p1-session', null),
        ]);
        model.showSession('p1p1-session');
        expect(model.canvas.workflow!.id, publish);
        expect(model.canvas.places.isWorkflow(model.canvas.body!), isTrue);

        model.closeCalledGraph();
        expect(listed(), [('r2r2-session', null), ('r1r1-session', null)]);
        expect(model.selection.sessionId, 'r2r2-session');
      });
    });

    test('in a parent\'s session: its body from the session\'s snapshot, '
        'the session\'s effects on it found by the places of the session\'s '
        'workflow — a called body —, Logs listing those in it alone, the '
        'last of them selected', () {
      run((async) {
        graphFile.graph = chain;
        give(async, sessions());
        model.openAsGraph(carry);
        model.showSession('c1c1-session');
        final canvas = model.canvas;
        expect(canvas.ofSession, isTrue);
        expect(canvas.calledGraph, carry);
        expect(canvas.workflow!.id, carry);
        expect(canvas.body, same(canvas.file!.functions[carry]!.body));
        expect(canvas.file, isNot(same(chain)));
        expect(canvas.places.isCalled(canvas.body!), isTrue);
        expect(canvas.notes, [
          const GraphNote(sessionRanOnOtherCode, text: otherCodeDetail),
        ]);
        expect(model.selection.effectId, 'c1c1-coder-3');

        final view = model.sessionView(at(746))!;
        expect(view.marks!.of('1')!.state, NodeState.visited);
        expect(view.marks!.of('3')!.state, NodeState.visited);
        expect(view.marks!.of('5')!.state, NodeState.notVisited);
        expect(view.logs.header.text, '2 effects');
        // Each in a run of a call of carry: admit, then work.
        final runs = view.logs.rows.whereType<RunRow>().toList();
        expect([for (final run in runs) run.name], ['admit()', 'work()']);
        expect(view.logs.rows.whereType<EffectRow>(), isEmpty);
        // What the effect details window takes for the effects of `Logs`.
        expect(
          [for (final effect in view.logsEffects) effect.effectId],
          ['c1c1-status-2', 'c1c1-coder-3'],
        );

        // A run opened shows its effects under it; closed again, they go.
        model.toggleRun(runs.last.key);
        List<String> names() => [
          for (final row in model.sessionView(at(746))!.logs.rows)
            switch (row) {
              RunRow(:final name) => name,
              EffectRow(:final name, :final depth) => '$depth $name',
              EndRow() => 'end',
            },
        ];
        expect(names(), ['admit()', 'work()', '1 coder']);
        model.toggleRun(runs.last.key);
        expect(names(), ['admit()', 'work()']);
      });
    });

    test('Current graph draws it from the graph file', () {
      run((async) {
        graphFile.graph = chain;
        give(async, sessions());
        model.openAsGraph(carry);
        model.selection.showCurrentGraph();
        expect(model.canvas.ofSession, isFalse);
        expect(model.canvas.calledGraph, isNull);
        expect(model.canvas.body, same(chain.functions[carry]!.body));
      });
    });

    test('keeps the selected session while it ran in it; another gives way '
        'as on another workflow', () {
      run((async) {
        graphFile.graph = chain;
        give(async, sessions());
        model.showSession('c1c1-session');
        model.openAsGraph(carry);
        expect(model.selection.sessionId, 'c1c1-session');

        model.closeCalledGraph();
        expect(model.selection.sessionId, 'c1c1-session');
        model.showSession('c2c2-session');
        model.openAsGraph(carry);
        expect(model.selection.sessionId, 't1t1-session');
      });
    });

    test('keeps the session selected as the graph opened while it ran in '
        'it', () {
      run((async) {
        graphFile.graph = chain;
        give(
          async,
          changesOf([
            Journal('c1c1-session', workflow: 'chain', graph: chain.toJson())
              ..effect('status', 3, end: 4, place: 'lib/task_graph.dart:66'),
            Journal(
              't1t1-session',
              workflow: 'task',
              graph: chain.toJson(),
              startedAt: 20,
            )..effect('status', 21, end: 22, place: 'lib/task_graph.dart:66'),
          ]),
        );
        expect(model.selection.sessionId, 'c1c1-session');
        model.openAsGraph(carry);
        expect(model.selection.sessionId, 'c1c1-session');
      });
    });

    test('keeps the session selected as it opens, going back to the '
        'workflow', () {
      run((async) {
        graphFile.graph = chain;
        give(
          async,
          changesOf([
            Journal('t1t1-session', workflow: 'task', graph: chain.toJson())
              ..effect('status', 1, end: 2, place: 'lib/task_graph.dart:66'),
            Journal(
              'c1c1-session',
              workflow: 'chain',
              graph: chain.toJson(),
              startedAt: 20,
            )..effect('status', 21, end: 22, place: 'lib/task_graph.dart:66'),
            Journal(
              'c2c2-session',
              workflow: 'chain',
              graph: chain.toJson(),
              startedAt: 30,
            ),
          ]),
        );
        expect(model.selection.sessionId, 'c2c2-session');
        model.openAsGraph(carry);
        expect(model.selection.sessionId, 'c1c1-session');
        model.closeCalledGraph();
        expect(model.selection.sessionId, 'c1c1-session');
      });
    });

    test('closed, the workflow is drawn from its top, with its own '
        'sessions; closing none changes nothing', () {
      run((async) {
        graphFile.graph = chain;
        give(async, sessions());
        model.openAsGraph(carry);
        model.open(work);
        model.closeCalledGraph();
        expect(model.calledGraph, isNull);
        expect(titles(), ['chain']);
        expect(listed(), [('c2c2-session', null), ('c1c1-session', null)]);

        notified = 0;
        model.closeCalledGraph();
        expect(notified, 0);
      });
    });

    test('lists a parent\'s session resumed with a snapshot once the snapshot '
        'is read', () {
      run((async) {
        graphFile.graph = chain;
        documents['snapshot'] = chain.toJson();
        give(
          async,
          changesOf([
            Journal('c1c1-session', workflow: 'chain', graph: chain.toJson())
              ..resume(1, graphId: 'snapshot')
              ..effect('status', 3, end: 4, place: 'lib/task_graph.dart:66'),
          ]),
        );
        model.selection.showCurrentGraph();
        model.openAsGraph(carry);
        expect(listed(), isEmpty);
        async.elapse(const Duration(milliseconds: 100));
        expect(read, contains('snapshot'));
        expect(listed(), [('c1c1-session', 'from chain')]);
      });
    });

    test('opens nothing the graph file does not have', () {
      run((async) {
        graphFile.graph = chain;
        model.openAsGraph('lib/task_graph.dart#gone');
        expect(model.calledGraph, isNull);
        expect(model.mainGraph!.name, 'chain');
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
        file: '/p/lib/review.graph.json',
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
        file: '/p/lib/review.graph.json',
        graph: null,
        workflowId: null,
        error: 'Unexpected end of input at line 1, column 14',
      );
      expect(canvas.workflow, isNull);
      expect(canvas.placeholder, noValidGraphYet);
      expect(canvas.notes, [
        const GraphNote(
          'review.graph.json cannot be read',
          danger: true,
          lines: ['Unexpected end of input at line 1, column 14'],
        ),
      ]);
    });

    test('a file gone before any graph was read keeps none', () {
      final canvas = fileCanvas(
        file: '/p/lib/review.graph.json',
        graph: null,
        workflowId: null,
        fileMissing: true,
      );
      expect(canvas.notes, [
        const GraphNote(
          fileUnavailable,
          danger: true,
          text: 'review.graph.json is gone.',
        ),
      ]);
    });

    test('says so when the graph file has no workflows', () {
      final graph = GraphFile.fromJson({...graphFileJson(), 'workflows': []});
      final canvas = fileCanvas(
        file: '/p/lib/review.graph.json',
        graph: graph,
        workflowId: null,
      );
      expect(canvas.placeholder, noWorkflows);
    });

    test('notes a file that is gone or cannot be read, over the last graph '
        'read', () {
      final canvas = fileCanvas(
        file: '/p/lib/review.graph.json',
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
              'review.graph.json is gone; the canvas keeps the last graph '
              'read from it.',
        ),
        const GraphNote(
          'review.graph.json cannot be read',
          danger: true,
          lines: ['workflows: missing'],
          text: lastGraphShown,
        ),
      ]);
    });

    test('notes a graph that may not match the code, with what changed', () {
      final canvas = fileCanvas(
        file: '/p/lib/review.graph.json',
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
          file: '/p/lib/review.graph.json',
          graph: reviewGraphFile(),
          workflowId: 'lib/review.dart#review',
          freshness: const Freshness(stale: false, changed: []),
        ).notes,
        isEmpty,
      );
    });

    test('lists the warnings of the graph file', () {
      final canvas = fileCanvas(
        file: '/p/lib/review.graph.json',
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
          '2 warnings in review.graph.json',
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

  group('a session on the function of a call opened', () {
    /// inPlace over core and tool, each a call of ship(): core done, tool
    /// on verify.
    List<Change> shipped() => changesOf([
      Journal('a1b2-session', workflow: 'inPlace', graph: packagesGraphJson())
        ..effect('plan', 1, end: 2, place: packagesAt(4), key: 'p', after: null)
        ..effect(
          'upload',
          3,
          end: 4,
          place: packagesAt(7),
          key: 'uc',
          after: 'p',
        )
        ..effect(
          'upload',
          3,
          end: 5,
          place: packagesAt(7),
          key: 'ut',
          after: 'p',
        )
        ..effect(
          'verify',
          6,
          end: 7,
          place: packagesAt(8),
          key: 'vc',
          after: 'uc',
        )
        ..effect('verify', 8, place: packagesAt(8), key: 'vt', after: 'ut'),
    ]);

    void open(FakeAsync async) {
      graphFile.graph = packagesGraphFile();
      give(async, shipped());
      model.open(const Opened('2', functionId: 'lib/packages.dart#ship'));
    }

    test('a click on a node selects its last effect; on a node without one, '
        'nothing', () {
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

    test('stay as another session or Current graph is shown, and go as a '
        'called graph opens', () {
      run((async) {
        graphFile.graph = release;
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

        model.closeCalledGraph();
        expect(frames(), ['publish()'], reason: 'no called graph was open');
        model.openAsGraph('lib/publish.dart#publish');
        model.closeCalledGraph();
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

    group('in a session, a call in place', () {
      const ship = Opened('2', functionId: 'lib/packages.dart#ship');

      void open(FakeAsync async) {
        graphFile.graph = packagesGraphFile();
        give(
          async,
          changesOf([
            Journal(
                'a1b2-session',
                workflow: 'inPlace',
                graph: packagesGraphJson(),
              )
              ..effect(
                'plan',
                1,
                end: 2,
                place: packagesAt(4),
                key: 'p',
                after: null,
              )
              ..effect(
                'upload',
                3,
                end: 4,
                place: packagesAt(7),
                key: 'uc',
                after: 'p',
              )
              ..effect(
                'upload',
                3,
                end: 5,
                place: packagesAt(7),
                key: 'ut',
                after: 'p',
              )
              ..effect(
                'verify',
                6,
                end: 7,
                place: packagesAt(8),
                key: 'vc',
                after: 'uc',
              )
              ..effect(
                'verify',
                8,
                place: packagesAt(8),
                key: 'vt',
                after: 'ut',
              ),
          ]),
        );
        model.expandNode(const [], ship);
      }

      test('a click on a node in the frame selects its last effect; a double '
          'click on an effect there opens it', () {
        run((async) {
          open(async);
          model.clickNode('2', path: const [ship]);
          expect(model.selection.effectId, 'a1b2-verify-4');
          final verify =
              model.canvas.frames.single.level.body.node('2')! as EffectNode;
          expect(model.visitToOpen(verify)!.effectId, 'a1b2-verify-4');
        });
      });

      test('a node in a frame opens one level down from the frame', () {
        run((async) {
          graphFile.graph = GraphFile.fromJson({
            ...packagesGraphJson(),
            'workflows': ['lib/packages.dart#nested'],
          });
          const prepare = Opened('1', functionId: 'lib/packages.dart#prepare');
          model.expandNode(const [], prepare);
          model.open(
            const Opened('2', functionId: 'lib/packages.dart#compile'),
            from: const [prepare],
          );
          expect(
            [for (final level in model.canvas.levels) level.title],
            ['nested', 'prepare()', 'compile()'],
          );
        });
      });
    });
  });

  test("opens a graph's file whose runs/ has the sessions of another graph: "
      'they are not its own, nor noted', () async {
    final dir = await Directory.systemTemp.createTemp('nanoflow_model_test');
    addTearDown(() => dir.delete(recursive: true));
    final file = putGraphOf(dir.path, 'review');
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
    expect(model.workflowSessions.map((s) => s.id), [review]);
    expect(model.canvas.notes, isEmpty);
  });

  test("opens a graph's file: its graph, and the sessions in runs/ of its "
      'project', () async {
    final dir = await Directory.systemTemp.createTemp('nanoflow_model_test');
    addTearDown(() => dir.delete(recursive: true));
    final file = putGraphOf(dir.path, 'review');
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

  test('opens a graph file on an SQLite store, on the session it is told: '
      'the store has no files', () async {
    final dir = await Directory.systemTemp.createTemp('nanoflow_model_test');
    addTearDown(() => dir.delete(recursive: true));
    final file = putGraphOf(dir.path, 'release');
    final db = p.join(dir.path, 'app.db');
    final store = SqliteStore(db);
    addTearDown(store.close);
    final first = await store.createSession(
      workflow: 'review',
      graph: null,
      input: null,
      code: null,
    );
    final second = await store.createSession(
      workflow: 'release',
      graph: null,
      input: null,
      code: null,
    );
    final effect = await second.createEffect(
      name: 'plan',
      key: 'plan#1@e3b0c44298fc1c14',
      after: null,
      place: null,
    );
    await second.appendEvent(
      EffectStarted(time: systemClock(), effectId: effect.id),
    );
    await first.release();
    await second.release();

    final model = GraphModel.open(
      file,
      store: StorePlace.sqlite(db),
      session: second.session.id,
    );
    addTearDown(model.dispose);
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (model.selection.sessionId == null) {
      if (DateTime.now().isAfter(deadline)) fail('waited too long');
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(model.workflow!.name, 'release');
    expect(model.selection.sessionId, second.session.id);
    expect(model.files.effectPath(effect.id), isNull);
    expect(model.files.logPath(effect.id), isNull);
  });
}
