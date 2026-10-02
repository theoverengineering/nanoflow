import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_model/nanoflow_model.dart' hide Route;
import 'package:nanoflow_ui/platform/shell.dart';
import 'package:nanoflow_ui/state/graph_model.dart';
import 'package:nanoflow_ui/state/graph_source.dart';
import 'package:nanoflow_ui/state/outcomes.dart';
import 'package:nanoflow_ui/state/session_feed.dart';

import 'support.dart';

/// The changes that give [journals] of the session [sessionId].
List<Change> _changesOf(
  List<Journal> journals, {
  String sessionId = 'a1b2-session',
}) => [
  SessionAdded(Session(id: sessionId, graph: reviewGraph)),
  for (final journal in journals) ...[
    RunAdded(
      Run(id: journal.id, sessionId: sessionId, parentId: journal.parent),
    ),
    for (final step in journal.steps) StepAdded(step),
    for (final event in journal.events) EventAdded(event),
  ],
];

void main() {
  late StreamController<Change> changes;
  late List<String> read;
  late Set<String> unreadable;
  late GraphModel model;
  late int notified;

  void run(void Function(FakeAsync async) body) => fakeAsync((async) {
    changes = StreamController<Change>();
    read = [];
    unreadable = {};
    model = GraphModel(
      source: GraphSource(
        file: '/nowhere/review.yaml',
        shell: Shell(environment: const {}),
      ),
      feed: SessionFeed(changes.stream),
      outcomes: Outcomes((_, documentId) async {
        read.add(documentId);
        if (unreadable.contains(documentId)) {
          throw FormatException('$documentId.json: not there');
        }
        return const {
          'is-empty-outcome': false,
          'verdict-outcome-1': 'returned',
          'verdict-outcome-2': 'accepted',
        }[documentId];
      }),
      // The graph is opened at 14:20, after everything in the mockup.
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

  test('selects the newest session started before the graph was opened', () {
    run((async) {
      final mockup = Mockup();
      give(async, _changesOf([mockup.k7f2, mockup.c3d4, mockup.e5f6]));
      expect(model.selection.sessionId, 'a1b2-session');
      expect(model.selection.runId, 'e5f6-run');
      expect(model.selectedSession!.id, 'a1b2-session');

      give(
        async,
        _changesOf([
          Journal(
            'newe-run',
            node: 'collect',
            startedAt: 2000,
            sessionId: 'newe-session',
          ),
        ], sessionId: 'newe-session'),
      );
      expect(model.selection.sessionId, 'a1b2-session');
    });
  });

  test('without sessions selects Current graph', () {
    run((async) {
      async.elapse(const Duration(milliseconds: 100));
      expect(model.selection.currentGraph, isTrue);
      expect(model.selectedSession, isNull);
      expect(model.sessionView(Mockup.now), isNull);
    });
  });

  test('reads the outcomes of the forks of the session it shows, and of no '
      'other', () {
    run((async) {
      final old = Journal(
        'olde-run',
        node: 'verdict',
        startedAt: -600,
        sessionId: 'olde-session',
      )..step('verdict', -600, end: -599, output: 'old-outcome');
      give(async, _changesOf([old], sessionId: 'olde-session'));
      expect(model.selection.sessionId, 'olde-session');
      final mockup = Mockup();
      give(async, _changesOf([mockup.k7f2, mockup.c3d4, mockup.e5f6]));
      expect(read, isEmpty);

      model.sessionView(Mockup.now);
      async.elapse(const Duration(milliseconds: 100));
      expect(
        read,
        unorderedEquals([
          'is-empty-outcome',
          'verdict-outcome-1',
          'verdict-outcome-2',
        ]),
      );
      final view = model.sessionView(Mockup.now)!;
      expect(view.marks.passesOf('verdict', 0), 1);
      expect(
        view.run!.header.text,
        'run e5f6 · 8 steps, 7 inherited from k7f2',
      );
    });
  });

  test('marks a run whose outcome cannot be read, and reads it again when '
      'the feed gives its document', () {
    run((async) {
      final mockup = Mockup();
      unreadable.add('verdict-outcome-1');
      give(async, _changesOf([mockup.k7f2, mockup.c3d4, mockup.e5f6]));
      model.sessionView(Mockup.now);
      async.elapse(const Duration(milliseconds: 100));
      final k7f2 = model.sessionView(Mockup.now)!.runs.first;
      expect(k7f2.incomplete, isTrue);

      unreadable.clear();
      give(async, const [
        DocumentAdded(
          sessionId: 'a1b2-session',
          documentId: 'verdict-outcome-1',
        ),
      ]);
      model.sessionView(Mockup.now);
      async.elapse(const Duration(milliseconds: 100));
      expect(read.where((id) => id == 'verdict-outcome-1'), hasLength(2));
      expect(model.sessionView(Mockup.now)!.runs.first.incomplete, isFalse);
    });
  });

  test('computes what it shows once per change and second', () {
    run((async) {
      final mockup = Mockup();
      give(async, _changesOf([mockup.k7f2, mockup.c3d4, mockup.e5f6]));
      final now = Mockup.now;
      final view = model.sessionView(now);
      final sessions = model.sessions(now);
      final sameSecond = now.add(const Duration(milliseconds: 400));
      expect(model.sessionView(sameSecond), same(view));
      expect(model.sessions(sameSecond), same(sessions));

      final nextSecond = now.add(const Duration(seconds: 1));
      expect(model.sessionView(nextSecond), isNot(same(view)));
      expect(model.sessions(nextSecond), isNot(same(sessions)));

      final again = model.sessionView(nextSecond);
      model.selection.selectRun(mockup.session, 'k7f2-run');
      expect(model.sessionView(nextSecond), isNot(same(again)));
    });
  });

  test('follows a running run as its new steps come', () {
    run((async) {
      final mockup = Mockup();
      give(async, _changesOf([mockup.k7f2, mockup.c3d4, mockup.e5f6]));
      final next = mockup.e5f6.step('notify', 700);
      give(async, [
        StepAdded(mockup.e5f6.steps.last),
        EventAdded(mockup.e5f6.events.last),
      ]);
      expect(model.selection.stepId, next);
    });
  });

  test('tells its listeners of changes of the feed and the selection', () {
    run((async) {
      give(async, _changesOf([Mockup().k7f2]));
      expect(notified, greaterThan(0));
      notified = 0;
      model.selection.showCurrentGraph();
      expect(notified, 1);
    });
  });

  group('the canvas', () {
    final graph = Graph.fromJson(reviewGraph);

    test('shows the selected session\'s own graph', () {
      final session = sessionOf(
        const [],
        graph: const {
          'start': 'old',
          'nodes': {
            'old': {'command': 'old.sh'},
          },
        },
      );
      final canvas = canvasOf(
        session: session,
        currentGraph: graph,
        errors: const ['x'],
      );
      expect(canvas.graph!.nodes.keys, ['old']);
      expect(canvas.placeholder, isNull);
      expect(canvas.errors, isEmpty);
      expect(canvas.ofSession, isTrue);
    });

    test('says when the selected session\'s graph cannot be read', () {
      final session = sessionOf(const [], graph: const {'start': 'collect'});
      final canvas = canvasOf(
        session: session,
        currentGraph: graph,
        errors: const [],
      );
      expect(canvas.graph, isNull);
      expect(canvas.placeholder, 'Graph of this session cannot be read');
      expect(canvas.ofSession, isTrue);
    });

    test('for Current graph shows the last graph that passed check, with the '
        'errors of the latest one', () {
      final canvas = canvasOf(
        session: null,
        currentGraph: graph,
        errors: const ['nodes.x: cannot be reached from start'],
      );
      expect(canvas.graph, same(graph));
      expect(canvas.errors, ['nodes.x: cannot be reached from start']);
      expect(canvas.ofSession, isFalse);
    });

    test('for Current graph says No valid graph yet until a graph passes '
        'check', () {
      final canvas = canvasOf(
        session: null,
        currentGraph: null,
        errors: const ['start: names no node'],
      );
      expect(canvas.graph, isNull);
      expect(canvas.placeholder, 'No valid graph yet');
      expect(canvas.errors, ['start: names no node']);
    });
  });
}
