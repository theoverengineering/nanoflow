import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_ui/graph/canvas/canvas_bodies.dart' show expandedOf;
import 'package:nanoflow_ui/graph/canvas/canvas_marks.dart';
import 'package:nanoflow_ui/layout/layout.dart';
import 'package:nanoflow_ui/state/body_path.dart';
import 'package:nanoflow_ui/state/effect_places.dart';
import 'package:nanoflow_ui/state/in_place.dart';
import 'package:nanoflow_ui/state/session_view.dart';

import '../../layout/support.dart' show layoutOf, loadGraphFile;
import '../../state/support.dart';

void main() {
  final file = packagesGraphFile();
  final inPlace = file.functions['lib/packages.dart#inPlace']!;

  /// inPlace over core and tool: plan, core's upload done, tool's running.
  Journal journal() =>
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
        ..effect('upload', 3, place: packagesAt(7), key: 'ut', after: 'p');

  CanvasMarks marksOf(List<Opened> path, {String? effectId}) => CanvasMarks.of(
    SessionView.of(
      journal().data,
      now: at(100),
      documents: outcomesOf(const {}),
      graphFile: null,
      levels: bodyLevels(inPlace, file.functions, path),
      effectId: effectId,
    ),
  );

  test('the marks of the effects on the nodes of the level drawn', () {
    final marks = marksOf(const [], effectId: 'a1b2-plan-0');
    expect(marks.isPlain, isFalse);
    expect(marks.node('1')!.state, NodeState.visited);
    expect(marks.node('2')!.state, NodeState.running);
    expect(marks.node('3')!.state, NodeState.notVisited);
    expect(marks.selected('1'), isTrue);
    expect(marks.selected('2'), isFalse);
  });

  test('no fork passed: arrows are plain', () {
    final marks = marksOf(const []);
    final layout = layoutBody(inPlace.body, functions: file.functions);
    for (final edge in layout.edges) {
      expect(marks.edge(edge), Tone.plain);
    }
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
    });
  });

  test('a call expanded in place: its frame\'s own fork, !ok, went by false '
      'to the end of publish(): its arrow to rollback is darker', () {
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
    final frames = inPlaceFrames(
      levels,
      release.functions,
      Expansions()..expand(const [], publish),
    );
    final view = SessionView.of(
      j.data,
      now: at(100),
      documents: outcomesOf(const {}),
      graphFile: null,
      levels: levels,
      // The places of the graph the levels are of: publish's body drawn is
      // the body of a function the workflow calls.
      places: EffectPlaces.of(
        release.workflowNamed('release'),
        release.functions,
      ),
      frames: frames,
    );
    // The arrows of the frame as the canvas lays them out and draws them.
    final inner = layoutBody(
      levels.last.body,
      functions: release.functions,
      expanded: expandedOf(frames),
    ).nodes['5']!.frame!.inner;
    final marks = CanvasMarks.ofFrame(view.scopeOf(const [publish]));
    Tone tone(String from, String to) => marks.edge(
      inner.edges.singleWhere((e) => e.from == from && e.to == to),
    );

    // publish: upload → verify → (!ok ? rollback : end), announce after
    // verify, as `return f.effect('verify', …)` keys it. It ran once, each of
    // its effect nodes holding one effect at most, so an exit of its body can
    // be darker.
    expect(marks.node('3')!.state, NodeState.visited);
    expect(tone('3', '4'), Tone.untaken);
    expect(tone('3', endMarker), Tone.plain);
    expect(tone('2', '3'), Tone.plain);
  });

  test('back arrows are in the plain tone; none without them', () {
    // Review goes back from fix to inspect.
    final back = layoutOf('review').edges.where((edge) => edge.isDashed);
    expect(back, isNotEmpty);
    expect(marksOf(const []).backEdges(back), Tone.plain);
    expect(marksOf(const []).backEdges(const <EdgePath>[]), isNull);
  });

  test('Current graph is plain: no marks', () {
    const plain = CanvasMarks.plain;
    expect(CanvasMarks.of(null), same(plain));
    expect(plain.isPlain, isTrue);
    expect(plain.node('1'), isNull);
    expect(plain.selected('1'), isFalse);
  });
}
