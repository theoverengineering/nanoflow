import 'package:flutter/rendering.dart' show debugDisableShadows;
import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_model/nanoflow_model.dart' hide Route;
import 'package:nanoflow_ui/graph/canvas/node_tile.dart';

import '../../state/support.dart';
import '../../support/golden.dart';
import '../canvas/support.dart';
import '../support.dart';

/// [Mockup] with the second step on `inspect` at the times of
/// docs/design/step-details.png: started at 14:09:20.118, interrupted, again
/// at 14:11:47, finished at 14:13:22.406.
Mockup _stepDetailsMockup() {
  final mockup = Mockup();
  final events = mockup.k7f2.events;
  final starts = [at(369.118), at(516)];
  for (final (i, event) in events.indexed) {
    switch (event) {
      case StepStarted(stepId: 'k7f2-inspect-5', :final runId, :final node):
        events[i] = StepStarted(
          runId: runId,
          time: starts.removeAt(0),
          stepId: 'k7f2-inspect-5',
          node: node,
        );
      case StepFinished(
        stepId: 'k7f2-inspect-5',
        :final runId,
        :final exitCode,
        :final outputId,
      ):
        events[i] = StepFinished(
          runId: runId,
          time: at(611.406),
          stepId: 'k7f2-inspect-5',
          exitCode: exitCode,
          outputId: outputId,
        );
      default:
    }
  }
  return mockup;
}

void main() {
  testWidgets('the step details window on inspect\'s second visit '
      '(docs/design/step-details.png)', (tester) async {
    // The window's shadow, which tests leave out unless told; set back
    // before the test ends, or the test fails.
    debugDisableShadows = false;
    try {
      await _pumpWindow(tester);
      await expectGolden(tester, 'step_details');
    } finally {
      debugDisableShadows = true;
    }
  });
}

/// The graph screen of [_stepDetailsMockup] with the step details window
/// open on inspect's second visit, its documents those of the mockup.
Future<void> _pumpWindow(WidgetTester tester) async {
  final mockup = _stepDetailsMockup();
  const change = {'id': 'c4f1a9', 'path': 'src/engine/step.ts'};
  final files = mockupFiles()
    ..documents['change-2'] = change
    ..documents['report-2'] = const {
      'change': change,
      'findings': [
        'Writes no output.json on exit code 0',
        'Timeout is absent from the protocol',
      ],
    }
    ..stepPaths['k7f2-inspect-5'] = mockupStepDir(
      'k7f2-run',
      0,
      'inspect',
      'k7f2-inspect-5',
      369.118,
    );
  await pumpGraphScreen(
    tester,
    model: ownedModel(
      current: Graph.fromJson(reviewGraph),
      changes: changesOf([mockup.k7f2, mockup.c3d4, mockup.e5f6]),
      outcomes: reviewOutcomes,
      files: files,
    ),
  );

  final tile = find.byKey(NodeTile.tileKeyOf('inspect'));
  await tester.tap(tile);
  await tester.pump(const Duration(milliseconds: 60));
  await tester.tap(tile);
  await settle(tester);
}
