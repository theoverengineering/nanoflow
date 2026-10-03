import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_ui/graph/canvas/graph_canvas.dart';
import 'package:nanoflow_ui/graph/graph_screen.dart';
import 'package:nanoflow_ui/graph/logs/logs_panel.dart';
import 'package:nanoflow_ui/graph/logs/step_details_pane.dart';
import 'package:nanoflow_ui/graph/logs/step_list.dart';
import 'package:nanoflow_ui/state/graph_model.dart';

import '../support.dart';
import 'support.dart';

void main() {
  Finder title() => find.byKey(LogsPanel.titleKey);

  Future<GraphModel> pumpReview(WidgetTester tester) => pumpGraphScreen(
    tester,
    path: reviewFile,
    model: reviewModel(),
    now: () => columnNow,
  );

  testWidgets('the title counts the steps of the session', (tester) async {
    await pumpReview(tester);
    expect(textIn(tester, title()), 'Logs 6 steps');
  });

  testWidgets('holds the steps on the left and the selected step on the '
      'right, under the canvas, as the mockup does', (tester) async {
    await pumpReview(tester);

    expect(
      tester.getRect(find.byKey(GraphScreen.logsKey)),
      const Rect.fromLTRB(272, 621, 1440, 900),
    );
    expect(tester.getRect(find.byType(GraphCanvas)).bottom, 620);
    expect(
      tester.getRect(find.byType(StepList)),
      const Rect.fromLTRB(272, 621 + 38, 272 + 547, 900),
    );
    expect(
      tester.getRect(find.byType(StepDetailsPane)),
      const Rect.fromLTRB(272 + 548, 621 + 38, 1440, 900),
    );
  });

  testWidgets('is empty for Current graph', (tester) async {
    final model = await pumpReview(tester);
    model.selection.showCurrentGraph();
    await tester.pump();

    expect(textIn(tester, title()), 'Logs');
    expect(find.byType(StepList), findsNothing);
    expect(find.byType(StepDetailsPane), findsNothing);
  });

  testWidgets('folds to its title with the chevron, and unfolds', (
    tester,
  ) async {
    await pumpReview(tester);

    await tester.tap(find.byKey(LogsPanel.toggleKey));
    await tester.pump();
    expect(find.byType(StepList), findsNothing);
    expect(
      tester.getRect(find.byKey(GraphScreen.logsKey)),
      const Rect.fromLTRB(272, 900 - 38, 1440, 900),
    );
    expect(tester.getRect(find.byType(GraphCanvas)).bottom, 900 - 39);

    await tester.tap(find.byKey(LogsPanel.toggleKey));
    await tester.pump();
    expect(find.byType(StepList), findsOneWidget);
    expect(tester.getRect(find.byType(GraphCanvas)).bottom, 620);
  });
}
