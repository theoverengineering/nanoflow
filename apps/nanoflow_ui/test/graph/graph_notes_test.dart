import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_ui/graph/graph_notes.dart';
import 'package:nanoflow_ui/state/freshness.dart';
import 'package:nanoflow_ui/state/graph_model.dart';
import 'package:nanoflow_ui/state/session_view.dart';
import 'package:nanoflow_ui/theme.dart';

import '../state/support.dart';
import '../support/golden.dart';

void main() {
  const file = '/Users/me/Projects/review/nanoflow.graph.json';

  /// The notes over the canvas: [notes], their height told to [heights].
  Future<void> pumpNotes(
    WidgetTester tester,
    List<GraphNote> notes, {
    List<double>? heights,
  }) async {
    await pumpScreen(
      tester,
      Scaffold(
        body: GraphNotes(notes: notes, onHeight: heights?.add),
      ),
    );
    await tester.pump();
  }

  Finder inNotes(Finder finder) =>
      find.descendant(of: find.byType(GraphNotes), matching: finder);

  Color colorOf(WidgetTester tester, String text) =>
      tester.widget<Text>(inNotes(find.text(text))).style!.color!;

  List<GraphNote> sessionNotes(Journal session) => sessionCanvas(
    session.data,
    sessionGraphOf(
      session.data,
      documents: outcomesOf(const {}),
      graphFile: reviewGraphFile(fingerprint: 'sha256:now'),
    ),
  ).notes;

  testWidgets('a graph file that matches its code and has no warnings: '
      'nothing', (tester) async {
    final heights = <double>[];
    await pumpNotes(
      tester,
      fileCanvas(
        file: file,
        graph: reviewGraphFile(),
        workflowId: 'lib/review.dart#review',
        freshness: const Freshness(stale: false, changed: []),
      ).notes,
      heights: heights,
    );
    expect(inNotes(find.byType(Text)), findsNothing);
    expect(heights, isEmpty);
  });

  testWidgets('a graph that may not match the code: amber, with the files '
      'that changed', (tester) async {
    await pumpNotes(
      tester,
      fileCanvas(
        file: file,
        graph: reviewGraphFile(),
        workflowId: 'lib/review.dart#review',
        freshness: const Freshness(
          stale: true,
          changed: ['lib/review.dart', 'review'],
        ),
      ).notes,
    );
    expect(colorOf(tester, graphMayNotMatchCode), AppColors.running);
    expect(inNotes(find.text('lib/review.dart')), findsOneWidget);
    expect(inNotes(find.text('review')), findsOneWidget);
    expect(inNotes(find.text(changedSinceWritten)), findsOneWidget);
  });

  testWidgets('the warnings of the graph file: listed with their places', (
    tester,
  ) async {
    await pumpNotes(
      tester,
      fileCanvas(
        file: file,
        graph: reviewGraphFile(
          warnings: [
            {
              'place': 'lib/review.dart:40',
              'message': 'steps in a closure passed on are not drawn',
            },
          ],
        ),
        workflowId: 'lib/review.dart#review',
      ).notes,
    );
    expect(
      colorOf(tester, '1 warning in nanoflow.graph.json'),
      AppColors.running,
    );
    expect(
      inNotes(
        find.text(
          'lib/review.dart:40  steps in a closure passed on are not drawn',
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a graph file gone or broken: red, over the last graph read', (
    tester,
  ) async {
    await pumpNotes(
      tester,
      fileCanvas(
        file: file,
        graph: reviewGraphFile(),
        workflowId: 'lib/review.dart#review',
        fileMissing: true,
        error: 'Unexpected end of input at line 1, column 14',
      ).notes,
    );
    expect(colorOf(tester, fileUnavailable), AppColors.dangerText);
    expect(
      inNotes(
        find.text(
          fileUnavailableDetail('nanoflow.graph.json', graphKept: true),
        ),
      ),
      findsOneWidget,
    );
    expect(
      colorOf(tester, fileUnreadable('nanoflow.graph.json')),
      AppColors.dangerText,
    );
    expect(
      inNotes(find.text('Unexpected end of input at line 1, column 14')),
      findsOneWidget,
    );
    expect(inNotes(find.text(lastGraphShown)), findsOneWidget);
  });

  testWidgets('sessions of workflows the graph file does not have: amber, '
      'with the workflows', (tester) async {
    await pumpNotes(
      tester,
      fileCanvas(
        file: file,
        graph: reviewGraphFile(),
        workflowId: 'lib/review.dart#review',
        extraNotes: workflowNotes(
          file: file,
          workflow: null,
          notInGraph: const {'backup': 1, 'deploy': 2},
        ),
      ).notes,
    );
    expect(
      colorOf(tester, '3 sessions of workflows not in nanoflow.graph.json'),
      AppColors.running,
    );
    expect(inNotes(find.text('backup')), findsOneWidget);
    expect(inNotes(find.text('deploy')), findsOneWidget);
    expect(inNotes(find.text(notInGraphFileDetail)), findsOneWidget);
  });

  testWidgets('a workflow the graph file does not have, chosen', (
    tester,
  ) async {
    await pumpNotes(
      tester,
      fileCanvas(
        file: file,
        graph: reviewGraphFile(),
        workflowId: 'deploy',
        extraNotes: workflowNotes(
          file: file,
          workflow: workflowChoices(reviewGraphFile(), [
            Journal('d1d1-session', workflow: 'deploy').data,
          ]).last,
          notInGraph: const {'deploy': 1},
        ),
      ).notes,
    );
    expect(
      colorOf(tester, workflowNotInFile('deploy', 'nanoflow.graph.json')),
      AppColors.running,
    );
    expect(inNotes(find.text(graphFileMayBeStale)), findsOneWidget);
    expect(
      inNotes(find.text('1 session of workflows not in nanoflow.graph.json')),
      findsNothing,
    );
  });

  testWidgets('a session that ran on other code', (tester) async {
    await pumpNotes(
      tester,
      sessionNotes(Journal('a1b2-session')..resume(10, code: 'sha256:x')),
    );
    expect(colorOf(tester, sessionRanOnOtherCode), AppColors.running);
    expect(inNotes(find.text(otherCodeDetail)), findsOneWidget);
  });

  testWidgets('a session whose code was not checked', (tester) async {
    await pumpNotes(tester, sessionNotes(Journal('a1b2-session', code: null)));
    expect(colorOf(tester, sessionCodeNotChecked), AppColors.running);
    expect(inNotes(find.text(notCheckedDetail)), findsOneWidget);
  });

  testWidgets('a session without a snapshot', (tester) async {
    await pumpNotes(
      tester,
      sessionNotes(
        Journal('a1b2-session', snapshot: false, code: 'sha256:now'),
      ),
    );
    expect(colorOf(tester, sessionHasNoSnapshot), AppColors.running);
    expect(inNotes(find.text(noSnapshotDetail)), findsOneWidget);
    expect(inNotes(find.text(sessionRanOnOtherCode)), findsNothing);
  });

  testWidgets('tells how tall the notes are, and 0 once they are gone', (
    tester,
  ) async {
    final heights = <double>[];
    final notes = sessionNotes(Journal('a1b2-session', code: null));
    await pumpNotes(tester, notes, heights: heights);
    expect(heights.single, greaterThan(0));
    expect(
      heights.single,
      tester
          .getSize(
            find.descendant(
              of: find.byType(GraphNotes),
              matching: find.byType(IntrinsicWidth),
            ),
          )
          .height,
    );

    await pumpNotes(tester, const [], heights: heights);
    expect(heights.last, 0);
  });

  testWidgets('the notes can be selected and copied', (tester) async {
    await pumpNotes(tester, sessionNotes(Journal('a1b2-session', code: null)));
    expect(inNotes(find.byType(SelectionArea)), findsOneWidget);
  });
}
