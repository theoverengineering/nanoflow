import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_model/nanoflow_model.dart' show LogCorrupted;
import 'package:nanoflow_ui/graph/session_bar.dart';
import 'package:nanoflow_ui/graph/sessions_column.dart';
import 'package:nanoflow_ui/state/graph_model.dart';
import 'package:nanoflow_ui/state/sessions.dart';
import 'package:nanoflow_ui/theme.dart';

import '../state/support.dart';
import 'canvas/support.dart';
import 'support.dart';

void main() {
  Finder card(String sessionId) =>
      find.byKey(SessionsColumn.cardKey(sessionId));

  Finder inCard(String sessionId, Finder finder) =>
      find.descendant(of: card(sessionId), matching: finder);

  Finder inColumn(Finder finder) =>
      find.descendant(of: find.byType(SessionsColumn), matching: finder);

  Color? colorOf(WidgetTester tester, Finder text) =>
      tester.widget<Text>(text).style?.color;

  Color barOf(WidgetTester tester, String sessionId) => tester
      .widget<ColoredBox>(
        inCard(sessionId, find.byKey(SessionsColumn.statusBarKey)),
      )
      .color;

  Color? fillOf(WidgetTester tester, Finder box) =>
      (tester.widget<Container>(box).decoration! as BoxDecoration).color;

  Future<GraphModel> pump(WidgetTester tester) =>
      pumpGraphScreen(tester, model: columnModel(), now: () => columnNow);

  testWidgets('lists the sessions newest first, by the day and time they '
      'started', (tester) async {
    await pump(tester);

    final lines = [
      'Today · 14:03:11',
      'Today · 13:27:40',
      'Today · 12:40:02',
      'Yesterday · 19:12:55',
    ];
    final tops = [
      for (final line in lines) tester.getTopLeft(inColumn(find.text(line))).dy,
    ];
    expect(tops, orderedEquals([...tops]..sort()));
    expect(inColumn(find.text('Sessions')), findsOneWidget);
    expect(inColumn(find.text('4')), findsOneWidget);
  });

  testWidgets('shows a session by its short id, the full id in a tooltip', (
    tester,
  ) async {
    await pump(tester);

    expect(inCard('a1b2-session', find.text('a1b2')), findsOneWidget);
    expect(
      inCard('a1b2-session', find.byTooltip('a1b2-session')),
      findsOneWidget,
    );
  });

  testWidgets('a running session is amber: Running for 12m 26s', (
    tester,
  ) async {
    await pump(tester);

    final status = inCard('a1b2-session', find.text('Running for 12m 26s'));
    expect(status, findsOneWidget);
    expect(colorOf(tester, status), AppColors.running);
    expect(barOf(tester, 'a1b2-session'), AppColors.running);
  });

  testWidgets('a failed session is red: Failed in 6m 18s', (tester) async {
    await pump(tester);

    final status = inCard('7c3e-session', find.text('Failed in 6m 18s'));
    expect(status, findsOneWidget);
    expect(colorOf(tester, status), AppColors.dangerText);
    expect(barOf(tester, '7c3e-session'), AppColors.failed);
  });

  testWidgets('a finished session is green: Finished in 3m 04s', (
    tester,
  ) async {
    await pump(tester);

    final status = inCard('4b8d-session', find.text('Finished in 3m 04s'));
    expect(status, findsOneWidget);
    expect(colorOf(tester, status), AppColors.finishedText);
    expect(barOf(tester, '4b8d-session'), AppColors.finished);
  });

  testWidgets('a session whose process is gone is interrupted: Interrupted '
      'after the time to its last event, why in a tooltip; its time stands '
      'still (owner spec §6)', (tester) async {
    var now = columnNow;
    await pumpGraphScreen(
      tester,
      model: ownedModel(
        file: releaseFile,
        changes: changesOf([
          Journal('a1b2-session', workflow: 'release')
            ..effect('plan', 1, end: 5)
            ..effect('build', 5)
            ..processGone(),
        ]),
      ),
      now: () => now,
    );

    final status = inCard('a1b2-session', find.text('Interrupted after 5s'));
    expect(status, findsOneWidget);
    // Muted: nothing goes on — not the amber of running.
    expect(AppColors.interrupted, AppColors.textMuted);
    expect(colorOf(tester, status), AppColors.interrupted);
    expect(barOf(tester, 'a1b2-session'), AppColors.interrupted);
    expect(
      inCard('a1b2-session', find.byTooltip(interruptedWhy)),
      findsOneWidget,
    );

    now = now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(status, findsOneWidget);
  });

  testWidgets('a running session with failed effects says 1 failed', (
    tester,
  ) async {
    await pump(tester);

    expect(
      inCard('f0a5-session', find.text('Running for 47m 57s')),
      findsOneWidget,
    );
    expect(inCard('f0a5-session', find.text('1 failed')), findsOneWidget);
    // A failed session's failed effect is in its status already.
    expect(find.text('1 failed'), findsOneWidget);
  });

  testWidgets('a session that ran on other code says so, and its status '
      'stays whole at the default width', (tester) async {
    await pumpGraphScreen(
      tester,
      model: ownedModel(
        file: releaseFile,
        changes: changesOf([
          Journal(
              'f0a5-session',
              workflow: 'release',
              startedAt: -2131,
              code: 'sha256:other',
            )
            ..effect('plan', -2130, end: -2120)
            ..effect('build', -2120, end: -2100, failed: true)
            ..effect('build', -2000),
          Journal('c3d4-session', workflow: 'release', code: null)
            ..effect('plan', 1),
        ]),
      ),
      now: () => columnNow,
    );

    for (final (id, status, note) in [
      ('f0a5-session', 'Running for 47m 57s', 'other code'),
      ('c3d4-session', 'Running for 12m 26s', 'not checked'),
    ]) {
      expect(inCard(id, find.text(note)), findsOneWidget);
      final shown = tester.renderObject<RenderParagraph>(
        inCard(id, find.text(status)),
      );
      expect(shown.didExceedMaxLines, isFalse, reason: status);
    }
    expect(inCard('f0a5-session', find.text('1 failed')), findsOneWidget);
    expect(inCard('f0a5-session', find.text('3 effects')), findsOneWidget);
  });

  testWidgets('1 failed goes first on the line under the status, so the '
      'status and the count stay whole at the default width', (tester) async {
    // The longest a running session's status and count get in its first
    // hour, `Running for 59m 59s` and `99 effects`, with `1 failed` between
    // them take 225 px with no gaps at all; a card has 224 px inside the
    // default 272 px column. No gap makes them fit on one line: `1 failed`
    // goes on the line of the notes, before `other code`.
    final journal = Journal(
      'f0a5-session',
      workflow: 'release',
      startedAt: -2853,
      code: 'sha256:other',
    )..effect('build', -2852, end: -2851, failed: true);
    for (var i = 1; i < 99; i++) {
      journal.effect('build', -2851 + i, end: -2851 + i);
    }
    await pumpGraphScreen(
      tester,
      model: ownedModel(file: releaseFile, changes: changesOf([journal])),
      now: () => columnNow,
    );

    final status = inCard('f0a5-session', find.text('Running for 59m 59s'));
    final count = inCard('f0a5-session', find.text('99 effects'));
    final failed = inCard('f0a5-session', find.text('1 failed'));
    final note = inCard('f0a5-session', find.text('other code'));
    expect(
      tester.renderObject<RenderParagraph>(status).didExceedMaxLines,
      isFalse,
    );
    expect(
      tester.getRect(count).right,
      lessThan(tester.getRect(card('f0a5-session')).right),
    );
    expect(
      tester.getRect(failed).top,
      greaterThanOrEqualTo(tester.getRect(status).bottom),
    );
    expect(
      tester.getCenter(failed).dy,
      moreOrLessEquals(tester.getCenter(note).dy, epsilon: 1),
    );
    expect(tester.getRect(failed).right, lessThan(tester.getRect(note).left));
  });

  testWidgets('a session resumed on changed code says so on its card', (
    tester,
  ) async {
    await pumpGraphScreen(
      tester,
      model: ownedModel(
        file: releaseFile,
        changes: changesOf([
          Journal('a1b2-session', workflow: 'release')
            ..effect('plan', 1, end: 5)
            ..resume(6, code: 'sha256:edited')
            ..effect('build', 7),
          Journal('c3d4-session', workflow: 'release', startedAt: -100)
            ..effect('plan', -99),
        ]),
      ),
      now: () => columnNow,
    );

    expect(
      inCard('a1b2-session', find.text(resumedOnChangedCode)),
      findsOneWidget,
    );
    expect(
      inCard('c3d4-session', find.text(resumedOnChangedCode)),
      findsNothing,
    );
  });

  /// f0a5 ran on other code, and line 4 of its journal is not an event;
  /// c3d4 was read whole.
  Future<void> pumpIncomplete(WidgetTester tester) async {
    final journal = Journal(
      'f0a5-session',
      workflow: 'release',
      startedAt: -2131,
      code: 'sha256:other',
    )..effect('plan', -2130, end: -2120);
    await pumpGraphScreen(
      tester,
      model: ownedModel(
        file: releaseFile,
        changes: [
          ...changesOf([
            journal,
            Journal('c3d4-session', workflow: 'release')..effect('plan', 1),
          ]),
          const LogCorrupted(
            sessionId: 'f0a5-session',
            line: 4,
            text: '{"time": 1}',
          ),
        ],
      ),
      now: () => columnNow,
    );
  }

  double middleOf(WidgetTester tester, String sessionId, String text) =>
      tester.getCenter(inCard(sessionId, find.text(text))).dy;

  testWidgets('a session whose journal was read incompletely is marked Log '
      'read incompletely on the line of its other code, why in a tooltip, '
      'and its status stays whole', (tester) async {
    await pumpIncomplete(tester);

    expect(
      inCard('f0a5-session', find.text(logReadIncompletely)),
      findsOneWidget,
    );
    expect(
      middleOf(tester, 'f0a5-session', logReadIncompletely),
      moreOrLessEquals(
        middleOf(tester, 'f0a5-session', 'other code'),
        epsilon: 1,
      ),
    );
    expect(
      inCard(
        'f0a5-session',
        find.byTooltip(
          '$logReadIncompletely\nline 4 is not an event: {"time": 1}',
        ),
      ),
      findsOneWidget,
    );
    final status = tester.renderObject<RenderParagraph>(
      inCard('f0a5-session', find.text('Running for 47m 57s')),
    );
    expect(status.didExceedMaxLines, isFalse);
    expect(
      inCard('c3d4-session', find.text(logReadIncompletely)),
      findsNothing,
    );
  });

  testWidgets('in the narrowest column the Log read incompletely mark goes '
      'under the other code note instead of overflowing', (tester) async {
    await pumpIncomplete(tester);
    // The column's border, dragged as far left as it goes: 200 px.
    await tester.dragFrom(
      const Offset(271.5, 300),
      const Offset(-200, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    expect(tester.getSize(find.byType(SessionsColumn)).width, 199);

    expect(
      middleOf(tester, 'f0a5-session', logReadIncompletely),
      greaterThan(middleOf(tester, 'f0a5-session', 'other code')),
    );
    expect(
      inCard('f0a5-session', find.text(logReadIncompletely)),
      findsOneWidget,
    );
  });

  testWidgets('counts the effects of each session', (tester) async {
    await pump(tester);

    expect(inCard('a1b2-session', find.text('2 effects')), findsOneWidget);
    expect(inCard('4b8d-session', find.text('1 effect')), findsOneWidget);
  });

  testWidgets('a running session goes on counting its time', (tester) async {
    var now = columnNow;
    await pumpGraphScreen(tester, model: columnModel(), now: () => now);
    expect(find.text('Running for 12m 26s'), findsOneWidget);

    now = now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Running for 12m 27s'), findsOneWidget);
    expect(find.text('Finished in 3m 04s'), findsOneWidget);
  });

  group('the selection', () {
    testWidgets('highlights the selected session', (tester) async {
      await pump(tester);

      expect(fillOf(tester, card('a1b2-session')), AppColors.accentSurface);
      expect(fillOf(tester, card('f0a5-session')), AppColors.card);
      expect(
        colorOf(tester, inCard('a1b2-session', find.text('a1b2'))),
        AppColors.accentText,
      );
      expect(
        colorOf(tester, inCard('f0a5-session', find.text('f0a5'))),
        AppColors.textFaint,
      );
    });

    testWidgets('a click on a session selects it', (tester) async {
      final model = await pump(tester);

      await tester.tap(card('7c3e-session'));
      await tester.pump();

      expect(model.selection.sessionId, '7c3e-session');
      expect(fillOf(tester, card('7c3e-session')), AppColors.accentSurface);
      expect(fillOf(tester, card('a1b2-session')), AppColors.card);
    });

    testWidgets('Current graph is above the sessions; a click selects it', (
      tester,
    ) async {
      final model = await pump(tester);
      final current = find.byKey(SessionsColumn.currentGraphKey);
      expect(
        tester.getTopLeft(current).dy,
        lessThan(tester.getTopLeft(card('a1b2-session')).dy),
      );
      expect(fillOf(tester, current), AppColors.card);

      await tester.tap(current);
      await tester.pump();

      expect(model.selection.currentGraph, isTrue);
      expect(fillOf(tester, current), AppColors.accentSurface);
      expect(fillOf(tester, card('a1b2-session')), AppColors.card);
      expect(find.byType(SessionBar), findsOneWidget);
      expect(find.text('Session'), findsNothing);
    });
  });

  testWidgets('without sessions: No sessions yet and where they come from', (
    tester,
  ) async {
    final model = await pumpGraphScreen(tester);

    expect(model.selection.currentGraph, isTrue);
    expect(inColumn(find.text(noSessionsYet)), findsOneWidget);
    expect(inColumn(find.text(noSessionsHint(releaseFile))), findsOneWidget);
    expect(find.byKey(SessionsColumn.currentGraphKey), findsOneWidget);
  });
}
