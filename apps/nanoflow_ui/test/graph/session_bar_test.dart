import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_ui/graph/canvas/node_tile.dart';
import 'package:nanoflow_ui/graph/session_bar.dart';
import 'package:nanoflow_ui/graph/sessions_column.dart';
import 'package:nanoflow_ui/state/graph_model.dart';
import 'package:nanoflow_ui/state/sessions.dart' show resumedOnChangedCode;
import 'package:nanoflow_ui/theme.dart';

import '../state/support.dart' show Journal, changesOf;
import 'canvas/support.dart' show ownedModel;
import 'support.dart';

void main() {
  Finder inBar(Finder finder) =>
      find.descendant(of: find.byType(SessionBar), matching: finder);

  Future<GraphModel> pump(WidgetTester tester) =>
      pumpGraphScreen(tester, model: columnModel(), now: () => columnNow);

  Future<void> select(WidgetTester tester, String sessionId) async {
    await tester.tap(find.byKey(SessionsColumn.cardKey(sessionId)));
    await tester.pump();
  }

  testWidgets('names the session, when it started and how it is', (
    tester,
  ) async {
    await pump(tester);

    for (final text in ['Session', 'a1b2', 'started 14:03:11']) {
      expect(inBar(find.text(text)), findsOneWidget);
    }
    expect(inBar(find.byTooltip('a1b2-session')), findsOneWidget);
    final status = inBar(find.text('running 12m 26s'));
    expect(tester.widget<Text>(status).style!.color, AppColors.running);
  });

  testWidgets('a failed session: failed in 6m 18s', (tester) async {
    await pump(tester);
    await select(tester, '7c3e-session');

    expect(inBar(find.text('7c3e')), findsOneWidget);
    final status = inBar(find.text('failed in 6m 18s'));
    expect(tester.widget<Text>(status).style!.color, AppColors.dangerText);
  });

  testWidgets('a finished session: finished in 3m 04s', (tester) async {
    await pump(tester);
    await select(tester, '4b8d-session');

    final status = inBar(find.text('finished in 3m 04s'));
    expect(tester.widget<Text>(status).style!.color, AppColors.finishedText);
  });

  testWidgets('a session resumed on changed code says so', (tester) async {
    await pumpGraphScreen(
      tester,
      model: ownedModel(
        file: releaseFile,
        changes: changesOf([
          Journal('a1b2-session', workflow: 'release')
            ..step('plan', 1, end: 5)
            ..resume(6, code: 'sha256:edited')
            ..step('build', 7),
        ]),
      ),
      now: () => columnNow,
    );

    final mark = inBar(find.text(resumedOnChangedCode));
    expect(mark, findsOneWidget);
    expect(tester.widget<Text>(mark).style!.color, AppColors.noteText);
    expect(inBar(find.text('running 12m 26s')), findsOneWidget);
  });

  testWidgets('a session that was not resumed on changed code has no such '
      'mark', (tester) async {
    await pump(tester);

    expect(inBar(find.text(resumedOnChangedCode)), findsNothing);
  });

  testWidgets('stays put while the canvas under it moves', (tester) async {
    await pump(tester);
    final bar = tester.getRect(inBar(find.text('Session')));
    final node = tester.getRect(find.byKey(NodeTile.tileKeyOf('1')));

    await tester.dragFrom(const Offset(700, 400), const Offset(-120, 60));
    await tester.pump();

    expect(tester.getRect(inBar(find.text('Session'))), bar);
    expect(tester.getRect(find.byKey(NodeTile.tileKeyOf('1'))), isNot(node));
  });

  testWidgets('is not there for Current graph; the zoom buttons are', (
    tester,
  ) async {
    final model = await pump(tester);
    model.selection.showCurrentGraph();
    await tester.pump();

    expect(inBar(find.text('Session')), findsNothing);
    expect(find.byTooltip('Zoom to fit'), findsOneWidget);
  });
}
