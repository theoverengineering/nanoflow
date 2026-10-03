import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_ui/graph/canvas/canvas_marks.dart';
import 'package:nanoflow_ui/layout/layout.dart';
import 'package:nanoflow_ui/state/body_path.dart';
import 'package:nanoflow_ui/state/session_view.dart';

import '../../layout/support.dart' show layoutOf;
import '../../state/support.dart';

void main() {
  final file = copiesGraphFile();
  final inPlace = file.functions['lib/copies.dart#inPlace']!;

  /// inPlace over core and tool: plan, core's upload done, tool's running.
  Journal journal() =>
      Journal('a1b2-session', workflow: 'inPlace', graph: copiesGraphJson())
        ..step('plan', 1, end: 2, place: copiesAt(4), key: 'p', after: null)
        ..step('upload', 3, end: 4, place: copiesAt(7), key: 'uc', after: 'p')
        ..step('upload', 3, place: copiesAt(7), key: 'ut', after: 'p');

  CanvasMarks marksOf(
    List<Opened> path, {
    Map<int, String> copies = const {},
    String? stepId,
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
        stepId: stepId,
      ),
      depth: levels.length - 1,
    );
  }

  test('the marks of the steps on the nodes of the level drawn', () {
    final marks = marksOf(const [], stepId: 'a1b2-plan-0');
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

  test('in the body of copies, all shown, steps count the copies on them; '
      'one copy shown, not', () {
    expect(marksOf(const [Opened('2')]).allCopies, isTrue);
    expect(marksOf(const [Opened('2')]).node('1')!.running, 1);
    expect(marksOf(const []).allCopies, isFalse);
    expect(
      marksOf(const [Opened('2')], copies: {1: 'a1b2-upload-2'}).allCopies,
      isFalse,
    );
  });

  test('a step records no way it took: arrows, exits and bars are plain', () {
    final marks = marksOf(const []);
    final layout = layoutBody(inPlace.body, functions: file.functions);
    for (final edge in layout.edges) {
      expect(marks.edge(edge), Tone.plain);
    }
    expect(marks.exit('1', 0), Tone.plain);
    expect(marks.bar('2', layout.edges.where((e) => e.to == '2')), Tone.plain);
    expect(marks.counter('1', 0), isNull);
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
