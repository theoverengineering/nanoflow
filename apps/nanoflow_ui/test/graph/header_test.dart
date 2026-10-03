import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_ui/graph/header.dart';
import 'package:nanoflow_ui/platform/shell.dart';
import 'package:nanoflow_ui/state/graph_source.dart';

import 'support.dart';

void main() {
  /// A shell whose `open` exits with [exitCode]; what it was asked to run
  /// goes to [ran].
  Shell shellOpening(List<List<String>> ran, {int exitCode = 0}) => Shell(
    run: (executable, arguments) async {
      ran.add([executable, ...arguments]);
      return ProcessResult(0, exitCode, '', '');
    },
  );

  Finder inHeader(Finder finder) =>
      find.descendant(of: find.byType(GraphHeader), matching: finder);

  testWidgets('names the graph file and its directory', (tester) async {
    await pumpGraphScreen(tester);

    expect(inHeader(find.text('Graphs')), findsOneWidget);
    expect(inHeader(find.text('review.yaml')), findsOneWidget);
    expect(inHeader(find.text('~/Projects/review')), findsOneWidget);
  });

  testWidgets('Graphs leads back', (tester) async {
    var backs = 0;
    await pumpGraphScreen(tester, onBack: () => backs++);

    await tester.tap(inHeader(find.text('Graphs')));
    expect(backs, 1);
  });

  group('the Live badge', () {
    testWidgets('says the runs directory is watched', (tester) async {
      await pumpGraphScreen(tester);

      expect(inHeader(find.text('Live · watching runs/')), findsOneWidget);
    });

    testWidgets('says the graph is not live when its program has a problem', (
      tester,
    ) async {
      final model = await pumpGraphScreen(tester);
      sourceOf(model).programProblem = const SourceProblem(
        'nanoflow-yaml not found on PATH',
      );
      await tester.pump();

      expect(
        inHeader(find.text('Graph not live · watching runs/')),
        findsOneWidget,
      );
      expect(
        inHeader(find.byTooltip('nanoflow-yaml not found on PATH')),
        findsOneWidget,
      );
    });

    testWidgets('says the file is unavailable while it is gone', (
      tester,
    ) async {
      final model = await pumpGraphScreen(tester);
      sourceOf(model)
        ..programProblem = const SourceProblem(
          'nanoflow-yaml exited with code 1',
        )
        ..fileMissing = true;
      await tester.pump();

      expect(
        inHeader(find.text('File unavailable · watching runs/')),
        findsOneWidget,
      );

      sourceOf(model).fileMissing = false;
      await tester.pump();
      expect(
        inHeader(find.text('Graph not live · watching runs/')),
        findsOneWidget,
      );
    });
  });

  testWidgets('Reveal in Finder shows the graph file in Finder', (
    tester,
  ) async {
    final ran = <List<String>>[];
    await pumpGraphScreen(tester, shell: shellOpening(ran));

    await tester.tap(inHeader(find.text('Reveal in Finder')));
    await tester.pump();

    expect(ran, [
      ['/usr/bin/open', '-R', reviewFile],
    ]);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('Open in editor opens the graph file in the text editor', (
    tester,
  ) async {
    final ran = <List<String>>[];
    await pumpGraphScreen(tester, shell: shellOpening(ran));

    await tester.tap(inHeader(find.text('Open in editor')));
    await tester.pump();

    expect(ran, [
      ['/usr/bin/open', '-t', reviewFile],
    ]);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('says so for a while when Finder or the editor fails', (
    tester,
  ) async {
    final ran = <List<String>>[];
    await pumpGraphScreen(tester, shell: shellOpening(ran, exitCode: 1));

    await tester.tap(inHeader(find.text('Reveal in Finder')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Could not reveal review.yaml in Finder'), findsOneWidget);

    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(find.text('Could not reveal review.yaml in Finder'), findsNothing);

    await tester.tap(inHeader(find.text('Open in editor')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      find.text('Could not open review.yaml in an editor'),
      findsOneWidget,
    );
  });
}
