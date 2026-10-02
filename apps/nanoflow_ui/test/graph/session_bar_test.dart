import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_model/nanoflow_model.dart' hide Route;
import 'package:nanoflow_ui/graph/canvas/node_tile.dart';
import 'package:nanoflow_ui/graph/run_switcher.dart';
import 'package:nanoflow_ui/graph/session_bar.dart';
import 'package:nanoflow_ui/graph/sessions_column.dart';
import 'package:nanoflow_ui/state/runs.dart';
import 'package:nanoflow_ui/theme.dart';

import '../state/support.dart';
import 'canvas/support.dart';
import 'support.dart';

void main() {
  Finder inBar(Finder finder) =>
      find.descendant(of: find.byType(SessionBar), matching: finder);

  Finder pill(String runId) => find.byKey(RunSwitcher.pillKey(runId));

  Finder sign(String runId, RunPhase phase) => find.descendant(
    of: pill(runId),
    matching: find.byWidgetPredicate((w) => w is RunSign && w.phase == phase),
  );

  Color? fillOf(WidgetTester tester, String runId) =>
      (tester.widget<Container>(pill(runId)).decoration! as BoxDecoration)
          .color;

  Finder incompleteMark(String runId) => find.descendant(
    of: pill(runId),
    matching: find.byWidgetPredicate(
      (w) => w is Tooltip && w.message!.startsWith(logReadIncompletely),
    ),
  );

  Future<void> select(WidgetTester tester, String sessionId) async {
    await tester.tap(find.byKey(SessionsColumn.cardKey(sessionId)));
    await tester.pump();
  }

  group('the session bar', () {
    testWidgets('names the session, when it started and how it is', (
      tester,
    ) async {
      await pumpGraphScreen(tester);

      for (final text in ['Session', 'a1b2', 'started 14:03:11']) {
        expect(inBar(find.text(text)), findsOneWidget);
      }
      expect(inBar(find.byTooltip('a1b2-session')), findsOneWidget);
      final status = inBar(find.text('running 12m 26s'));
      expect(tester.widget<Text>(status).style!.color, AppColors.running);
    });

    testWidgets('a failed session: failed in 6m 18s', (tester) async {
      await pumpGraphScreen(tester);
      await select(tester, '7c3e-s');

      expect(inBar(find.text('7c3e')), findsOneWidget);
      final status = inBar(find.text('failed in 6m 18s'));
      expect(tester.widget<Text>(status).style!.color, AppColors.dangerText);
    });

    testWidgets('a finished session: finished in 3m 04s', (tester) async {
      await pumpGraphScreen(tester);
      await select(tester, '4b8d-s');

      final status = inBar(find.text('finished in 3m 04s'));
      expect(tester.widget<Text>(status).style!.color, AppColors.finishedText);
    });

    testWidgets('stays put while the canvas under it moves', (tester) async {
      await pumpGraphScreen(tester);
      final bar = tester.getRect(inBar(find.text('Session')));
      final node = tester.getRect(find.byKey(NodeTile.tileKeyOf('collect')));

      await tester.dragFrom(const Offset(700, 400), const Offset(-120, 60));
      await tester.pump();

      expect(tester.getRect(inBar(find.text('Session'))), bar);
      expect(
        tester.getRect(find.byKey(NodeTile.tileKeyOf('collect'))),
        isNot(node),
      );
    });

    testWidgets('is not there for Current graph; the zoom buttons are', (
      tester,
    ) async {
      final model = await pumpGraphScreen(tester);
      model.selection.showCurrentGraph();
      await tester.pump();

      expect(inBar(find.text('Session')), findsNothing);
      expect(find.byKey(RunSwitcher.pillKey('e5f6-run')), findsNothing);
      expect(find.byTooltip('Zoom to fit'), findsOneWidget);
    });
  });

  group('the run switcher', () {
    testWidgets('has the runs in the order they were created', (tester) async {
      await pumpGraphScreen(tester);

      final lefts = [
        for (final run in ['k7f2-run', 'c3d4-run', 'e5f6-run'])
          tester.getTopLeft(pill(run)).dx,
      ];
      expect(lefts, orderedEquals([...lefts]..sort()));
      expect(inBar(find.text('Run')), findsOneWidget);
      expect(
        find.descendant(of: pill('k7f2-run'), matching: find.text('k7f2')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: pill('k7f2-run'),
          matching: find.byTooltip('k7f2-run'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('signs each run with its state, a split one with split too', (
      tester,
    ) async {
      final mockup = Mockup();
      final failed = Journal(
        'f1a2-run',
        parent: 'k7f2-run',
        node: 'publish',
        startedAt: 611.4,
      );
      failed.fail(failed.step('publish', 612, end: 620, exit: 1), 620, 'oops');
      final waiting = Journal(
        'w9x8-run',
        parent: 'k7f2-run',
        node: 'notify',
        startedAt: 611.5,
      );
      await pumpGraphScreen(
        tester,
        model: ownedModel(
          changes: changesOf([
            mockup.k7f2,
            mockup.c3d4,
            mockup.e5f6,
            failed,
            waiting,
          ]),
          outcomes: reviewOutcomes,
        ),
      );

      expect(sign('k7f2-run', RunPhase.split), findsOneWidget);
      expect(
        find.descendant(of: pill('k7f2-run'), matching: find.text('split')),
        findsOneWidget,
      );
      expect(sign('c3d4-run', RunPhase.finished), findsOneWidget);
      expect(sign('e5f6-run', RunPhase.running), findsOneWidget);
      expect(sign('f1a2-run', RunPhase.failed), findsOneWidget);
      expect(sign('w9x8-run', RunPhase.notStarted), findsOneWidget);
      expect(find.text('split'), findsOneWidget);
    });

    testWidgets('fills the selected run with the accent', (tester) async {
      await pumpGraphScreen(tester);

      expect(fillOf(tester, 'e5f6-run'), AppColors.accent);
      expect(fillOf(tester, 'c3d4-run'), isNot(AppColors.accent));
      expect(fillOf(tester, 'k7f2-run'), isNot(AppColors.accent));
    });

    testWidgets('a click on a run selects it', (tester) async {
      final model = await pumpGraphScreen(tester);

      await tester.tap(pill('c3d4-run'));
      await tester.pump();

      expect(model.selection.runId, 'c3d4-run');
      expect(fillOf(tester, 'c3d4-run'), AppColors.accent);
      expect(fillOf(tester, 'e5f6-run'), isNot(AppColors.accent));
    });

    testWidgets('marks a run whose log was read incompletely, and says why', (
      tester,
    ) async {
      final mockup = Mockup();
      await pumpGraphScreen(
        tester,
        model: ownedModel(
          changes: [
            ...changesOf([mockup.k7f2, mockup.c3d4, mockup.e5f6]),
            const LogCorrupted(runId: 'c3d4-run', line: 3, text: 'garbage'),
          ],
          outcomes: reviewOutcomes,
        ),
      );

      expect(incompleteMark('c3d4-run'), findsOneWidget);
      expect(
        tester.widget<Tooltip>(incompleteMark('c3d4-run')).message,
        contains('line 3 is not an event: garbage'),
      );
      expect(incompleteMark('e5f6-run'), findsNothing);
      expect(incompleteMark('k7f2-run'), findsNothing);
    });
  });
}
