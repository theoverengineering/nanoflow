import 'package:flutter/rendering.dart' show debugDisableShadows;
import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_ui/graph/canvas/node_tile.dart';

import '../../state/support.dart';
import '../../support/golden.dart';
import '../canvas/support.dart';
import '../support.dart';

void main() {
  testWidgets("the step details window on inspect's second visit "
      '(docs/design/step-details.png, without the input)', (tester) async {
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

/// The graph screen of [reviewSession] with the second step on `inspect`
/// at the times of docs/design/step-details.png — started at
/// 14:09:20.118, interrupted, again at 14:11:47, finished at 14:13:22.406
/// — and the step details window open on it.
Future<void> _pumpWindow(WidgetTester tester) async {
  final graph = graphFileNamed('review');
  String place(int line) => 'lib/review.dart:$line';
  final session =
      Journal('a1b2-session', graph: graph.toJson(), code: graph.fingerprint)
        ..step('collect', 0, end: 149, output: 'change-1', place: place(49))
        ..step('inspect', 150, end: 342, output: 'report-1', place: place(55))
        ..step('fix', 343, end: 369, output: 'change-2', place: place(63))
        ..step(
          'inspect',
          369.118,
          end: 611.406,
          output: 'report-2',
          place: place(55),
          restarts: [516],
        )
        ..step('publish', 612, end: 613, output: 'published', place: place(58))
        ..step('notify', 612, place: place(59));
  final files = reviewFiles()
    ..stepPaths['a1b2-inspect-3'] = reviewStepDir(
      'inspect',
      'a1b2-inspect-3',
      369.118,
    );
  await pumpReview(
    tester,
    model: ownedModel(
      graph: graph,
      file: reviewFile,
      changes: session.changes,
      documents: reviewDocuments,
      files: files,
    ),
  );

  final tile = find.byKey(NodeTile.tileKeyOf('4'));
  await tester.tap(tile);
  await tester.pump(const Duration(milliseconds: 60));
  await tester.tap(tile);
  await settle(tester);
}
