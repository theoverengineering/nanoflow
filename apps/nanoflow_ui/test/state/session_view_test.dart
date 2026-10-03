import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_ui/state/body_path.dart';
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
    expect(view.step!.name, 'collect');
    expect(view.logs.header.text, '2 steps');
    expect(view.logs.rows, hasLength(2));
    expect(view.marks, isNull, reason: 'no level drawn');
  });

  group('the session on the levels drawn (spec §9 «Шаги на графе»)', () {
    final file = copiesGraphFile();
    final inPlace = file.functions['lib/copies.dart#inPlace']!;

    /// inPlace over core and tool, tool's verify running.
    Journal journal() =>
        Journal('a1b2-session', workflow: 'inPlace', graph: copiesGraphJson())
          ..step('plan', 1, end: 2, place: copiesAt(4), key: 'p', after: null)
          ..step('upload', 3, end: 4, place: copiesAt(7), key: 'uc', after: 'p')
          ..step('upload', 3, end: 5, place: copiesAt(7), key: 'ut', after: 'p')
          ..step('verify', 6, place: copiesAt(8), key: 'vt', after: 'ut');

    SessionView viewOf(
      Journal j, {
      List<Opened> path = const [],
      Map<int, String> copies = const {},
      String? stepId,
    }) => SessionView.of(
      j.data,
      now: now,
      documents: noDocuments,
      graphFile: null,
      stepId: stepId,
      levels: bodyLevels(inPlace, file.functions, path),
      copies: copies,
    );

    test('the workflow body: every step in Logs, those in copies named by '
        'their copy; the marks of its nodes', () {
      final view = viewOf(journal());
      expect(view.shown.frames, isEmpty);
      expect(view.logs.header.text, '4 steps');
      expect(view.marks!.of('2')!.copies, 2);
      expect(view.logs.rows.whereType<StepRow>().map((row) => row.copy), [
        null,
        'pkg 1',
        'pkg 2',
        'pkg 2',
      ]);
    });

    test('the body of the copies, all of them: Logs name the copy of each '
        'step', () {
      final view = viewOf(journal(), path: const [Opened('2')]);
      expect(view.shown.frames.single.footer, 'done 1 of 2');
      expect(view.logs.rows.whereType<StepRow>().map((row) => row.copy), [
        null,
        'pkg 1',
        'pkg 2',
        'pkg 2',
      ]);
      expect(view.marks!.of('2')!.running, 1);
    });

    test('one copy: Logs and the marks show its steps alone', () {
      final j = journal();
      final view = viewOf(
        j,
        path: const [Opened('2')],
        copies: {1: j.steps[2].id},
        stepId: j.steps[3].id,
      );
      expect(view.logs.header.text, 'pkg 2 · 2 steps');
      expect(view.logs.rows.whereType<EndRow>(), isEmpty);
      expect(view.marks!.of('1')!.steps, 1);
      expect(view.marks!.selected, {'2'});
      expect(view.copyOf(j.steps[3].id), 'pkg 2');
    });
  });
}
