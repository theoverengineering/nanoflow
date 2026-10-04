import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_ui/graph/canvas/canvas_marks.dart';
import 'package:nanoflow_ui/layout/layout.dart';
import 'package:nanoflow_ui/state/body_path.dart';
import 'package:nanoflow_ui/state/effect_places.dart';
import 'package:nanoflow_ui/state/session_view.dart';

import '../../layout/support.dart' show layoutOf;
import '../../state/support.dart';

void main() {
  final file = copiesGraphFile();
  final inPlace = file.functions['lib/copies.dart#inPlace']!;

  /// inPlace over core and tool: plan, core's upload done, tool's running.
  Journal journal() =>
      Journal('a1b2-session', workflow: 'inPlace', graph: copiesGraphJson())
        ..effect('plan', 1, end: 2, place: copiesAt(4), key: 'p', after: null)
        ..effect('upload', 3, end: 4, place: copiesAt(7), key: 'uc', after: 'p')
        ..effect('upload', 3, place: copiesAt(7), key: 'ut', after: 'p');

  CanvasMarks marksOf(
    List<Opened> path, {
    Map<int, String> copies = const {},
    String? effectId,
  }) {
    final levels = bodyLevels(inPlace, file.functions, path);
    return CanvasMarks.of(
      SessionView.of(
        journal().data,
        now: at(100),
        documents: outcomesOf(const {}),
        graphFile: null,
        levels: levels,
        copies: copies,
        effectId: effectId,
      ),
      depth: levels.length - 1,
    );
  }

  test('the marks of the effects on the nodes of the level drawn', () {
    final marks = marksOf(const [], effectId: 'a1b2-plan-0');
    expect(marks.isPlain, isFalse);
    expect(marks.node('1')!.state, NodeState.visited);
    expect(marks.node('2')!.state, NodeState.running);
    expect(marks.node('3')!.state, NodeState.notVisited);
    expect(marks.selected('1'), isTrue);
    expect(marks.selected('2'), isFalse);
  });

  test('copies say how many copies ran', () {
    expect(marksOf(const []).copies('2'), '×2');
  });

  test('copies none of which ran yet say ×0', () {
    final marks = CanvasMarks.of(
      SessionView.of(
        Journal(
          'b2c3-session',
          workflow: 'inPlace',
          graph: copiesGraphJson(),
        ).data,
        now: at(100),
        documents: outcomesOf(const {}),
        graphFile: null,
        levels: bodyLevels(inPlace, file.functions, const []),
      ),
      depth: 0,
    );
    expect(marks.copies('2'), '×0');
  });

  test('in the body of copies, all shown, effects count the copies on them; '
      'one copy shown, not', () {
    expect(marksOf(const [Opened('2')]).allCopies, isTrue);
    expect(marksOf(const [Opened('2')]).node('1')!.running, 1);
    expect(marksOf(const []).allCopies, isFalse);
    expect(
      marksOf(const [Opened('2')], copies: {1: 'a1b2-upload-2'}).allCopies,
      isFalse,
    );
  });

  test(
    'no fork passed and no copy chosen: arrows, exits and bars are plain',
    () {
      final marks = marksOf(const []);
      final layout = layoutBody(inPlace.body, functions: file.functions);
      for (final edge in layout.edges) {
        expect(marks.edge(edge), Tone.plain);
      }
      expect(marks.exit('1'), Tone.plain);
      expect(marks.bar('2'), Tone.plain);
    },
  );

  test('one copy shown: what leads to or from a node it has not reached is '
      'darker (docs/design/code-first/copy-switcher.html)', () {
    // Tool's upload runs: verify and tag are not reached.
    final marks = marksOf(const [Opened('2')], copies: {1: 'a1b2-upload-2'});
    final frame = inPlace.body.node('2')! as CopiesNode;
    final layout = layoutBody(frame.body, functions: file.functions);
    EdgePath edge(String from, String to) =>
        layout.edges.firstWhere((e) => e.from == from && e.to == to);
    expect(marks.edge(edge('(start)', '1')), Tone.plain);
    expect(marks.edge(edge('1', '2')), Tone.untaken);
    expect(marks.edge(edge('2', '3')), Tone.untaken);
    expect(marks.edge(edge('3', '(end)')), Tone.untaken);
    expect(marks.exit('1'), Tone.plain);
    expect(marks.exit('2'), Tone.untaken);
    expect(marks.bar('1'), Tone.plain);
    expect(marks.bar('2'), Tone.untaken);
    // All copies shown: plain.
    final all = marksOf(const [Opened('2')]);
    expect(all.edge(edge('2', '3')), Tone.plain);
    expect(all.bar('3'), Tone.plain);
  });

  /// The tone [marks] give the arrow of [body] from [from] to [to], `null`
  /// standing for the body's start or end.
  Tone toneOf(CanvasMarks marks, GraphBody body, String? from, String? to) {
    final index = body.edges.indexWhere((e) => e.from == from && e.to == to);
    final layout = layoutBody(body, functions: file.functions);
    return marks.edge(layout.edges.singleWhere((e) => e.edgeIndex == index));
  }

  group('a passed fork: its exits no way could have taken are darker', () {
    // collect, inspect, fix, inspect, then publish and notify, as the real
    // library wrote them: 2 is `change.path.isEmpty`, 3 discard, 4 inspect,
    // 5 `report.findings.isEmpty`, 6 publish, 7 notify, 8 fix.
    final recorded = recordedReview();
    final review = recorded.graph.functions['lib/review.dart#review']!;
    final marks = CanvasMarks.of(
      SessionView.of(
        recorded.sessions['review']!,
        now: at(100),
        documents: outcomesOf(const {}),
        graphFile: recorded.graph,
        levels: bodyLevels(review, recorded.graph.functions, const []),
        places: EffectPlaces.of(review, recorded.graph.functions),
      ),
      depth: 0,
    );
    Tone tone(String? from, String? to) => toneOf(marks, review.body, from, to);

    test('change.path.isEmpty went by false: true, to discard, is darker', () {
      expect(marks.node('2')!.state, NodeState.visited);
      expect(tone('2', '3'), Tone.untaken);
      expect(tone('2', '4'), Tone.plain);
    });

    test('every other arrow is plain: those the code took, and those of the '
        'end it did not reach as well', () {
      for (final (from, to) in [
        (null, '1'),
        ('1', '2'),
        ('3', null),
        ('4', '5'),
        ('5', '6'),
        ('5', '7'),
        ('5', '8'),
        ('6', null),
        ('7', null),
        ('8', '4'),
      ]) {
        expect(tone(from, to), Tone.plain, reason: '$from>$to');
      }
      expect(marks.exit('2'), Tone.plain);
      expect(marks.bar('3'), Tone.plain);
    });
  });

  group('a fork in the body of copies', () {
    // checked: plan → copies { upload → (ok ? tag : return) } → announce;
    // core uploaded and tagged, tool uploaded.
    const copies = GraphBody(
      nodes: [
        EffectNode(id: '1', place: 'lib/copies.dart:7', name: 'upload'),
        ConditionNode(id: '2', place: 'lib/copies.dart:8', label: 'ok'),
        EffectNode(id: '3', place: 'lib/copies.dart:9', name: 'tag'),
      ],
      edges: [
        GraphEdge(from: null, to: '1', label: null),
        GraphEdge(from: '1', to: '2', label: null),
        GraphEdge(from: '2', to: '3', label: 'true'),
        GraphEdge(from: '2', to: null, label: 'false'),
        GraphEdge(from: '3', to: null, label: null),
      ],
    );
    const checked = GraphFunction(
      id: 'lib/copies.dart#checked',
      name: 'checked',
      place: 'lib/copies.dart:3',
      body: GraphBody(
        nodes: [
          EffectNode(id: '1', place: 'lib/copies.dart:4', name: 'plan'),
          CopiesNode(
            id: '2',
            place: 'lib/copies.dart:5',
            label: 'pkg in plan',
            body: copies,
          ),
          EffectNode(id: '3', place: 'lib/copies.dart:12', name: 'announce'),
        ],
        edges: [
          GraphEdge(from: null, to: '1', label: null),
          GraphEdge(from: '1', to: '2', label: null),
          GraphEdge(from: '2', to: '3', label: null),
          GraphEdge(from: '3', to: null, label: null),
        ],
      ),
    );
    final session =
        (Journal('a1b2-session', workflow: 'checked', snapshot: false)
              ..effect('plan', 1, end: 2, place: copiesAt(4), key: 'p')
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
              ..effect('tag', 6, place: copiesAt(9), key: 'tc', after: 'uc'))
            .data;
    CanvasMarks copiesMarks({String? copy}) => CanvasMarks.of(
      SessionView.of(
        session,
        now: at(100),
        documents: outcomesOf(const {}),
        graphFile: null,
        levels: bodyLevels(checked, {checked.id: checked}, const [Opened('2')]),
        places: EffectPlaces.of(checked, {checked.id: checked}),
        copies: {1: ?copy},
      ),
      depth: 1,
    );

    test('all copies: the fork is visited, but no arrow is darker '
        '(decision 11: no way is highlighted)', () {
      final marks = copiesMarks();
      expect(marks.allCopies, isTrue);
      expect(marks.node('2')!.state, NodeState.visited);
      for (final edge in copies.edges) {
        expect(
          toneOf(marks, copies, edge.from, edge.to),
          Tone.plain,
          reason: '${edge.from}>${edge.to}',
        );
      }
    });

    test('one copy: its own fork\'s untaken exit is darker', () {
      // Core went on to tag: ok was true.
      final marks = copiesMarks(copy: 'a1b2-upload-1');
      expect(marks.node('2')!.state, NodeState.visited);
      expect(toneOf(marks, copies, '2', null), Tone.untaken);
      expect(toneOf(marks, copies, '2', '3'), Tone.plain);
      expect(toneOf(marks, copies, '1', '2'), Tone.plain);
      expect(toneOf(marks, copies, '3', null), Tone.plain);
    });

    test('one copy: what leads to or from a node it has not reached stays '
        'darker as well', () {
      // Tool has not gone past upload: no fork passed, tag not reached.
      final marks = copiesMarks(copy: 'a1b2-upload-2');
      expect(marks.node('2'), isNull);
      expect(toneOf(marks, copies, '2', '3'), Tone.untaken);
      expect(toneOf(marks, copies, '3', null), Tone.untaken);
      expect(toneOf(marks, copies, '2', null), Tone.plain);
      expect(toneOf(marks, copies, '1', '2'), Tone.plain);
    });
  });

  test('back arrows are in the plain tone; none without them', () {
    // Review goes back from fix to inspect.
    final back = layoutOf('review').edges.where((edge) => edge.isDashed);
    expect(back, isNotEmpty);
    expect(marksOf(const []).backEdges(back), Tone.plain);
    expect(marksOf(const []).backEdges(const <EdgePath>[]), isNull);
  });

  test('Current graph is plain: no marks, ×n on copies', () {
    const plain = CanvasMarks.plain;
    expect(CanvasMarks.of(null, depth: 0), same(plain));
    expect(plain.isPlain, isTrue);
    expect(plain.node('1'), isNull);
    expect(plain.selected('1'), isFalse);
    expect(plain.copies('2'), '×n');
  });
}
