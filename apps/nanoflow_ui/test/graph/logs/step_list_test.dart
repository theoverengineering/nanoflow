import 'dart:async';

import 'package:flutter/material.dart' hide Step;
import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_ui/graph/canvas/graph_canvas.dart';
import 'package:nanoflow_ui/graph/canvas/node_tile.dart';
import 'package:nanoflow_ui/graph/logs/step_bar.dart';
import 'package:nanoflow_ui/graph/logs/step_list.dart';
import 'package:nanoflow_ui/state/graph_model.dart';
import 'package:nanoflow_ui/state/log_rows.dart' show notOnGraph;
import 'package:nanoflow_ui/state/visits.dart' show StartOutcome;
import 'package:nanoflow_ui/theme.dart';
import 'package:nanoflow_ui/widgets/spinner.dart';

import '../../state/support.dart';
import '../canvas/support.dart';
import '../support.dart';
import 'support.dart';

void main() {
  Finder row(String stepId) => find.byKey(StepList.rowKey(stepId));

  Finder icon(String stepId, StartOutcome status) => find.descendant(
    of: row(stepId),
    matching: find.byWidgetPredicate(
      (w) => w is StepIcon && w.status == status,
    ),
  );

  Color? fillOf(WidgetTester tester, Finder finder) =>
      (tester.widget<Container>(finder).decoration as BoxDecoration?)?.color;

  Future<GraphModel> pumpReview(
    WidgetTester tester, {
    GraphModel? model,
    DateTime Function()? now,
  }) => pumpGraphScreen(
    tester,
    path: reviewFile,
    model: model ?? reviewModel(),
    now: now ?? () => columnNow,
  );

  /// A session of review that [change] ends otherwise than [reviewSession].
  GraphModel endedModel(void Function(Journal session) change) {
    final session = reviewSession();
    change(session);
    return ownedModel(
      graph: graphFileNamed('review'),
      file: reviewFile,
      changes: session.changes,
      documents: reviewDocuments,
    );
  }

  group('the steps list', () {
    testWidgets('has a row per step: its name, `2 starts`, when it first '
        'started, how long it took', (tester) async {
      await pumpReview(tester);

      for (final (stepId, text) in [
        ('a1b2-collect-0', 'collect 14:03:11 2m 29s'),
        ('a1b2-inspect-1', 'inspect 14:05:41 3m 12s'),
        ('a1b2-fix-2', 'fix 14:08:54 26s'),
        ('a1b2-inspect-3', 'inspect 2 starts 14:09:20 4m 02s'),
        ('a1b2-publish-4', 'publish 14:13:23 1s'),
        ('a1b2-notify-5', 'notify 14:13:23 2m 14s'),
      ]) {
        expect(textIn(tester, row(stepId)), text, reason: stepId);
      }
      expect(
        textIn(tester, find.byType(StepList)),
        startsWith('Step Started Took 0m 6m 12m'),
      );
    });

    testWidgets('marks steps finished, running and failed; a failed one '
        'with its error in red', (tester) async {
      await pumpReview(
        tester,
        model: endedModel(
          (session) => session.step(
            'inspect',
            700,
            end: 701,
            failed: true,
            place: 'lib/review.dart:55',
          ),
        ),
      );

      expect(icon('a1b2-collect-0', StartOutcome.finished), findsOneWidget);
      expect(icon('a1b2-notify-5', StartOutcome.running), findsOneWidget);
      final failed = row('a1b2-inspect-6');
      expect(icon('a1b2-inspect-6', StartOutcome.failed), findsOneWidget);
      expect(
        textIn(tester, failed),
        startsWith('inspect StateError: inspect failed'),
      );
      final text = tester
          .widget<RichText>(
            find.descendant(of: failed, matching: find.byType(RichText)).first,
          )
          .text;
      final colors = <String, Color?>{};
      text.visitChildren((span) {
        if (span is TextSpan && span.text != null) {
          colors[span.text!.trim()] = span.style?.color;
        }
        return true;
      });
      expect(colors['StateError: inspect failed'], AppColors.dangerText);
    });

    testWidgets('in a session whose process is gone, the step that was '
        'running is interrupted: its pause, a plain bar, a Took that took '
        'until the last event and stands still (owner spec §6)', (
      tester,
    ) async {
      var now = columnNow;
      await pumpReview(
        tester,
        model: endedModel(
          (session) => session
            ..step('archive', 620, end: 700)
            ..processGone(),
        ),
        now: () => now,
      );

      expect(icon('a1b2-notify-5', StartOutcome.interrupted), findsOneWidget);
      expect(
        find.descendant(
          of: row('a1b2-notify-5'),
          matching: find.byType(Spinner),
        ),
        findsNothing,
      );
      final bar = tester.widget<StepBar>(
        find.byKey(StepTrack.barKey('a1b2-notify-5')),
      );
      expect(bar.status, StartOutcome.interrupted);
      expect(bar.striped, isFalse);
      expect(textIn(tester, row('a1b2-notify-5')), endsWith('1m 28s'));

      now = now.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(textIn(tester, row('a1b2-notify-5')), endsWith('1m 28s'));
    });

    testWidgets('says of a step that is on no node: not on the graph', (
      tester,
    ) async {
      await pumpReview(
        tester,
        model: endedModel(
          (session) =>
              session.step('gather', 700, end: 701, place: 'lib/old.dart:3'),
        ),
      );
      expect(
        textIn(tester, row('a1b2-gather-6')),
        startsWith('gather $notOnGraph'),
      );
    });

    testWidgets("the running step's Took ticks", (tester) async {
      var now = columnNow;
      await pumpReview(tester, now: () => now);
      expect(textIn(tester, row('a1b2-notify-5')), endsWith('2m 14s'));

      now = now.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(textIn(tester, row('a1b2-notify-5')), endsWith('2m 15s'));
    });

    testWidgets("draws each step's bar on the session's time scale, the "
        'running one striped', (tester) async {
      await pumpReview(tester);

      Rect bar(String stepId) =>
          tester.getRect(find.byKey(StepTrack.barKey(stepId)));
      Rect track(String stepId) =>
          tester.getRect(find.byKey(StepTrack.trackKey(stepId)));
      final collect = track('a1b2-collect-0');
      expect(collect.width, 150);
      expect(bar('a1b2-collect-0').left, collect.left);
      expect(bar('a1b2-collect-0').width, closeTo(150 * 149 / 746, 0.01));
      // Shorter than 2 px it is 2 px wide.
      expect(bar('a1b2-publish-4').width, 2);
      final notify = track('a1b2-notify-5');
      expect(
        bar('a1b2-notify-5').left,
        closeTo(notify.left + 150 * 612 / 746, 0.01),
      );
      expect(bar('a1b2-notify-5').right, notify.right);
      expect(
        tester
            .widget<StepBar>(find.byKey(StepTrack.barKey('a1b2-notify-5')))
            .striped,
        isTrue,
      );
      expect(
        tester
            .widget<StepBar>(find.byKey(StepTrack.barKey('a1b2-fix-2')))
            .striped,
        isFalse,
      );
    });

    final end = find.byKey(StepList.endKey);
    Color? colorOf(WidgetTester tester, String text) => tester
        .widget<Text>(find.descendant(of: end, matching: find.text(text)))
        .style
        ?.color;

    testWidgets('a running session has no end', (tester) async {
      await pumpReview(tester);
      expect(end, findsNothing);
    });

    testWidgets('ends a finished session with how it ended', (tester) async {
      await pumpReview(
        tester,
        model: endedModel(
          (session) => session
            ..events.add(
              StepFinished(
                time: at(700),
                stepId: 'a1b2-notify-5',
                outputId: 'notified',
              ),
            )
            ..finish(701),
        ),
      );
      expect(textIn(tester, end), 'Session finished 14:14:52');
      expect(colorOf(tester, 'Session finished'), AppColors.finishedText);
    });

    testWidgets('ends a failed session with its error', (tester) async {
      await pumpReview(
        tester,
        model: endedModel((session) => session.fail(701, 'StateError: boom')),
      );
      expect(textIn(tester, end), startsWith('Session failed: StateError'));
      expect(
        colorOf(tester, 'Session failed: StateError: boom'),
        AppColors.dangerText,
      );
    });

    testWidgets('highlights the selected step', (tester) async {
      await pumpReview(tester);

      expect(fillOf(tester, row('a1b2-notify-5')), AppColors.accentSurface);
      expect(fillOf(tester, row('a1b2-collect-0')), isNull);
    });

    testWidgets('a click on a row selects its step and brings its node into '
        'view on the canvas', (tester) async {
      final model = await pumpReview(tester);
      final canvas = find.byType(GraphCanvas);
      final collect = find.byKey(NodeTile.tileKeyOf('1'));
      await tester.dragFrom(const Offset(800, 300), const Offset(-700, 0));
      // The drag may begin on a tile, which waits to tell a double click.
      await tester.pump(const Duration(milliseconds: 100));
      expect(shownWithin(tester, collect, canvas), isFalse);

      await tester.tap(row('a1b2-collect-0'));
      await tester.pump();

      expect(model.selection.stepId, 'a1b2-collect-0');
      expect(model.selection.following, isFalse);
      expect(fillOf(tester, row('a1b2-collect-0')), AppColors.accentSurface);
      expect(fillOf(tester, row('a1b2-notify-5')), isNull);
      expect(shownWithin(tester, collect, canvas), isTrue);
    });
  });

  group('a long steps list', () {
    late StreamController<Change> more;

    /// Review round inspect and fix eight times, then on inspect.
    Future<GraphModel> pumpLong(WidgetTester tester) {
      more = StreamController<Change>();
      addTearDown(more.close);
      final graph = graphFileNamed('review');
      final session = Journal(
        'l0ng-session',
        graph: graph.toJson(),
        code: graph.fingerprint,
      )..step('collect', 0, end: 10, place: 'lib/review.dart:49');
      for (var i = 0; i < 8; i++) {
        session
          ..step(
            'inspect',
            10 + i * 20,
            end: 20 + i * 20,
            place: 'lib/review.dart:55',
          )
          ..step(
            'fix',
            20 + i * 20,
            end: 30 + i * 20,
            place: 'lib/review.dart:63',
          );
      }
      session.step('inspect', 170, place: 'lib/review.dart:55');
      return pumpReview(
        tester,
        model: ownedModel(
          graph: graphFileNamed('review'),
          file: reviewFile,
          changes: session.changes,
          more: more.stream,
        ),
        now: () => at(200),
      );
    }

    Finder list() => find.byType(StepList);

    testWidgets('is scrolled to the selected last step, and says how many '
        'steps are above it', (tester) async {
      await pumpLong(tester);

      expect(shownWithin(tester, row('l0ng-inspect-17'), list()), isTrue);
      final earlier = find.byKey(StepList.earlierKey);
      expect(
        textIn(tester, earlier),
        matches(RegExp(r'^↑ \d+ earlier steps$')),
      );

      await tester.tap(earlier);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(earlier, findsNothing);
      expect(shownWithin(tester, row('l0ng-collect-0'), list()), isTrue);
    });

    testWidgets('follows the session: a new step is selected and scrolled '
        'into view', (tester) async {
      final model = await pumpLong(tester);

      more
        ..add(
          EventAdded(
            sessionId: 'l0ng-session',
            event: StepFinished(
              time: at(180),
              stepId: 'l0ng-inspect-17',
              outputId: 'report',
            ),
          ),
        )
        ..add(
          const StepAdded(
            Step(
              id: 'l0ng-publish-18',
              sessionId: 'l0ng-session',
              name: 'publish',
              key: 'publish#1@0000000000000000',
              after: 'inspect#9@0000000000000000',
              place: 'lib/review.dart:58',
              outputId: null,
              log: logFileName,
            ),
          ),
        )
        ..add(
          EventAdded(
            sessionId: 'l0ng-session',
            event: StepStarted(time: at(181), stepId: 'l0ng-publish-18'),
          ),
        );
      await settle(tester);

      expect(model.selection.stepId, 'l0ng-publish-18');
      expect(shownWithin(tester, row('l0ng-publish-18'), list()), isTrue);
    });

    testWidgets('a step selected on the canvas is scrolled into view', (
      tester,
    ) async {
      final model = await pumpLong(tester);
      expect(shownWithin(tester, row('l0ng-collect-0'), list()), isFalse);

      await tester.tap(find.byKey(NodeTile.tileKeyOf('1')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      expect(model.selection.stepId, 'l0ng-collect-0');
      expect(shownWithin(tester, row('l0ng-collect-0'), list()), isTrue);
    });
  });
}
