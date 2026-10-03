import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_ui/graph/canvas/graph_canvas.dart';
import 'package:nanoflow_ui/state/graph_model.dart';

import '../../support/golden.dart';
import 'support.dart';

void main() {
  Future<void> pumpCanvas(WidgetTester tester, GraphModel model) async {
    await pumpScreen(tester, GraphCanvas(model: model), size: reviewCanvas);
    await settle(tester);
  }

  testWidgets('the review example as Current graph', (tester) async {
    await pumpCanvas(tester, modelOf(graph: graphFileNamed('review')));
    await expectGolden(tester, 'canvas_review');
  });

  testWidgets('a loop over packages, a call and a switch: the release '
      'fixture', (tester) async {
    await pumpCanvas(tester, modelOf());
    await expectGolden(tester, 'canvas_release');
  });

  testWidgets('copies of a body', (tester) async {
    await pumpCanvas(
      tester,
      modelOf(
        graph: GraphFile.fromJson({
          ...graphFileNamed('inline').toJson(),
          'workflows': ['lib/inline.dart#inPlace'],
        }),
      ),
    );
    await expectGolden(tester, 'canvas_copies');
  });
}
