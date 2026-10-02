import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_model/nanoflow_model.dart' hide Route;
import 'package:nanoflow_ui/graph/session_bar.dart';
import 'package:nanoflow_ui/graph/sessions_column.dart';
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

  testWidgets('lists the sessions newest first, by the day and time they '
      'started', (tester) async {
    await pumpGraphScreen(tester);

    final lines = [
      'Today · 14:03:11',
      'Today · 13:27:40',
      'Today · 12:40:02',
      'Yesterday · 19:12:55',
      'Yesterday · 11:40:17',
      'Sep 18 · 16:05:33',
    ];
    final tops = [
      for (final line in lines) tester.getTopLeft(inColumn(find.text(line))).dy,
    ];
    expect(tops, orderedEquals([...tops]..sort()));
    expect(inColumn(find.text('Sessions')), findsOneWidget);
    expect(inColumn(find.text('6')), findsOneWidget);
  });

  testWidgets('shows a session by its short id, the full id in a tooltip', (
    tester,
  ) async {
    await pumpGraphScreen(tester);

    expect(inCard('a1b2-session', find.text('a1b2')), findsOneWidget);
    expect(
      inCard('a1b2-session', find.byTooltip('a1b2-session')),
      findsOneWidget,
    );
  });

  testWidgets('a running session is amber: Running for 12m 26s', (
    tester,
  ) async {
    await pumpGraphScreen(tester);

    final status = inCard('a1b2-session', find.text('Running for 12m 26s'));
    expect(status, findsOneWidget);
    expect(colorOf(tester, status), AppColors.running);
    expect(barOf(tester, 'a1b2-session'), AppColors.running);
  });

  testWidgets('a failed session is red: Failed in 6m 18s', (tester) async {
    await pumpGraphScreen(tester);

    final status = inCard('7c3e-s', find.text('Failed in 6m 18s'));
    expect(status, findsOneWidget);
    expect(colorOf(tester, status), AppColors.dangerText);
    expect(barOf(tester, '7c3e-s'), AppColors.failed);
  });

  testWidgets('a finished session is green: Finished in 3m 04s', (
    tester,
  ) async {
    await pumpGraphScreen(tester);

    final status = inCard('4b8d-s', find.text('Finished in 3m 04s'));
    expect(status, findsOneWidget);
    expect(colorOf(tester, status), AppColors.finishedText);
    expect(barOf(tester, '4b8d-s'), AppColors.finished);
  });

  testWidgets('a running session with failed runs says 1 failed', (
    tester,
  ) async {
    await pumpGraphScreen(tester);

    expect(inCard('f0a5-s', find.text('Running for 47m 57s')), findsOneWidget);
    expect(inCard('f0a5-s', find.text('1 failed')), findsOneWidget);
    // A failed session's failed run is in its status already.
    expect(find.text('1 failed'), findsOneWidget);
  });

  testWidgets('counts the runs of each session', (tester) async {
    await pumpGraphScreen(tester);

    expect(inCard('a1b2-session', find.text('3 runs')), findsOneWidget);
    expect(inCard('4b8d-s', find.text('1 run')), findsOneWidget);
  });

  testWidgets('a running session goes on counting its time', (tester) async {
    var now = Mockup.now;
    await pumpGraphScreen(tester, now: () => now);
    expect(find.text('Running for 12m 26s'), findsOneWidget);

    now = now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Running for 12m 27s'), findsOneWidget);
    expect(find.text('Finished in 3m 04s'), findsOneWidget);
  });

  group('the selection', () {
    testWidgets('highlights the selected session', (tester) async {
      await pumpGraphScreen(tester);

      expect(fillOf(tester, card('a1b2-session')), AppColors.accentSurface);
      expect(fillOf(tester, card('f0a5-s')), AppColors.card);
      expect(
        colorOf(tester, inCard('a1b2-session', find.text('a1b2'))),
        AppColors.accentText,
      );
      expect(
        colorOf(tester, inCard('f0a5-s', find.text('f0a5'))),
        AppColors.textFaint,
      );
    });

    testWidgets('a click on a session selects it', (tester) async {
      final model = await pumpGraphScreen(tester);

      await tester.tap(card('7c3e-s'));
      await tester.pump();

      expect(model.selection.sessionId, '7c3e-s');
      expect(fillOf(tester, card('7c3e-s')), AppColors.accentSurface);
      expect(fillOf(tester, card('a1b2-session')), AppColors.card);
    });

    testWidgets('Current graph is above the sessions; a click selects it', (
      tester,
    ) async {
      final model = await pumpGraphScreen(tester);
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

  testWidgets('Current graph counts the errors of the current graph', (
    tester,
  ) async {
    final model = await pumpGraphScreen(tester);
    expect(find.text('2 errors'), findsNothing);

    sourceOf(model).errors = const ['first', 'second'];
    await tester.pump();

    expect(
      find.descendant(
        of: find.byKey(SessionsColumn.currentGraphKey),
        matching: find.text('2 errors'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('without sessions: No runs yet and how to start one', (
    tester,
  ) async {
    final model = await pumpGraphScreen(
      tester,
      model: ownedModel(current: Graph.fromJson(reviewGraph)),
    );

    expect(model.selection.currentGraph, isTrue);
    expect(inColumn(find.text(noRunsYet)), findsOneWidget);
    expect(inColumn(find.text(noRunsHint(reviewFile))), findsOneWidget);
    expect(find.byKey(SessionsColumn.currentGraphKey), findsOneWidget);
  });
}
