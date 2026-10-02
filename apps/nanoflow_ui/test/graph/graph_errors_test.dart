import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_model/nanoflow_model.dart' hide Route;
import 'package:nanoflow_ui/graph/canvas/node_tile.dart';
import 'package:nanoflow_ui/graph/graph_errors.dart';
import 'package:nanoflow_ui/graph/session_bar.dart';
import 'package:nanoflow_ui/state/graph_source.dart';
import 'package:nanoflow_ui/state/sessions.dart';

import '../state/support.dart';
import 'canvas/support.dart';
import 'support.dart';

void main() {
  const errors = [
    'nodes.verdict.then.accepted[0]: no node named "pubish"',
    'nodes.fix: no node leads here',
  ];

  Finder inProblems(Finder finder) =>
      find.descendant(of: find.byType(GraphProblems), matching: finder);

  /// A screen of the review graph, opened before any session, so that
  /// `Current graph` is selected; its source as the test sets it.
  Future<FixedSource> pumpCurrentGraph(
    WidgetTester tester, {
    Graph? current,
  }) async {
    final model = await pumpGraphScreen(
      tester,
      model: ownedModel(current: current),
    );
    expect(model.selection.currentGraph, isTrue);
    return sourceOf(model);
  }

  testWidgets('a graph that fails check: its errors over the last graph '
      'that passed', (tester) async {
    final source = await pumpCurrentGraph(
      tester,
      current: Graph.fromJson(reviewGraph),
    );
    source.errors = errors;
    await tester.pump();

    for (final error in errors) {
      expect(inProblems(find.text(error)), findsOneWidget);
    }
    expect(inProblems(find.text(checkFailed(2))), findsOneWidget);
    expect(inProblems(find.text(lastValidGraphShown)), findsOneWidget);
    expect(find.byKey(NodeTile.tileKeyOf('verdict')), findsOneWidget);
  });

  testWidgets('a graph that fails check with no graph before it: '
      'No valid graph yet', (tester) async {
    final source = await pumpCurrentGraph(tester);
    source.errors = errors.sublist(0, 1);
    await tester.pump();

    expect(find.text(noValidGraphYet), findsOneWidget);
    expect(inProblems(find.text(checkFailed(1))), findsOneWidget);
    expect(inProblems(find.text(errors.first)), findsOneWidget);
    expect(inProblems(find.text(lastValidGraphShown)), findsNothing);
    expect(find.byType(NodeTile), findsNothing);
  });

  testWidgets('a graph file deleted while open: the last graph stays, and '
      'File unavailable', (tester) async {
    final source = await pumpCurrentGraph(
      tester,
      current: Graph.fromJson(reviewGraph),
    );
    source.fileMissing = true;
    await tester.pump();

    expect(inProblems(find.text(fileUnavailable)), findsOneWidget);
    expect(
      inProblems(find.text(fileUnavailableDetail('review.yaml'))),
      findsOneWidget,
    );
    expect(find.byKey(NodeTile.tileKeyOf('verdict')), findsOneWidget);
  });

  testWidgets('a graph program not found: what is wrong', (tester) async {
    final source = await pumpCurrentGraph(tester);
    source.programProblem = const SourceProblem(
      'nanoflow-yaml not found on PATH',
    );
    await tester.pump();

    expect(
      inProblems(find.text('nanoflow-yaml not found on PATH')),
      findsOneWidget,
    );
    expect(find.text(noValidGraphYet), findsOneWidget);
  });

  testWidgets('a graph program that exited: what is wrong, and its last '
      'words', (tester) async {
    final source = await pumpCurrentGraph(
      tester,
      current: Graph.fromJson(reviewGraph),
    );
    source.programProblem = const SourceProblem(
      'nanoflow-yaml exited with code 255',
      'Unhandled exception:\nFileSystemException: Cannot open file',
    );
    await tester.pump();

    expect(
      inProblems(find.text('nanoflow-yaml exited with code 255')),
      findsOneWidget,
    );
    expect(
      inProblems(
        find.text(
          'Unhandled exception:\nFileSystemException: Cannot open file',
        ),
      ),
      findsOneWidget,
    );
    expect(find.byKey(NodeTile.tileKeyOf('verdict')), findsOneWidget);
  });

  testWidgets('nanoflow not found: the graph is drawn, not checked', (
    tester,
  ) async {
    final source = await pumpCurrentGraph(
      tester,
      current: Graph.fromJson(reviewGraph),
    );
    source.checkProblem = 'nanoflow not found on PATH — graph not checked';
    await tester.pump();

    expect(
      inProblems(find.text('nanoflow not found on PATH — graph not checked')),
      findsOneWidget,
    );
  });

  testWidgets('the graph is fitted clear of the problems over it, and back '
      'up once they are gone', (tester) async {
    final source = await pumpCurrentGraph(
      tester,
      current: Graph.fromJson(reviewGraph),
    );
    double top() => [
      for (final node
          in (reviewGraph['nodes']! as Map<String, Object?>).entries)
        tester.getRect(find.byKey(NodeTile.keyOf(node.key))).top,
    ].reduce(math.min);
    final clear = top();

    source
      ..errors = errors
      ..fileMissing = true
      ..programProblem = const SourceProblem(
        'nanoflow-yaml exited with code 255',
        'Unhandled exception:\nFileSystemException: Cannot open file',
      );
    await settle(tester);
    final problems = tester.getRect(
      find.descendant(
        of: find.byType(GraphProblems),
        matching: find.byType(IntrinsicWidth),
      ),
    );
    expect(top(), greaterThan(problems.bottom));

    source
      ..errors = const []
      ..fileMissing = false
      ..programProblem = null;
    await settle(tester);
    expect(top(), moreOrLessEquals(clear));
  });

  testWidgets('over a session the canvas shows its own graph: the current '
      "graph's problems are not over it", (tester) async {
    final model = await pumpGraphScreen(tester);
    sourceOf(model)
      ..errors = errors
      ..fileMissing = true
      ..programProblem = const SourceProblem('nanoflow-yaml exited');
    await tester.pump();
    expect(inProblems(find.text(fileUnavailable)), findsNothing);
    expect(inProblems(find.text(errors.first)), findsNothing);
    expect(
      find.descendant(
        of: find.byType(SessionBar),
        matching: find.text('Session'),
      ),
      findsOneWidget,
    );

    model.selection.showCurrentGraph();
    await tester.pump();
    expect(inProblems(find.text(fileUnavailable)), findsOneWidget);
    expect(inProblems(find.text(errors.first)), findsOneWidget);
    expect(inProblems(find.text('nanoflow-yaml exited')), findsOneWidget);
  });

  testWidgets('a graph without sessions: drawn, and No runs yet', (
    tester,
  ) async {
    await pumpCurrentGraph(tester, current: Graph.fromJson(reviewGraph));

    expect(find.byKey(NodeTile.tileKeyOf('collect')), findsOneWidget);
    expect(find.text(noRunsYet), findsOneWidget);
    expect(find.byType(GraphProblems), findsOneWidget);
    expect(inProblems(find.textContaining('')), findsNothing);
  });
}
