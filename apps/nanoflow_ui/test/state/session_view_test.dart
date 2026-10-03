import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_ui/state/session_view.dart';

import 'support.dart';

void main() {
  final now = at(746);
  final noDocuments = outcomesOf(const {});

  /// The graph file as it is now: the review workflow's step is `gather`.
  final graphFile = reviewGraphFile(
    fingerprint: 'sha256:now',
    reviewStep: 'gather',
  );

  SessionGraph graphOf(
    Journal session, {
    Map<String, Object?> documents = const {},
    Map<String, String> unreadable = const {},
  }) => sessionGraphOf(
    session.data,
    documents: outcomesOf(documents, failed: unreadable),
    graphFile: graphFile,
  );

  group('the graph of a session (spec §9 «Сессия»)', () {
    test('is the snapshot it was created with', () {
      final graph = graphOf(Journal('a1b2-session'));
      expect(graph.graph, reviewGraphFile());
      expect(graph.noSnapshot, isFalse);
      expect(graph.unreadable, isFalse);
    });

    test('is the snapshot of its last resume that has one', () {
      final session = Journal('a1b2-session')
        ..resume(10, graphId: 'snapshot-1')
        ..resume(20, graphId: 'snapshot-2')
        ..resume(30);
      final graph = graphOf(
        session,
        documents: {
          'snapshot-1': graphFileJson(reviewStep: 'first'),
          'snapshot-2': graphFileJson(reviewStep: 'second'),
        },
      );
      expect(graph.graph, reviewGraphFile(reviewStep: 'second'));
      expect(graph.noSnapshot, isFalse);
    });

    test('is not known while the snapshot of its resume is read', () {
      final session = Journal('a1b2-session')..resume(10, graphId: 'snap');
      final graph = graphOf(session);
      expect(graph.graph, isNull);
      expect(graph.unreadable, isFalse);
      expect(graph.code, isNull);
    });

    test('cannot be read when its snapshot document cannot', () {
      final session = Journal('a1b2-session')..resume(10, graphId: 'snap');
      final graph = graphOf(session, unreadable: {'snap': 'snap.json: gone'});
      expect(graph.graph, isNull);
      expect(graph.unreadable, isTrue);
    });

    test('cannot be read when its snapshot is not a graph file', () {
      final graph = graphOf(
        Journal('a1b2-session', graph: {'start': 'collect'}),
      );
      expect(graph.graph, isNull);
      expect(graph.unreadable, isTrue);

      final resumed = Journal('a1b2-session')..resume(10, graphId: 'snap');
      expect(
        graphOf(resumed, documents: {'snap': 'not a graph'}).unreadable,
        isTrue,
      );
    });

    test('without a snapshot is the graph file, marked so', () {
      final graph = graphOf(Journal('a1b2-session', snapshot: false));
      expect(graph.graph, same(graphFile));
      expect(graph.noSnapshot, isTrue);
    });

    test('without a snapshot or a graph file is none', () {
      final graph = sessionGraphOf(
        Journal('a1b2-session', snapshot: false).data,
        documents: noDocuments,
        graphFile: null,
      );
      expect(graph.graph, isNull);
      expect(graph.noSnapshot, isTrue);
      expect(graph.unreadable, isFalse);
    });
  });

  group('the code of a session, checked against its graph', () {
    test('matches the fingerprint of its snapshot', () {
      expect(graphOf(Journal('a1b2-session')).code, CodeCheck.matches);
    });

    test('of its last resume: other code once the code changed', () {
      final session = Journal('a1b2-session')..resume(10, code: 'sha256:x');
      expect(graphOf(session).code, CodeCheck.otherCode);
    });

    test('without a hash: not checked', () {
      expect(
        graphOf(Journal('a1b2-session', code: null)).code,
        CodeCheck.notChecked,
      );
    });

    test('without a snapshot: against the graph file', () {
      final session = Journal(
        'a1b2-session',
        snapshot: false,
        code: 'sha256:now',
      );
      expect(graphOf(session).code, CodeCheck.matches);
      expect(
        graphOf(Journal('b2c3-session', snapshot: false)).code,
        CodeCheck.otherCode,
      );
    });
  });

  test('the whole view puts together what the session shows', () {
    final session = Journal('a1b2-session')
      ..step('collect', 1, end: 149)
      ..step('inspect', 150);
    final view = SessionView.of(
      session.data,
      now: now,
      documents: noDocuments,
      graphFile: graphFile,
      stepId: 'a1b2-collect-0',
    );
    expect(view.summary!.statusText, 'Running for 12m 26s');
    expect(view.graph.graph, reviewGraphFile());
    expect(view.graph.code, CodeCheck.matches);
    expect(view.stepId, 'a1b2-collect-0');
  });
}
