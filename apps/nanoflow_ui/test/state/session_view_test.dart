import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_ui/state/body_path.dart';
import 'package:nanoflow_ui/state/effect_places.dart';
import 'package:nanoflow_ui/state/in_place.dart';
import 'package:nanoflow_ui/state/session_view.dart';

import '../layout/support.dart' show loadGraphFile;
import 'support.dart';

void main() {
  final now = at(746);
  final noDocuments = outcomesOf(const {});

  /// The graph file as it is now: the review workflow's effect is `gather`.
  final graphFile = reviewGraphFile(
    fingerprint: 'sha256:now',
    reviewEffect: 'gather',
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
          'snapshot-1': graphFileJson(reviewEffect: 'first'),
          'snapshot-2': graphFileJson(reviewEffect: 'second'),
        },
      );
      expect(graph.graph, reviewGraphFile(reviewEffect: 'second'));
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

    test('of a resume whose snapshot is null — there was no graph file then '
        '— is the graph file, marked as without a snapshot, and the code '
        'is checked against it', () {
      final session = Journal('a1b2-session')
        ..resume(10, code: 'sha256:now', graphId: 'snap');
      final graph = graphOf(session, documents: {'snap': null});
      expect(graph.graph, same(graphFile));
      expect(graph.noSnapshot, isTrue);
      expect(graph.unreadable, isFalse);
      expect(graph.code, CodeCheck.matches);
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
      ..effect('collect', 1, end: 149)
      ..effect('inspect', 150);
    final view = SessionView.of(
      session.data,
      now: now,
      documents: noDocuments,
      graphFile: graphFile,
      effectId: 'a1b2-collect-0',
    );
    expect(view.summary!.statusText, 'Running for 12m 26s');
    expect(view.graph.graph, reviewGraphFile());
    expect(view.graph.code, CodeCheck.matches);
    expect(view.effectId, 'a1b2-collect-0');
    expect(view.effect!.name, 'collect');
    expect(view.logs.header.text, '2 effects');
    expect(view.logs.rows, hasLength(2));
    expect(view.marks, isNull, reason: 'no level drawn');
  });

  test('the session on the workflow body drawn: every effect in Logs, each '
      'run of a call on one row; the marks of its nodes (spec §9 «Эффекты на '
      'графе»)', () {
    final file = packagesGraphFile();
    final inPlace = file.functions['lib/packages.dart#inPlace']!;
    // inPlace over core and tool, tool's verify running.
    final j =
        Journal('a1b2-session', workflow: 'inPlace', graph: packagesGraphJson())
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
          ..effect('verify', 6, place: packagesAt(8), key: 'vt', after: 'ut');
    final view = SessionView.of(
      j.data,
      now: now,
      documents: noDocuments,
      graphFile: null,
      levels: bodyLevels(inPlace, file.functions, const []),
    );
    expect(view.logs.header.text, '4 effects');
    expect(view.logs.rows.whereType<EffectRow>(), hasLength(1));
    expect(view.logs.rows.whereType<RunRow>(), hasLength(2));
    expect(view.marks!.of('2')!.effects, 3);
  });

  group('frames drawn in place (decision 6)', () {
    final file = packagesGraphFile();
    final inPlace = file.functions['lib/packages.dart#inPlace']!;
    const ship = Opened('2', functionId: 'lib/packages.dart#ship');

    /// inPlace over core and tool, tool's verify running.
    Journal journal() =>
        Journal('a1b2-session', workflow: 'inPlace', graph: packagesGraphJson())
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
          ..effect('verify', 6, place: packagesAt(8), key: 'vt', after: 'ut');

    /// The top level of inPlace drawn, the nodes [expansions] has expanded
    /// in place — by default its call of ship().
    SessionView viewOf(Journal j, {Expansions? expansions, String? effectId}) {
      final levels = bodyLevels(inPlace, file.functions, const []);
      return SessionView.of(
        j.data,
        now: now,
        documents: noDocuments,
        graphFile: null,
        effectId: effectId,
        levels: levels,
        frames: inPlaceFrames(
          levels,
          file.functions,
          expansions ?? (Expansions()..expand(const [], ship)),
        ),
      );
    }

    test('a call in place shows what its function\'s body shows when opened: '
        'the effects of every run on each node', () {
      final view = viewOf(journal());
      final scope = view.scopeOf(const [ship])!;
      expect(scope.marks.of('1')!.effects, 2);
      expect(scope.marks.of('2')!.state, NodeState.running);
      // The level drawn and Logs are as without the frame.
      expect(view.marks!.of('2')!.effects, 3);
      expect(view.logs.header.text, '4 effects');
    });

    test('the selected effect is ringed in its frame, and is found there to '
        'be revealed', () {
      final j = journal();
      final view = viewOf(j, effectId: j.effects[3].id);
      expect(view.scopeOf(const [ship])!.marks.selected, {'2'});
      expect(view.revealPathOf(j.effects[3].id), ['2', '2']);
      expect(view.revealPathOf(j.effects[0].id), ['1']);
      final collapsed = viewOf(j, expansions: Expansions());
      expect(collapsed.revealPathOf(j.effects[3].id), ['2']);
    });

    test('a call in place marks its function\'s effects on their nodes, the '
        'selected one ringed', () {
      final release = loadGraphFile('release');
      const publish = Opened('5', functionId: 'lib/publish.dart#publish');
      final j =
          Journal('r1r1-session', workflow: 'release', graph: release.toJson())
            ..effect('plan', 1, end: 2, place: 'lib/release.dart:16')
            ..effect('upload', 3, end: 4, place: 'lib/publish.dart:12')
            ..effect('verify', 5, place: 'lib/publish.dart:13');
      final levels = bodyLevels(
        release.workflowNamed('release')!,
        release.functions,
        const [],
      );
      final view = SessionView.of(
        j.data,
        now: now,
        documents: noDocuments,
        graphFile: null,
        effectId: j.effects[2].id,
        levels: levels,
        frames: inPlaceFrames(
          levels,
          release.functions,
          Expansions()..expand(const [], publish),
        ),
      );
      final scope = view.scopeOf(const [publish])!;
      expect(scope.marks.of('1')!.state, NodeState.visited);
      expect(scope.marks.of('2')!.state, NodeState.running);
      expect(scope.marks.of('4')!.state, NodeState.notVisited);
      expect(scope.marks.selected, {'2'});
      // The level drawn has them in the call.
      expect(view.marks!.of('5')!.state, NodeState.running);
      expect(view.revealPathOf(j.effects[2].id), ['5', '2']);
    });

    test('a call in place has the forks of what it shows: the code left '
        'publish() by !ok false; the level drawn has its own', () {
      final release = loadGraphFile('release');
      const publish = Opened('5', functionId: 'lib/publish.dart#publish');
      final j =
          Journal('r1r1-session', workflow: 'release', graph: release.toJson())
            ..effect('plan', 1, end: 2, place: 'lib/release.dart:16')
            ..effect('build', 3, end: 4, place: 'lib/release.dart:18')
            ..effect('upload', 5, end: 6, place: 'lib/publish.dart:12')
            ..effect('verify', 7, end: 8, place: 'lib/publish.dart:13')
            ..effect('announce', 9, place: 'lib/release.dart:23');
      final levels = bodyLevels(
        release.workflowNamed('release')!,
        release.functions,
        const [],
      );
      final view = SessionView.of(
        j.data,
        now: now,
        documents: noDocuments,
        graphFile: null,
        levels: levels,
        // The places of the graph the levels are of: publish's body drawn is
        // the body of a function the workflow calls.
        places: EffectPlaces.of(
          release.workflowNamed('release'),
          release.functions,
        ),
        frames: inPlaceFrames(
          levels,
          release.functions,
          Expansions()..expand(const [], publish),
        ),
      );
      final scope = view.scopeOf(const [publish])!;
      // publish: upload → verify → (!ok ? rollback : end), announce after
      // verify, as `return f.effect('verify', …)` keys it. It ran once, each
      // of its effect nodes holding one effect at most, so an exit of its
      // body can be darker.
      final body = scope.frame.level.body;
      expect(scope.marks.of('3')!.state, NodeState.visited);
      expect(scope.marks.of('3')!.effects, 1);
      expect(
        scope.marks.passes.untaken(
          body.edges.indexWhere((e) => e.from == '3' && e.to == '4'),
        ),
        isTrue,
      );
      // release: plan → (for pkg ? build → (isPublic ? publish() → loop :
      // loop) : switch → announce | notify-testers).
      expect(view.marks!.of('2')!.effects, 2);
      expect(view.marks!.of('4')!.effects, 1);
      expect(view.marks!.of('6')!.effects, 1);
      expect(view.marks!.passes.of('3'), 0);
    });
  });
}
