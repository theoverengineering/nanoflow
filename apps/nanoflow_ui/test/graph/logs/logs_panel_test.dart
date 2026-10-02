import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_ui/graph/canvas/graph_canvas.dart';
import 'package:nanoflow_ui/graph/graph_screen.dart';
import 'package:nanoflow_ui/graph/logs/logs_panel.dart';
import 'package:nanoflow_ui/graph/logs/step_details_pane.dart';
import 'package:nanoflow_ui/graph/logs/step_list.dart';
import 'package:nanoflow_ui/graph/run_switcher.dart';

import '../support.dart';
import 'support.dart';

void main() {
  Finder title() => find.byKey(LogsPanel.titleKey);

  testWidgets('the title names the selected run and its steps: run e5f6 · 8 '
      'steps, 7 inherited from k7f2', (tester) async {
    await pumpGraphScreen(tester);

    expect(
      textIn(tester, title()),
      'Logs run e5f6 · 8 steps, 7 inherited from k7f2',
    );
    expect(
      find.descendant(of: title(), matching: find.byTooltip('e5f6-run')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: title(), matching: find.byTooltip('k7f2-run')),
      findsOneWidget,
    );
  });

  testWidgets('a root run\'s title has no inherited steps: run k7f2 · 7 '
      'steps', (tester) async {
    await pumpGraphScreen(tester);
    await tester.tap(find.byKey(RunSwitcher.pillKey('k7f2-run')));
    await tester.pump();

    expect(textIn(tester, title()), 'Logs run k7f2 · 7 steps');
  });

  testWidgets('holds the steps on the left and the selected step on the '
      'right, as the mockup does', (tester) async {
    await pumpGraphScreen(tester);

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
    final model = await pumpGraphScreen(tester);
    model.selection.showCurrentGraph();
    await tester.pump();

    expect(textIn(tester, title()), 'Logs');
    expect(find.byType(StepList), findsNothing);
    expect(find.byType(StepDetailsPane), findsNothing);
  });

  testWidgets('folds to its title with the chevron, and unfolds', (
    tester,
  ) async {
    await pumpGraphScreen(tester);

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
