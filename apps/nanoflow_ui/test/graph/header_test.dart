import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_model/nanoflow_model.dart' hide Route;
import 'package:nanoflow_ui/graph/header.dart';
import 'package:nanoflow_ui/platform/shell.dart';
import 'package:nanoflow_ui/state/body_path.dart';
import 'package:nanoflow_ui/theme.dart';

import '../state/support.dart';
import 'canvas/support.dart';
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

  const publish = Opened('5', functionId: 'lib/publish.dart#publish');

  /// The release fixture with publish as a workflow too.
  GraphFile twoWorkflows() => GraphFile.fromJson({
    ...graphFileNamed('release').toJson(),
    'workflows': ['lib/release.dart#release', 'lib/publish.dart#publish'],
  });

  testWidgets('names the graph file, its directory and the workflow', (
    tester,
  ) async {
    await pumpGraphScreen(tester);

    expect(inHeader(find.text('Graphs')), findsOneWidget);
    expect(inHeader(find.text(graphFileName)), findsOneWidget);
    expect(inHeader(find.text('~/Projects/release')), findsOneWidget);
    expect(inHeader(find.text('release')), findsOneWidget);
    // One workflow: nothing to choose.
    expect(inHeader(find.byKey(GraphHeader.workflowKey)), findsNothing);
  });

  testWidgets('Graphs leads back', (tester) async {
    var backs = 0;
    await pumpGraphScreen(tester, onBack: () => backs++);

    await tester.tap(inHeader(find.text('Graphs')));
    expect(backs, 1);
  });

  group('the crumbs', () {
    testWidgets('lead from the workflow down to the body drawn; a crumb '
        'goes back up to its level', (tester) async {
      final model = await pumpGraphScreen(tester);
      model.open(publish);
      await tester.pump();

      expect(inHeader(find.text('release')), findsOneWidget);
      expect(inHeader(find.text('publish()')), findsOneWidget);
      expect(inHeader(find.text('›')), findsOneWidget);

      // The crumb of the body drawn leads nowhere.
      await tester.tap(inHeader(find.text('publish()')));
      await tester.pump();
      expect(model.canvas.levels, hasLength(2));

      await tester.tap(inHeader(find.text('release')));
      await tester.pump();
      expect(model.canvas.levels, hasLength(1));
      expect(inHeader(find.text('publish()')), findsNothing);
    });

    testWidgets('are none while there is no workflow to draw', (tester) async {
      await pumpGraphScreen(tester, model: ownedModel(noGraph: true));
      expect(inHeader(find.text('›')), findsNothing);
      expect(inHeader(find.byKey(GraphHeader.workflowKey)), findsNothing);
    });

    testWidgets('with several workflows the workflow\'s crumb goes back up; '
        'its chevron lists the workflows', (tester) async {
      final model = await pumpGraphScreen(
        tester,
        model: ownedModel(graph: twoWorkflows()),
      );
      model.open(publish);
      await tester.pump();

      await tester.tap(inHeader(find.text('release')));
      await tester.pumpAndSettle();
      expect(model.canvas.levels, hasLength(1));
      expect(find.byType(PopupMenuItem<String>), findsNothing);

      await tester.tap(inHeader(find.byKey(GraphHeader.workflowKey)));
      await tester.pumpAndSettle();
      expect(find.byType(PopupMenuItem<String>), findsNWidgets(2));
    });

    testWidgets('of a deep path fit the narrowest window: the middle ones '
        'fold into …, which lists them', (tester) async {
      // crawl calls visit, which calls crawl: as deep as one goes.
      final model = await pumpGraphScreen(
        tester,
        model: ownedModel(graph: graphFileNamed('recursion')),
        size: const Size(1100, 700),
      );
      for (var i = 0; i < 4; i++) {
        model
          ..open(const Opened('3', functionId: 'lib/crawl.dart#visit'))
          ..open(const Opened('2', functionId: 'lib/crawl.dart#crawl'));
      }
      model.open(const Opened('3', functionId: 'lib/crawl.dart#visit'));
      await tester.pump();
      expect(model.canvas.levels, hasLength(10));

      // Nothing is pushed out of the header.
      final open = tester.getRect(inHeader(find.text('Open in editor')));
      expect(open.right, lessThanOrEqualTo(1100 - 16));
      final folded = inHeader(find.byKey(GraphHeader.foldedKey));
      expect(folded, findsOneWidget);
      // The workflow and the body drawn stay.
      expect(inHeader(find.text('crawl')), findsOneWidget);
      expect(
        tester.getRect(folded).left,
        greaterThan(tester.getRect(inHeader(find.text('crawl'))).right),
      );
      expect(inHeader(find.text('visit()')), findsWidgets);

      await tester.tap(folded);
      await tester.pumpAndSettle();
      final menu = find.byType(PopupMenuItem<int>);
      expect(menu, findsWidgets);
      final first = find.descendant(of: menu, matching: find.text('visit()'));
      await tester.tap(first.first);
      await tester.pumpAndSettle();
      expect(model.canvas.levels, hasLength(2));
      expect(inHeader(find.byKey(GraphHeader.foldedKey)), findsNothing);
    });

    testWidgets('a wide window shows them all', (tester) async {
      final model = await pumpGraphScreen(tester);
      model.open(publish);
      await tester.pump();
      expect(inHeader(find.byKey(GraphHeader.foldedKey)), findsNothing);
    });
  });

  testWidgets('the graph file\'s name is not drawn as a link', (tester) async {
    final model = await pumpGraphScreen(tester);
    final style = tester.widget<Text>(inHeader(find.text(graphFileName))).style;
    expect(style, AppText.headerFile);
    model.open(publish);
    await tester.pump();
    expect(
      tester.widget<Text>(inHeader(find.text(graphFileName))).style,
      AppText.headerFile,
    );
  });

  group('the workflow picker', () {
    testWidgets('lists the workflows of the graph file, then those only '
        'sessions ran, marked; a choice draws its top level', (tester) async {
      final model = await pumpGraphScreen(
        tester,
        model: ownedModel(
          graph: twoWorkflows(),
          changes: changesOf([Journal('d1d1-session', workflow: 'deploy')]),
        ),
      );
      model.open(publish);
      await tester.pump();

      await tester.tap(inHeader(find.byKey(GraphHeader.workflowKey)));
      await tester.pumpAndSettle();
      final menu = find.byType(PopupMenuItem<String>);
      expect(menu, findsNWidgets(3));
      for (final name in ['release', 'publish', 'deploy']) {
        expect(
          find.descendant(of: menu, matching: find.text(name)),
          findsOneWidget,
        );
      }
      expect(
        find.descendant(of: menu, matching: find.text('not in the graph file')),
        findsOneWidget,
      );

      await tester.tap(
        find.descendant(of: menu, matching: find.text('publish')),
      );
      await tester.pumpAndSettle();
      expect(model.workflow!.name, 'publish');
      expect(model.canvas.levels, hasLength(1));
      expect(inHeader(find.text('publish')), findsOneWidget);
    });

    testWidgets('the workflow drawn chosen again draws its top level', (
      tester,
    ) async {
      final model = await pumpGraphScreen(
        tester,
        model: ownedModel(graph: twoWorkflows()),
      );
      model.open(publish);
      await tester.pump();

      await tester.tap(inHeader(find.byKey(GraphHeader.workflowKey)));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(PopupMenuItem<String>),
          matching: find.text('release'),
        ),
      );
      await tester.pumpAndSettle();
      expect(model.workflow!.name, 'release');
      expect(model.canvas.levels, hasLength(1));
    });
  });

  group('the Live badge', () {
    testWidgets('says the runs directory is watched', (tester) async {
      await pumpGraphScreen(tester);

      expect(inHeader(find.text('Live · watching runs/')), findsOneWidget);
    });

    testWidgets('says the graph file cannot be read, why in its tooltip', (
      tester,
    ) async {
      final model = await pumpGraphScreen(tester);
      graphFileOf(model).error = 'line 3, column 1: unexpected end';
      await tester.pump();

      expect(
        inHeader(find.text('File unreadable · watching runs/')),
        findsOneWidget,
      );
      expect(
        inHeader(find.byTooltip('line 3, column 1: unexpected end')),
        findsOneWidget,
      );
    });

    testWidgets('says the file is unavailable while it is gone', (
      tester,
    ) async {
      final model = await pumpGraphScreen(tester);
      graphFileOf(model).fileMissing = true;
      await tester.pump();

      expect(
        inHeader(find.text('File unavailable · watching runs/')),
        findsOneWidget,
      );

      graphFileOf(model).fileMissing = false;
      await tester.pump();
      expect(inHeader(find.text('Live · watching runs/')), findsOneWidget);
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
      ['/usr/bin/open', '-R', releaseFile],
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
      ['/usr/bin/open', '-t', releaseFile],
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
    expect(
      find.text('Could not reveal $graphFileName in Finder'),
      findsOneWidget,
    );

    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(
      find.text('Could not reveal $graphFileName in Finder'),
      findsNothing,
    );

    await tester.tap(inHeader(find.text('Open in editor')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      find.text('Could not open $graphFileName in an editor'),
      findsOneWidget,
    );
  });
}
