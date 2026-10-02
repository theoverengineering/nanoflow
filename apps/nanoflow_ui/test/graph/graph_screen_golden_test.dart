import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_model/nanoflow_model.dart' hide Route;
import 'package:nanoflow_ui/state/graph_source.dart';

import '../state/support.dart';
import '../support/golden.dart';
import 'canvas/support.dart';
import 'support.dart';

void main() {
  testWidgets('the review graph mid-session (docs/design/graph.png)', (
    tester,
  ) async {
    await pumpGraphScreen(tester);
    await expectGolden(tester, 'graph_review');
  });

  testWidgets('the task graph waiting on a person '
      '(docs/design/task-graph.png)', (tester) async {
    await pumpGraphScreen(
      tester,
      path: taskFile,
      model: taskMockupModel(),
      now: () => taskNow,
      size: const Size(2000, 1000),
    );
    await expectGolden(tester, 'graph_task');
  });

  testWidgets('Current graph failing check, its program exited', (
    tester,
  ) async {
    final model = await pumpGraphScreen(tester);
    model.selection.showCurrentGraph();
    sourceOf(model)
      ..errors = const [
        'nodes.verdict.then.accepted[0]: no node named "pubish"',
        'nodes.fix.command: expected a string, got 12',
      ]
      ..programProblem = const SourceProblem(
        'nanoflow-yaml exited with code 255',
        'Unhandled exception:\n'
            'FileSystemException: Cannot open file, path = review.yaml',
      );
    await settle(tester);
    await expectGolden(tester, 'graph_errors');
  });

  testWidgets('a run failed, a run not started, a log read incompletely', (
    tester,
  ) async {
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
    await pumpGraphScreen(
      tester,
      model: ownedModel(
        changes: [
          ...changesOf([k7f2, c3d4, e5f6]),
          const LogCorrupted(runId: 'k7f2-run', line: 9, text: '{"event":'),
        ],
        outcomes: const {'empty': false, 'verdict': 'accepted'},
      ),
    );
    // The failed step's log is empty, and says so after a moment.
    await tester.pump(const Duration(milliseconds: 300));
    await expectGolden(tester, 'graph_failed');
  });
}
