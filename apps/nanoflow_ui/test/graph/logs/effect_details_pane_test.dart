import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_ui/graph/logs/effect_details_pane.dart';
import 'package:nanoflow_ui/graph/logs/effect_list.dart';
import 'package:nanoflow_ui/graph/logs/logs_panel.dart';
import 'package:nanoflow_ui/platform/shell.dart';
import 'package:nanoflow_ui/state/clock.dart';
import 'package:nanoflow_ui/theme.dart';

import '../../state/support.dart';
import '../../support/golden.dart';
import '../canvas/support.dart';
import '../support.dart';
import 'support.dart';

void main() {
  Finder pane() => find.byType(EffectDetailsPane);
  Finder inPane(Finder finder) => find.descendant(of: pane(), matching: finder);
  Finder tab(EffectTab tab) => find.byKey(EffectDetailsPane.tabKey(tab));

  Color? fillOf(WidgetTester tester, EffectTab which) =>
      (tester.widget<Container>(tab(which)).decoration as BoxDecoration?)
          ?.color;

  Future<void> open(WidgetTester tester, EffectTab which) async {
    await tester.tap(tab(which));
    await tester.pump();
    await tester.pump();
  }

  Future<void> selectRow(WidgetTester tester, String effectId) async {
    await tester.tap(find.byKey(EffectList.rowKey(effectId)));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('names the effect, and shows its log first: notify, Output, '
      'Log, following tail, Open — an effect has no input', (tester) async {
    await pumpReview(tester);

    expect(
      textIn(tester, find.byKey(EffectDetailsPane.headerKey)),
      'notify Output Log following tail Open',
    );
    expect(fillOf(tester, EffectTab.log), AppColors.selectedTab);
    expect(fillOf(tester, EffectTab.output), isNull);
    expect(inPane(find.text('2 findings, 3 subscribers')), findsOneWidget);
  });

  testWidgets('shows the output as JSON', (tester) async {
    await pumpReview(tester);
    await selectRow(tester, 'a1b2-inspect-3');

    await open(tester, EffectTab.output);
    expect(fillOf(tester, EffectTab.output), AppColors.selectedTab);
    for (final line in [
      '{',
      '  "change": {',
      '    "path": "lib/parse_config.dart"',
      '  "findings": []',
    ]) {
      expect(inPane(find.text(line)), findsOneWidget, reason: line);
    }
  });

  testWidgets('a running effect has no output yet', (tester) async {
    await pumpReview(tester);

    await open(tester, EffectTab.output);
    expect(
      inPane(find.text('Not yet: the effect is still running')),
      findsOneWidget,
    );
  });

  testWidgets("a failed effect's output is its error", (tester) async {
    final session = reviewSession()
      ..effect(
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

    await open(tester, EffectTab.output);
    expect(
      inPane(find.text('Failed: StateError: inspect failed')),
      findsOneWidget,
    );
  });

  testWidgets('says why a document cannot be read', (tester) async {
    await pumpReview(tester, model: reviewModel(files: FakeFiles()));
    await selectRow(tester, 'a1b2-inspect-3');

    await open(tester, EffectTab.output);
    expect(
      inPane(find.textContaining('Could not read the document: ')),
      findsOneWidget,
    );
  });

  testWidgets('keeps the open tab as another effect is selected', (
    tester,
  ) async {
    await pumpReview(tester);
    await selectRow(tester, 'a1b2-inspect-3');
    await open(tester, EffectTab.output);

    await selectRow(tester, 'a1b2-collect-0');
    expect(fillOf(tester, EffectTab.output), AppColors.selectedTab);
    expect(inPane(find.text('  "id": "c4f1a9",')), findsOneWidget);
  });

  testWidgets('Open opens the effect', (tester) async {
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
          onOpenEffect: (effect) => opened.add(effect.effectId),
        ),
      ),
    );
    await settle(tester);

    await tester.tap(find.byKey(EffectDetailsPane.openKey));
    expect(opened, ['a1b2-notify-5']);
  });
}
