import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_ui/graph/canvas/graph_canvas.dart';
import 'package:nanoflow_ui/graph/graph_screen.dart';
import 'package:nanoflow_ui/graph/logs/effect_details_pane.dart';
import 'package:nanoflow_ui/graph/logs/effect_list.dart';
import 'package:nanoflow_ui/graph/logs/logs_panel.dart';
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

  testWidgets('the title counts the effects of the session', (tester) async {
    await pumpReview(tester);
    expect(textIn(tester, title()), 'Logs 6 effects');
  });

  testWidgets('holds the effects on the left and the selected effect on the '
      'right, under the canvas, as the mockup does', (tester) async {
    await pumpReview(tester);

    expect(
      tester.getRect(find.byKey(GraphScreen.logsKey)),
      const Rect.fromLTRB(272, 621, 1440, 900),
    );
    expect(tester.getRect(find.byType(GraphCanvas)).bottom, 620);
    expect(
      tester.getRect(find.byType(EffectList)),
      const Rect.fromLTRB(272, 621 + 38, 272 + 547, 900),
    );
    expect(
      tester.getRect(find.byType(EffectDetailsPane)),
      const Rect.fromLTRB(272 + 548, 621 + 38, 1440, 900),
    );
  });

  testWidgets('is empty for Current graph', (tester) async {
    final model = await pumpReview(tester);
    model.selection.showCurrentGraph();
    await tester.pump();

    expect(textIn(tester, title()), 'Logs');
    expect(find.byType(EffectList), findsNothing);
    expect(find.byType(EffectDetailsPane), findsNothing);
  });

  testWidgets('folds to its title with the chevron, and unfolds', (
    tester,
  ) async {
    await pumpReview(tester);

    await tester.tap(find.byKey(LogsPanel.toggleKey));
    await tester.pump();
    expect(find.byType(EffectList), findsNothing);
    expect(
      tester.getRect(find.byKey(GraphScreen.logsKey)),
      const Rect.fromLTRB(272, 900 - 38, 1440, 900),
    );
    expect(tester.getRect(find.byType(GraphCanvas)).bottom, 900 - 39);

    await tester.tap(find.byKey(LogsPanel.toggleKey));
    await tester.pump();
    expect(find.byType(EffectList), findsOneWidget);
    expect(tester.getRect(find.byType(GraphCanvas)).bottom, 620);
  });
}
