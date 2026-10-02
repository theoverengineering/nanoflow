import 'dart:async';

import 'package:flutter/material.dart' hide Step;
import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_model/nanoflow_model.dart' hide Route;
import 'package:nanoflow_ui/graph/canvas/graph_canvas.dart';
import 'package:nanoflow_ui/graph/canvas/node_tile.dart';
import 'package:nanoflow_ui/graph/logs/logs_panel.dart';
import 'package:nanoflow_ui/graph/logs/step_bar.dart';
import 'package:nanoflow_ui/graph/logs/step_list.dart';
import 'package:nanoflow_ui/graph/run_switcher.dart';
import 'package:nanoflow_ui/graph/sessions_column.dart';
import 'package:nanoflow_ui/state/graph_model.dart';
import 'package:nanoflow_ui/theme.dart';

import '../../state/support.dart';
import '../canvas/support.dart';
import '../support.dart';
import 'support.dart';

void main() {
  Finder row(String stepId) => find.byKey(StepList.rowKey(stepId));

  Finder icon(String stepId, StepStatus status) => find.descendant(
    of: row(stepId),
    matching: find.byWidgetPredicate(
      (w) => w is StepIcon && w.status == status,
    ),
  );

  Color? fillOf(WidgetTester tester, Finder finder) =>
      (tester.widget<Container>(finder).decoration as BoxDecoration?)?.color;

  Future<void> select(
    WidgetTester tester,
    String sessionId,
    String runId,
  ) async {
    await tester.tap(find.byKey(SessionsColumn.cardKey(sessionId)));
    await tester.pump();
    await tester.tap(find.byKey(RunSwitcher.pillKey(runId)));
    await tester.pump();
  }

  const e5f6 = [
    ('k7f2-collect-0', 'collect 14:03:11 2m 29s'),
    ('k7f2-is-empty-1', 'is-empty else → inspect 14:05:40 1s'),
    ('k7f2-inspect-2', 'inspect 14:05:41 3m 12s'),
    ('k7f2-verdict-3', 'verdict returned → fix 14:08:53 0.4s'),
    ('k7f2-fix-4', 'fix 14:08:54 26s'),
    ('k7f2-inspect-5', 'inspect 2 starts 14:09:20 4m 02s'),
    ('k7f2-verdict-6', 'verdict accepted → publish, notify 14:13:22 0.3s'),
    ('e5f6-notify-0', 'notify 14:13:23 2m 14s'),
  ];

  group('the steps list', () {
    testWidgets('has a row per step: the node, a fork\'s outcome and where '
        'it went, `2 starts`, when it first started, how long it took', (
      tester,
    ) async {
      await pumpGraphScreen(tester);

      for (final (stepId, text) in e5f6) {
        expect(textIn(tester, row(stepId)), text, reason: stepId);
      }
      expect(
        textIn(
          tester,
          find.byType(StepList),
        ).startsWith('Step Started Took 0m 6m 12m'),
        isTrue,
      );
    });

    testWidgets('dims the inherited steps', (tester) async {
      await pumpGraphScreen(tester);

      for (final (stepId, _) in e5f6) {
        final dimmed = find.descendant(
          of: row(stepId),
          matching: find.byWidgetPredicate(
            (w) => w is Opacity && w.opacity == 0.55,
          ),
        );
        expect(
          dimmed,
          stepId == 'e5f6-notify-0' ? findsNothing : findsOneWidget,
          reason: stepId,
        );
      }
    });

    testWidgets('puts `split · run e5f6` where the run split from its '
        'parent', (tester) async {
      await pumpGraphScreen(tester);

      final split = find.byKey(StepList.splitKey('e5f6-run'));
      expect(textIn(tester, split), 'split · run e5f6');
      expect(
        find.descendant(of: split, matching: find.byTooltip('e5f6-run')),
        findsOneWidget,
      );
      final y = tester.getCenter(split).dy;
      expect(tester.getCenter(row('k7f2-verdict-6')).dy, lessThan(y));
      expect(tester.getCenter(row('e5f6-notify-0')).dy, greaterThan(y));
    });

    testWidgets('marks steps finished, running and failed', (tester) async {
      await pumpGraphScreen(tester);

      expect(icon('k7f2-collect-0', StepStatus.finished), findsOneWidget);
      expect(icon('e5f6-notify-0', StepStatus.running), findsOneWidget);

      await select(tester, '7c3e-s', 'p7c3-run');
      final failed = row('p7c3-publish-0');
      expect(icon('p7c3-publish-0', StepStatus.failed), findsOneWidget);
      expect(textIn(tester, failed), startsWith('publish exited with code 1'));
      final error = tester
          .widget<RichText>(
            find.descendant(of: failed, matching: find.byType(RichText)).first,
          )
          .text;
      final colors = <String, Color?>{};
      error.visitChildren((span) {
        if (span is TextSpan && span.text != null) {
          colors[span.text!.trim()] = span.style?.color;
        }
        return true;
      });
      expect(colors['exited with code 1'], AppColors.dangerText);
    });

    testWidgets('the running step\'s Took ticks', (tester) async {
      var now = Mockup.now;
      await pumpGraphScreen(tester, now: () => now);
      expect(textIn(tester, row('e5f6-notify-0')), endsWith('2m 14s'));

      now = now.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(textIn(tester, row('e5f6-notify-0')), endsWith('2m 15s'));
    });

    testWidgets('draws each step\'s bar on the session\'s time scale, the '
        'running one striped', (tester) async {
      await pumpGraphScreen(tester);

      Rect bar(String stepId) =>
          tester.getRect(find.byKey(StepTrack.barKey(stepId)));
      Rect track(String stepId) =>
          tester.getRect(find.byKey(StepTrack.trackKey(stepId)));
      final collect = track('k7f2-collect-0');
      expect(collect.width, 150);
      expect(bar('k7f2-collect-0').left, collect.left);
      expect(bar('k7f2-collect-0').width, closeTo(150 * 149 / 746, 0.01));
      // Shorter than 2 px it is 2 px wide.
      expect(bar('k7f2-is-empty-1').width, 2);
      final notify = track('e5f6-notify-0');
      expect(
        bar('e5f6-notify-0').left,
        closeTo(notify.left + 150 * 612 / 746, 0.01),
      );
      expect(bar('e5f6-notify-0').right, notify.right);
      expect(
        tester
            .widget<StepBar>(find.byKey(StepTrack.barKey('e5f6-notify-0')))
            .striped,
        isTrue,
      );
      expect(
        tester
            .widget<StepBar>(find.byKey(StepTrack.barKey('k7f2-fix-4')))
            .striped,
        isFalse,
      );
    });

    testWidgets('ends an ended run with how it ended', (tester) async {
      await pumpGraphScreen(tester);
      final end = find.byKey(StepList.endKey);
      expect(end, findsNothing);

      Color? colorOf(String text) => tester
          .widget<Text>(find.descendant(of: end, matching: find.text(text)))
          .style
          ?.color;

      await tester.tap(find.byKey(RunSwitcher.pillKey('c3d4-run')));
      await tester.pump();
      expect(textIn(tester, end), 'Run finished 14:13:51');
      expect(colorOf('Run finished'), AppColors.finishedText);

      await select(tester, '7c3e-s', 'p7c3-run');
      expect(textIn(tester, end), startsWith('Run failed: exited with code 1'));
      expect(colorOf('Run failed: exited with code 1'), AppColors.dangerText);
    });

    testWidgets('ends a run that split with links to the runs it split '
        'into', (tester) async {
      final model = await pumpGraphScreen(tester);
      await tester.tap(find.byKey(RunSwitcher.pillKey('k7f2-run')));
      await tester.pump();

      final end = find.byKey(StepList.endKey);
      expect(textIn(tester, end), 'Run split into c3d4 e5f6 14:13:22');
      expect(
        find.descendant(of: end, matching: find.byTooltip('c3d4-run')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(StepList.childKey('c3d4-run')));
      await tester.pump();
      expect(model.selection.runId, 'c3d4-run');
      expect(
        textIn(tester, find.byKey(LogsPanel.titleKey)),
        'Logs run c3d4 · 8 steps, 7 inherited from k7f2',
      );
    });

    testWidgets('highlights the selected step', (tester) async {
      await pumpGraphScreen(tester);

      expect(fillOf(tester, row('e5f6-notify-0')), AppColors.accentSurface);
      expect(fillOf(tester, row('k7f2-collect-0')), isNull);
    });

    testWidgets('a click on a row selects its step and brings its node into '
        'view on the canvas', (tester) async {
      final model = await pumpGraphScreen(tester);
      final canvas = find.byType(GraphCanvas);
      final collect = find.byKey(NodeTile.tileKeyOf('collect'));
      await tester.dragFrom(const Offset(800, 300), const Offset(-700, 0));
      // The drag began on a tile, which waits to tell a double click.
      await tester.pump(const Duration(milliseconds: 100));
      expect(shownWithin(tester, collect, canvas), isFalse);

      await tester.tap(row('k7f2-collect-0'));
      await tester.pump();

      expect(model.selection.stepId, 'k7f2-collect-0');
      expect(model.selection.following, isFalse);
      expect(fillOf(tester, row('k7f2-collect-0')), AppColors.accentSurface);
      expect(fillOf(tester, row('e5f6-notify-0')), isNull);
      expect(shownWithin(tester, collect, canvas), isTrue);
    });
  });

  group('a long steps list', () {
    late StreamController<Change> more;

    Future<GraphModel> pumpTask(WidgetTester tester) {
      more = StreamController<Change>();
      addTearDown(more.close);
      return pumpGraphScreen(
        tester,
        path: taskFile,
        model: taskMockupModel(more: more.stream),
        now: () => taskNow,
      );
    }

    Finder list() => find.byType(StepList);

    testWidgets('is scrolled to the selected last step, and says how many '
        'steps are above: ↑ 7 earlier steps', (tester) async {
      await pumpTask(tester);

      expect(shownWithin(tester, row('t9m4-human-review-15'), list()), isTrue);
      final earlier = find.byKey(StepList.earlierKey);
      expect(textIn(tester, earlier), '↑ 7 earlier steps');

      await tester.tap(earlier);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(earlier, findsNothing);
      expect(shownWithin(tester, row('t9m4-admit-0'), list()), isTrue);
    });

    testWidgets('follows the run: a new step is selected and scrolled into '
        'view', (tester) async {
      final model = await pumpTask(tester);

      final waiting = 't9m4-human-review-15';
      final time = DateTime(2026, 9, 24, 12, 6, 0).toUtc();
      more
        ..add(
          EventAdded(
            StepFinished(
              runId: 't9m4-run',
              time: time,
              stepId: waiting,
              exitCode: 0,
              outputId: null,
            ),
          ),
        )
        ..add(
          const StepAdded(
            Step(
              id: 't9m4-human-answer-16',
              runId: 't9m4-run',
              inputId: null,
              outputId: null,
              log: 'command.log',
            ),
          ),
        )
        ..add(
          EventAdded(
            StepStarted(
              runId: 't9m4-run',
              time: time.add(const Duration(seconds: 1)),
              stepId: 't9m4-human-answer-16',
              node: 'human-answer',
            ),
          ),
        );
      await settle(tester);

      expect(model.selection.stepId, 't9m4-human-answer-16');
      expect(shownWithin(tester, row('t9m4-human-answer-16'), list()), isTrue);
    });

    testWidgets('a step selected on the canvas is scrolled into view', (
      tester,
    ) async {
      await pumpTask(tester);
      expect(shownWithin(tester, row('t9m4-admit-0'), list()), isFalse);

      await tester.tap(find.byKey(NodeTile.tileKeyOf('admit')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      expect(shownWithin(tester, row('t9m4-admit-0'), list()), isTrue);
    });
  });
}
