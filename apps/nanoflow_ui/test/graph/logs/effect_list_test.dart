import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_ui/graph/canvas/graph_canvas.dart';
import 'package:nanoflow_ui/graph/canvas/node_tile.dart';
import 'package:nanoflow_ui/graph/logs/effect_bar.dart';
import 'package:nanoflow_ui/graph/logs/effect_list.dart';
import 'package:nanoflow_ui/state/graph_model.dart';
import 'package:nanoflow_ui/state/log_rows.dart';
import 'package:nanoflow_ui/state/texts.dart' show clockTime;
import 'package:nanoflow_ui/state/visits.dart' show StartOutcome;
import 'package:nanoflow_ui/theme.dart';
import 'package:nanoflow_ui/widgets/icons.dart' show ChevronIcon;
import 'package:nanoflow_ui/widgets/spinner.dart';

import '../../state/support.dart';
import '../../support/golden.dart';
import '../canvas/support.dart';
import '../support.dart';
import 'support.dart';

void main() {
  Finder row(String effectId) => find.byKey(EffectList.rowKey(effectId));

  Finder icon(String effectId, StartOutcome status) => find.descendant(
    of: row(effectId),
    matching: find.byWidgetPredicate(
      (w) => w is EffectIcon && w.status == status,
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

  group('the effects list', () {
    testWidgets('has a row per effect: its name, `2 starts`, when it first '
        'started, how long it took', (tester) async {
      await pumpReview(tester);

      for (final (effectId, text) in [
        ('a1b2-collect-0', 'collect 14:03:11 2m 29s'),
        ('a1b2-inspect-1', 'inspect 14:05:41 3m 12s'),
        ('a1b2-fix-2', 'fix 14:08:54 26s'),
        ('a1b2-inspect-3', 'inspect 2 starts 14:09:20 4m 02s'),
        ('a1b2-publish-4', 'publish 14:13:23 1s'),
        ('a1b2-notify-5', 'notify 14:13:23 2m 14s'),
      ]) {
        expect(textIn(tester, row(effectId)), text, reason: effectId);
      }
      expect(
        textIn(tester, find.byType(EffectList)),
        startsWith('Effect Started Took 0m 6m 12m'),
      );
    });

    testWidgets('marks effects finished, running and failed; a failed one '
        'with its error in red', (tester) async {
      await pumpReview(
        tester,
        model: endedModel(
          (session) => session.effect(
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

    testWidgets('in a session whose process is gone, the effect that was '
        'running is interrupted: its pause, a bar not filled to the end of '
        'the scale, a Took not known (owner spec §6)', (tester) async {
      var now = columnNow;
      await pumpReview(
        tester,
        model: endedModel((session) => session.processGone()),
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
      final bar = find.byKey(EffectTrack.barKey('a1b2-notify-5'));
      expect(tester.widget<EffectBar>(bar).status, StartOutcome.interrupted);
      expect(tester.widget<EffectBar>(bar).striped, isFalse);
      expect(
        find.descendant(of: bar, matching: find.byType(ColoredBox)),
        findsNothing,
        reason: 'not filled',
      );
      expect(textIn(tester, row('a1b2-notify-5')), endsWith('14:13:23 —'));

      now = now.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(textIn(tester, row('a1b2-notify-5')), endsWith('14:13:23 —'));
    });

    testWidgets('says of an effect that is on no node: not on the graph', (
      tester,
    ) async {
      await pumpReview(
        tester,
        model: endedModel(
          (session) =>
              session.effect('gather', 700, end: 701, place: 'lib/old.dart:3'),
        ),
      );
      expect(
        textIn(tester, row('a1b2-gather-6')),
        startsWith('gather $notOnGraph'),
      );
    });

    testWidgets("the running effect's Took ticks", (tester) async {
      var now = columnNow;
      await pumpReview(tester, now: () => now);
      expect(textIn(tester, row('a1b2-notify-5')), endsWith('2m 14s'));

      now = now.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(textIn(tester, row('a1b2-notify-5')), endsWith('2m 15s'));
    });

    testWidgets("draws each effect's bar on the session's time scale, the "
        'running one striped', (tester) async {
      await pumpReview(tester);

      Rect bar(String effectId) =>
          tester.getRect(find.byKey(EffectTrack.barKey(effectId)));
      Rect track(String effectId) =>
          tester.getRect(find.byKey(EffectTrack.trackKey(effectId)));
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
            .widget<EffectBar>(find.byKey(EffectTrack.barKey('a1b2-notify-5')))
            .striped,
        isTrue,
      );
      expect(
        tester
            .widget<EffectBar>(find.byKey(EffectTrack.barKey('a1b2-fix-2')))
            .striped,
        isFalse,
      );
    });

    final end = find.byKey(EffectList.endKey);
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
              EffectFinished(
                time: at(700),
                effectId: 'a1b2-notify-5',
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

    testWidgets('highlights the selected effect', (tester) async {
      await pumpReview(tester);

      expect(fillOf(tester, row('a1b2-notify-5')), AppColors.accentSurface);
      expect(fillOf(tester, row('a1b2-collect-0')), isNull);
    });

    testWidgets('a click on a row selects its effect and brings its node into '
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

      expect(model.selection.effectId, 'a1b2-collect-0');
      expect(model.selection.following, isFalse);
      expect(fillOf(tester, row('a1b2-collect-0')), AppColors.accentSurface);
      expect(fillOf(tester, row('a1b2-notify-5')), isNull);
      expect(shownWithin(tester, collect, canvas), isTrue);
    });
  });

  group('a long effects list', () {
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
      )..effect('collect', 0, end: 10, place: 'lib/review.dart:49');
      for (var i = 0; i < 8; i++) {
        session
          ..effect(
            'inspect',
            10 + i * 20,
            end: 20 + i * 20,
            place: 'lib/review.dart:55',
          )
          ..effect(
            'fix',
            20 + i * 20,
            end: 30 + i * 20,
            place: 'lib/review.dart:63',
          );
      }
      session.effect('inspect', 170, place: 'lib/review.dart:55');
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

    Finder list() => find.byType(EffectList);

    testWidgets('is scrolled to the selected last effect, and says how many '
        'effects are above it', (tester) async {
      await pumpLong(tester);

      expect(shownWithin(tester, row('l0ng-inspect-17'), list()), isTrue);
      final earlier = find.byKey(EffectList.earlierKey);
      expect(
        textIn(tester, earlier),
        matches(RegExp(r'^↑ \d+ earlier effects$')),
      );

      await tester.tap(earlier);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(earlier, findsNothing);
      expect(shownWithin(tester, row('l0ng-collect-0'), list()), isTrue);
    });

    testWidgets('follows the session: a new effect is selected and scrolled '
        'into view', (tester) async {
      final model = await pumpLong(tester);

      more
        ..add(
          EventAdded(
            sessionId: 'l0ng-session',
            event: EffectFinished(
              time: at(180),
              effectId: 'l0ng-inspect-17',
              outputId: 'report',
            ),
          ),
        )
        ..add(
          const EffectAdded(
            Effect(
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
            event: EffectStarted(time: at(181), effectId: 'l0ng-publish-18'),
          ),
        );
      await settle(tester);

      expect(model.selection.effectId, 'l0ng-publish-18');
      expect(shownWithin(tester, row('l0ng-publish-18'), list()), isTrue);
    });

    testWidgets('an effect selected on the canvas is scrolled into view', (
      tester,
    ) async {
      final model = await pumpLong(tester);
      expect(shownWithin(tester, row('l0ng-collect-0'), list()), isFalse);

      await tester.tap(find.byKey(NodeTile.tileKeyOf('1')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      expect(model.selection.effectId, 'l0ng-collect-0');
      expect(shownWithin(tester, row('l0ng-collect-0'), list()), isTrue);
    });
  });

  group('runs of calls (publishingSession)', () {
    final runs = publishingRows().whereType<RunRow>().toList();
    Finder run(int i) => find.byKey(EffectList.runKey(runs[i].key));

    Future<List<String>> pumpRuns(
      WidgetTester tester, {
      Set<String> open = const {},
      String? selected,
    }) async {
      final toggled = <String>[];
      await pumpScreen(
        tester,
        EffectList(
          rows: publishingRows(open: open),
          scale: TimeScale(at(0), at(100)),
          selectedEffectId: selected,
          following: false,
          onSelect: (_) {},
          onToggleRun: toggled.add,
        ),
      );
      return toggled;
    }

    testWidgets('a run is one row: its sign, a chevron to the right, the call '
        'and run n · effects, when it started and how long it took; a click '
        'opens it, by its key', (tester) async {
      final toggled = await pumpRuns(tester);
      expect(
        textIn(tester, run(0)),
        'publish() run 1 · 2 effects ${clockTime(at(10))} 30s',
      );
      expect(
        find.descendant(of: run(1), matching: find.byType(EffectIcon)),
        findsOneWidget,
      );
      expect(
        tester
            .widget<EffectIcon>(
              find.descendant(of: run(1), matching: find.byType(EffectIcon)),
            )
            .status,
        StartOutcome.failed,
      );
      final chevron = tester.widget<ChevronIcon>(
        find.descendant(of: run(0), matching: find.byType(ChevronIcon)),
      );
      expect((chevron.right, chevron.down), (true, false));
      expect(find.byKey(EffectList.rowKey('d5e6-upload-1')), findsNothing);

      await tester.tap(run(0));
      expect(toggled, [runs[0].key]);
    });

    testWidgets('an open run has its chevron down and its effects under it, '
        'their names indented', (tester) async {
      await pumpRuns(tester, open: {runs[0].key});
      final chevron = tester.widget<ChevronIcon>(
        find.descendant(of: run(0), matching: find.byType(ChevronIcon)),
      );
      expect(chevron.down, isTrue);
      final upload = find.byKey(EffectList.rowKey('d5e6-upload-1'));
      expect(upload, findsOneWidget);
      expect(tester.getTopLeft(upload).dy, tester.getBottomLeft(run(0)).dy);
      double nameLeft(Finder row, String name) => tester
          .getTopLeft(
            find.descendant(
              of: row,
              matching: find.textContaining(name, findRichText: true),
            ),
          )
          .dx;
      expect(
        nameLeft(upload, 'upload'),
        greaterThan(
          nameLeft(find.byKey(EffectList.rowKey('d5e6-plan-0')), 'plan'),
        ),
      );
    });

    testWidgets('a closed run over the selected effect is highlighted; open, '
        'the effect is', (tester) async {
      await pumpRuns(tester, selected: 'd5e6-verify-2');
      expect(fillOf(tester, run(0)), AppColors.accentSurface);
      expect(fillOf(tester, run(1)), const Color(0x00000000));

      await pumpRuns(tester, selected: 'd5e6-verify-2', open: {runs[0].key});
      expect(fillOf(tester, run(0)), const Color(0x00000000));
      expect(
        fillOf(tester, find.byKey(EffectList.rowKey('d5e6-verify-2'))),
        AppColors.accentSurface,
      );
    });

    testWidgets('opening a run keeps the list where it is, while following '
        'too', (tester) async {
      var open = <String>{};
      await pumpScreen(
        tester,
        StatefulBuilder(
          builder: (context, setState) => Align(
            alignment: Alignment.topLeft,
            // The title and three rows: the list scrolls.
            child: SizedBox(
              width: 548,
              height: 24 + 3 * 22,
              child: EffectList(
                rows: publishingRows(open: open),
                scale: TimeScale(at(0), at(100)),
                selectedEffectId: 'd5e6-announce-7',
                following: true,
                onSelect: (_) {},
                onToggleRun: (key) => setState(() => open = {...open, key}),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final list = find.byType(EffectList);
      await wheel(tester, list, -100);
      final top = tester.getTopLeft(run(0)).dy;

      await tester.tap(run(0));
      await tester.pump();
      await tester.pump();

      expect(open, {runs[0].key});
      expect(shownWithin(tester, run(0), list), isTrue);
      expect(tester.getTopLeft(run(0)).dy, top);
      expect(
        shownWithin(
          tester,
          find.byKey(EffectList.rowKey('d5e6-upload-1')),
          list,
        ),
        isTrue,
      );
    });
  });
}
