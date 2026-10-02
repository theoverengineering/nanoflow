import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_model/nanoflow_model.dart' hide Route;
import 'package:nanoflow_ui/graph/canvas/graph_canvas.dart';
import 'package:nanoflow_ui/state/graph_model.dart';

import '../../state/support.dart';
import '../../support/golden.dart';
import 'support.dart';

void main() {
  Future<void> pumpCanvas(
    WidgetTester tester,
    GraphModel model, {
    Size size = reviewCanvas,
  }) async {
    await pumpScreen(
      tester,
      GraphCanvas(model: model, now: () => Mockup.now),
      size: size,
    );
    await settle(tester);
  }

  testWidgets('the review graph mid-session (docs/design/graph.png)', (
    tester,
  ) async {
    await pumpCanvas(tester, reviewModel());
    await expectGolden(tester, 'canvas_review');
  });

  testWidgets('the task graph mid-session (docs/design/task-graph.png)', (
    tester,
  ) async {
    await pumpCanvas(tester, taskModel(), size: taskCanvas);
    await expectGolden(tester, 'canvas_task');
  });

  testWidgets('a failed run and a run not started', (tester) async {
    final k7f2 = Journal('k7f2-run', node: 'collect', startedAt: 0)
      ..step('collect', 0, end: 10, output: 'change')
      ..step('is-empty', 10, end: 11, output: 'empty')
      ..step('inspect', 11, end: 20, output: 'report')
      ..step('verdict', 20, end: 21, output: 'verdict')
      ..split(21);
    final c3d4 = Journal(
      'c3d4-run',
      parent: 'k7f2-run',
      node: 'publish',
      startedAt: 21,
    );
    c3d4.fail(c3d4.step('publish', 22, end: 30, exit: 1), 30, 'exited 1');
    final e5f6 = Journal(
      'e5f6-run',
      parent: 'k7f2-run',
      node: 'notify',
      startedAt: 21,
    );
    await pumpCanvas(
      tester,
      modelOf(
        changes: changesOf([k7f2, c3d4, e5f6]),
        outcomes: const {'empty': false, 'verdict': 'accepted'},
      ),
    );
    await expectGolden(tester, 'canvas_failed');
  });

  testWidgets('the review graph as Current graph', (tester) async {
    final model = reviewModel(current: Graph.fromJson(reviewGraph));
    await pumpCanvas(tester, model);
    model.selection.showCurrentGraph();
    await settle(tester);
    await expectGolden(tester, 'canvas_current');
  });
}
