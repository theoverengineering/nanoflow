import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_ui/graph/logs/logs_panel.dart';
import 'package:nanoflow_ui/graph/logs/step_details_pane.dart';
import 'package:nanoflow_ui/graph/logs/step_list.dart';
import 'package:nanoflow_ui/platform/shell.dart';
import 'package:nanoflow_ui/state/clock.dart';
import 'package:nanoflow_ui/theme.dart';

import '../../state/support.dart';
import '../../support/golden.dart';
import '../canvas/support.dart';
import '../support.dart';
import 'support.dart';

void main() {
  Finder pane() => find.byType(StepDetailsPane);
  Finder inPane(Finder finder) => find.descendant(of: pane(), matching: finder);
  Finder tab(StepTab tab) => find.byKey(StepDetailsPane.tabKey(tab));

  Color? fillOf(WidgetTester tester, StepTab which) =>
      (tester.widget<Container>(tab(which)).decoration as BoxDecoration?)
          ?.color;

  Future<void> open(WidgetTester tester, StepTab which) async {
    await tester.tap(tab(which));
    await tester.pump();
    await tester.pump();
  }

  Future<void> selectRow(WidgetTester tester, String stepId) async {
    await tester.tap(find.byKey(StepList.rowKey(stepId)));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('names the step, and shows its log first: notify, Output, '
      'Log, following tail, Open — a step has no input', (tester) async {
    await pumpReview(tester);

    expect(
      textIn(tester, find.byKey(StepDetailsPane.headerKey)),
      'notify Output Log following tail Open',
    );
    expect(fillOf(tester, StepTab.log), AppColors.selectedTab);
    expect(fillOf(tester, StepTab.output), isNull);
    expect(inPane(find.text('2 findings, 3 subscribers')), findsOneWidget);
  });

  testWidgets('shows the output as JSON', (tester) async {
    await pumpReview(tester);
    await selectRow(tester, 'a1b2-inspect-3');

    await open(tester, StepTab.output);
    expect(fillOf(tester, StepTab.output), AppColors.selectedTab);
    for (final line in [
      '{',
      '  "change": {',
      '    "path": "lib/parse_config.dart"',
      '  "findings": []',
    ]) {
      expect(inPane(find.text(line)), findsOneWidget, reason: line);
    }
  });

  testWidgets('a running step has no output yet', (tester) async {
    await pumpReview(tester);

    await open(tester, StepTab.output);
    expect(
      inPane(find.text('Not yet: the step is still running')),
      findsOneWidget,
    );
  });

  testWidgets("a failed step's output is its error", (tester) async {
    final session = reviewSession()
      ..step(
        'inspect',
        700,
        end: 701,
        failed: true,
        place: 'lib/review.dart:55',
      );
    await pumpReview(
      tester,
      model: ownedModel(
        graph: graphFileNamed('review'),
        file: reviewFile,
        changes: session.changes,
      ),
    );
    await selectRow(tester, 'a1b2-inspect-6');

    await open(tester, StepTab.output);
    expect(
      inPane(find.text('Failed: StateError: inspect failed')),
      findsOneWidget,
    );
  });

  testWidgets('says why a document cannot be read', (tester) async {
    await pumpReview(tester, model: reviewModel(files: FakeFiles()));
    await selectRow(tester, 'a1b2-inspect-3');

    await open(tester, StepTab.output);
    expect(
      inPane(find.textContaining('Could not read the document: ')),
      findsOneWidget,
    );
  });

  testWidgets('keeps the open tab as another step is selected', (tester) async {
    await pumpReview(tester);
    await selectRow(tester, 'a1b2-inspect-3');
    await open(tester, StepTab.output);

    await selectRow(tester, 'a1b2-collect-0');
    expect(fillOf(tester, StepTab.output), AppColors.selectedTab);
    expect(inPane(find.text('  "id": "c4f1a9",')), findsOneWidget);
  });

  testWidgets('Open opens the step', (tester) async {
    final opened = <String>[];
    final model = modelOf(
      graph: graphFileNamed('review'),
      file: reviewFile,
      changes: reviewSession().changes,
      documents: reviewDocuments,
      files: reviewFiles(),
    );
    final clock = LiveClock(now: () => columnNow);
    addTearDown(clock.dispose);
    await pumpScreen(
      tester,
      Scaffold(
        body: LogsPanel(
          model: model,
          clock: clock,
          shell: Shell(),
          graphFile: reviewFile,
          collapsed: false,
          onToggle: () {},
          onRevealNode: (_) {},
          onOpenStep: (step) => opened.add(step.stepId),
        ),
      ),
    );
    await settle(tester);

    await tester.tap(find.byKey(StepDetailsPane.openKey));
    expect(opened, ['a1b2-notify-5']);
  });
}
