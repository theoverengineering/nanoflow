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

  testWidgets('names the step, and shows its log first: notify, Input, '
      'Output —, Log, following tail, Open', (tester) async {
    await pumpGraphScreen(tester);

    expect(
      textIn(tester, find.byKey(StepDetailsPane.headerKey)),
      'notify Input Output — Log following tail Open',
    );
    expect(fillOf(tester, StepTab.log), AppColors.selectedTab);
    expect(fillOf(tester, StepTab.input), isNull);
    expect(inPane(find.text('2 findings, 3 subscribers')), findsOneWidget);
  });

  testWidgets('marks — the tab of data the node does not declare, and says '
      'so in it', (tester) async {
    await pumpGraphScreen(tester);

    expect(textIn(tester, tab(StepTab.output)), 'Output —');
    expect(textIn(tester, tab(StepTab.input)), 'Input');

    await open(tester, StepTab.output);
    expect(fillOf(tester, StepTab.output), AppColors.selectedTab);
    expect(inPane(find.text('This node declares no output')), findsOneWidget);
  });

  testWidgets('shows the input as JSON', (tester) async {
    await pumpGraphScreen(tester);

    await open(tester, StepTab.input);
    for (final line in [
      '{',
      '  "change": {',
      '    "id": "c4f1b0",',
      '  "findings": [',
      '    "Timeout is absent from the protocol"',
      '  },',
    ]) {
      expect(inPane(find.text(line)), findsOneWidget, reason: line);
    }
  });

  testWidgets('a fork\'s output is its outcome', (tester) async {
    await pumpGraphScreen(tester);
    await selectRow(tester, 'k7f2-verdict-6');

    await open(tester, StepTab.output);
    expect(
      textIn(tester, find.byKey(StepDetailsPane.headerKey)),
      startsWith('verdict Input Output Log'),
    );
    expect(inPane(find.text('"accepted"')), findsOneWidget);
  });

  testWidgets('a running step has no output yet', (tester) async {
    final run = Journal('runs-run', node: 'collect', startedAt: 0)
      ..step('collect', 0, end: 10, input: 'request', output: 'change-1')
      ..step('inspect', 10, input: 'change-1');
    await pumpGraphScreen(
      tester,
      model: ownedModel(changes: changesOf([run]), files: mockupFiles()),
    );

    await open(tester, StepTab.output);
    expect(textIn(tester, tab(StepTab.output)), 'Output');
    expect(
      inPane(find.text('Not yet: the step is still running')),
      findsOneWidget,
    );
  });

  testWidgets('says why a document cannot be read', (tester) async {
    await pumpGraphScreen(tester, model: mockupModel(files: FakeFiles()));

    await open(tester, StepTab.input);
    expect(
      inPane(find.textContaining('Could not read the document: ')),
      findsOneWidget,
    );
  });

  testWidgets('keeps the open tab as another step is selected', (tester) async {
    await pumpGraphScreen(tester);
    await open(tester, StepTab.input);

    await selectRow(tester, 'k7f2-collect-0');
    expect(fillOf(tester, StepTab.input), AppColors.selectedTab);
    expect(
      inPane(find.text('  "branch": "feat/step-protocol"')),
      findsOneWidget,
    );
  });

  testWidgets('Open opens the step', (tester) async {
    final opened = <String>[];
    final mockup = Mockup();
    final model = modelOf(
      changes: changesOf([mockup.k7f2, mockup.c3d4, mockup.e5f6]),
      outcomes: reviewOutcomes,
      files: mockupFiles(),
    );
    final clock = LiveClock(now: () => Mockup.now);
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
    expect(opened, ['e5f6-notify-0']);
  });
}
