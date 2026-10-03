import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_model/nanoflow_model.dart' hide Route;
import 'package:nanoflow_ui/graph/canvas/node_tile.dart';
import 'package:nanoflow_ui/graph/details/data_view.dart';
import 'package:nanoflow_ui/graph/details/input_column.dart';
import 'package:nanoflow_ui/graph/details/node_column.dart';
import 'package:nanoflow_ui/graph/details/output_column.dart';
import 'package:nanoflow_ui/graph/details/step_details_window.dart';
import 'package:nanoflow_ui/graph/logs/step_details_pane.dart';
import 'package:nanoflow_ui/platform/shell.dart';
import 'package:nanoflow_ui/state/json_data.dart';
import 'package:path/path.dart' as p;

import '../../state/support.dart';
import '../canvas/support.dart';
import '../logs/support.dart';
import '../support.dart';

void main() {
  Finder window() => find.byType(StepDetailsWindow);
  Finder inWindow(Finder finder) =>
      find.descendant(of: window(), matching: finder);
  Finder inColumn(Type column, Finder finder) =>
      find.descendant(of: find.byType(column), matching: finder);
  String textOf(WidgetTester tester, Type column) =>
      textIn(tester, find.byType(column));
  String topBar(WidgetTester tester) =>
      textIn(tester, find.byKey(StepDetailsWindow.topBarKey));

  /// Lets the window read its documents.
  Future<void> settleWindow(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> doubleClick(WidgetTester tester, String node) async {
    await tester.tap(find.byKey(NodeTile.tileKeyOf(node)));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(find.byKey(NodeTile.tileKeyOf(node)));
    await tester.pump(const Duration(milliseconds: 500));
    await settleWindow(tester);
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pump();
    await settleWindow(tester);
  }

  group('opens', () {
    testWidgets('from Open in Logs, on the selected step', (tester) async {
      await pumpGraphScreen(tester);
      expect(window(), findsNothing);

      await tap(tester, find.byKey(StepDetailsPane.openKey));

      expect(window(), findsOneWidget);
      expect(
        topBar(tester),
        'Back to canvas notify nodes/notify/run.sh Visit 1 of 1 run e5f6 '
        'running · 2m 14s',
      );
      expect(inWindow(find.byTooltip('e5f6-run')), findsOneWidget);
    });

    testWidgets('on a double click, at the node\'s last visit in the '
        'selected run', (tester) async {
      final model = await pumpGraphScreen(tester);

      await doubleClick(tester, 'inspect');

      expect(topBar(tester), contains('Visit 2 of 2 run k7f2 exit 0 · 4m 02s'));
      expect(model.selection.runId, 'e5f6-run');
      expect(model.selection.stepId, 'k7f2-inspect-5');
    });

    testWidgets('on a double click, at the node\'s latest visit in the '
        'session when the selected run has none', (tester) async {
      final model = await pumpGraphScreen(tester);

      await doubleClick(tester, 'publish');

      expect(topBar(tester), contains('Visit 1 of 1 run c3d4'));
      expect(model.selection.runId, 'c3d4-run');
      expect(model.selection.stepId, 'c3d4-publish-0');
    });

    testWidgets('on a node without visits with its description alone', (
      tester,
    ) async {
      final model = await pumpGraphScreen(tester);

      await doubleClick(tester, 'discard');

      expect(topBar(tester), 'Back to canvas discard nodes/discard/run.sh');
      expect(textOf(tester, InputColumn), 'INPUT');
      expect(textOf(tester, OutputColumn), 'OUTPUT');
      final node = textOf(tester, NodeColumn);
      expect(node, contains('COMMAND nodes/discard/run.sh'));
      expect(node, contains('IN #/Change { id, path }'));
      expect(node, isNot(contains('THIS STEP')));
      expect(model.selection.stepId, 'e5f6-notify-0');
    });
  });

  testWidgets('fits the smallest window, a long name cut', (tester) async {
    final graph = {
      ...reviewGraph,
      'nodes': {
        ...reviewGraph['nodes']! as Map<String, Object?>,
        'inspect': {
          ...(reviewGraph['nodes']! as Map<String, Object?>)['inspect']!
              as Map<String, Object?>,
          'command': 'nodes/inspect/${'very-long-directory/' * 6}run.sh',
        },
      },
    };
    final mockup = Mockup();
    // The window's least size: macos/Runner/MainFlutterWindow.swift.
    await pumpGraphScreen(
      tester,
      size: const Size(1100, 700),
      model: ownedModel(
        changes: changesOf([
          mockup.k7f2,
          mockup.c3d4,
          mockup.e5f6,
        ], graph: graph),
        outcomes: reviewOutcomes,
        files: mockupFiles(),
      ),
    );
    await doubleClick(tester, 'inspect');

    expect(tester.takeException(), isNull);
    expect(tester.getRect(window()), const Rect.fromLTWH(0, 0, 1100, 700));
    expect(topBar(tester), contains('Visit 2 of 2 run k7f2'));
  });

  testWidgets('opens on a node of Current graph with its description alone', (
    tester,
  ) async {
    final model = await pumpGraphScreen(tester);
    model.selection.showCurrentGraph();
    await tester.pump();

    await doubleClick(tester, 'inspect');

    expect(topBar(tester), 'Back to canvas inspect nodes/inspect/run.sh');
    expect(textOf(tester, NodeColumn), isNot(contains('THIS STEP')));
  });

  group('closes', () {
    for (final (how, close) in [
      (
        'Back to canvas',
        (WidgetTester tester) =>
            tester.tap(find.byKey(StepDetailsWindow.backKey)),
      ),
      (
        'the close button',
        (WidgetTester tester) =>
            tester.tap(find.byKey(StepDetailsWindow.closeKey)),
      ),
      (
        'Esc',
        (WidgetTester tester) => tester.sendKeyEvent(LogicalKeyboardKey.escape),
      ),
    ]) {
      testWidgets('with $how', (tester) async {
        await pumpGraphScreen(tester);
        await tap(tester, find.byKey(StepDetailsPane.openKey));
        expect(window(), findsOneWidget);

        await close(tester);
        await tester.pump();

        expect(window(), findsNothing);
      });
    }

    testWidgets('on a running run\'s newest step when the window showed its '
        'last: following goes on under the window', (tester) async {
      final mockup = Mockup();
      final more = StreamController<Change>();
      addTearDown(more.close);
      final model = await pumpGraphScreen(
        tester,
        model: ownedModel(
          changes: changesOf([mockup.k7f2, mockup.c3d4, mockup.e5f6]),
          more: more.stream,
          outcomes: reviewOutcomes,
          files: mockupFiles(),
        ),
      );
      await tap(tester, find.byKey(StepDetailsPane.openKey));

      final next = mockup.e5f6.step('notify', 700);
      more
        ..add(StepAdded(mockup.e5f6.steps.last))
        ..add(EventAdded(mockup.e5f6.events.last));
      await settle(tester);

      expect(
        topBar(tester),
        contains('notify nodes/notify/run.sh Visit 1 of 2'),
      );
      expect(model.selection.stepId, next);
      await tap(tester, find.byKey(StepDetailsWindow.closeKey));
      expect(model.selection.stepId, next);
    });

    testWidgets('leaving the canvas and Logs on the visit shown last', (
      tester,
    ) async {
      final model = await pumpGraphScreen(tester);
      await doubleClick(tester, 'inspect');
      await tap(tester, find.byKey(StepDetailsWindow.previousKey));

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(
        (model.selection.runId, model.selection.stepId),
        ('e5f6-run', 'k7f2-inspect-2'),
      );
      expect(
        textIn(tester, find.byKey(StepDetailsPane.headerKey)),
        startsWith('inspect'),
      );
    });
  });

  group('the visit switcher', () {
    testWidgets('goes through every visit to the node in the session, and '
        'selects each', (tester) async {
      final model = await pumpGraphScreen(tester);
      await doubleClick(tester, 'inspect');

      // The last visit has none after it.
      await tap(tester, find.byKey(StepDetailsWindow.nextKey));
      expect(topBar(tester), contains('Visit 2 of 2'));

      await tap(tester, find.byKey(StepDetailsWindow.previousKey));
      expect(topBar(tester), contains('Visit 1 of 2 run k7f2 exit 0 · 3m 12s'));
      expect(model.selection.stepId, 'k7f2-inspect-2');

      await tap(tester, find.byKey(StepDetailsWindow.previousKey));
      expect(topBar(tester), contains('Visit 1 of 2'));

      await tap(tester, find.byKey(StepDetailsWindow.nextKey));
      expect(topBar(tester), contains('Visit 2 of 2'));
      expect(model.selection.stepId, 'k7f2-inspect-5');
    });

    testWidgets('across runs, selecting the run of a visit the selected '
        'run does not show', (tester) async {
      final root = Journal('root-run', node: 'collect', startedAt: 0)
        ..step('collect', 0, end: 1, input: 'request', output: 'change')
        ..split(1);
      Journal child(String id, num at) =>
          Journal(id, parent: 'root-run', node: 'fix', startedAt: 1)
            ..step('fix', at, input: 'change');
      final model = ownedModel(
        changes: changesOf([root, child('aaaa-run', 6), child('bbbb-run', 5)]),
      );
      await pumpGraphScreen(tester, model: model);
      model.selectRun('aaaa-run');
      await tester.pump();

      await doubleClick(tester, 'fix');
      expect(topBar(tester), contains('Visit 2 of 2 run aaaa'));

      await tap(tester, find.byKey(StepDetailsWindow.previousKey));
      expect(topBar(tester), contains('Visit 1 of 2 run bbbb'));
      expect(
        (model.selection.runId, model.selection.stepId),
        ('bbbb-run', 'bbbb-fix-0'),
      );
    });
  });

  group('the input', () {
    testWidgets('comes from the step whose output it is; a click goes to '
        'that step', (tester) async {
      final model = await pumpGraphScreen(tester);
      await doubleClick(tester, 'inspect');
      expect(
        textOf(tester, InputColumn),
        startsWith('INPUT Schema JSON from fix · 14:08:54 #/Change'),
      );

      await tap(tester, find.byKey(InputColumn.fromKey));

      expect(
        topBar(tester),
        contains('fix nodes/fix/run.sh Visit 1 of 1 run k7f2'),
      );
      expect(model.selection.stepId, 'k7f2-fix-4');
    });

    testWidgets('of the first step of the run is the launch input', (
      tester,
    ) async {
      await pumpGraphScreen(tester);
      await doubleClick(tester, 'collect');
      expect(
        textOf(tester, InputColumn),
        startsWith('INPUT Schema JSON launch input #/Request'),
      );
    });

    testWidgets('shows the data as fields, or as JSON', (tester) async {
      await pumpGraphScreen(tester);
      await doubleClick(tester, 'inspect');
      expect(
        textOf(tester, InputColumn),
        contains('id string c4f1b0 path string src/engine/step.ts'),
      );

      await tap(tester, inColumn(InputColumn, find.text('JSON')));

      expect(
        textOf(tester, InputColumn),
        contains('{ "id": "c4f1b0", "path": "src/engine/step.ts" }'),
      );
    });

    testWidgets('is — with why when the node declares no in', (tester) async {
      const graph = <String, Object?>{
        'start': 'tick',
        'nodes': {
          'tick': {
            'command': 'date',
            'out': {'type': 'string'},
          },
        },
      };
      final run = Journal('tick-run', node: 'tick', startedAt: 0)
        ..step('tick', 0, end: 1, output: 'time')
        ..finish(1);
      final model = ownedModel(changes: changesOf([run], graph: graph));
      await pumpGraphScreen(tester, model: model);
      await doubleClick(tester, 'tick');

      expect(
        textOf(tester, InputColumn),
        'INPUT — This node declares no in: it gets no data',
      );
      expect(textOf(tester, NodeColumn), contains('IN — none'));
    });
  });

  group('the output', () {
    testWidgets('passes the node\'s out: its type and size, its data as JSON', (
      tester,
    ) async {
      await pumpGraphScreen(tester);
      await doubleClick(tester, 'inspect');
      final size = sizeText(byteSize(mockupDocuments['report-2']));
      expect(
        textOf(tester, OutputColumn),
        startsWith(
          'OUTPUT Output Log Schema JSON passes #/Report $size { "change": {',
        ),
      );
    });

    testWidgets('is — with why when the node declares no out, and Log shows '
        'the step\'s log', (tester) async {
      await pumpGraphScreen(tester);
      await tap(tester, find.byKey(StepDetailsPane.openKey));
      expect(
        textOf(tester, OutputColumn),
        'OUTPUT Output — Log — This node declares no out: what it prints '
        'goes to its log',
      );

      await tap(tester, find.byKey(OutputColumn.tabKey(OutputTab.log)));

      expect(
        textOf(tester, OutputColumn),
        contains('2 findings, 3 subscribers'),
      );
    });

    testWidgets('is not there yet while the step runs', (tester) async {
      final run = Journal('runs-run', node: 'collect', startedAt: 0)
        ..step('collect', 0, input: 'request');
      await pumpGraphScreen(
        tester,
        model: ownedModel(changes: changesOf([run])),
      );
      await doubleClick(tester, 'collect');
      expect(
        textOf(tester, OutputColumn),
        'OUTPUT Output Log Not yet: the step is still running',
      );
    });

    testWidgets('of a failed step is the run\'s error', (tester) async {
      final run = Journal('fail-run', node: 'collect', startedAt: 0);
      run.fail(
        run.step('collect', 0, end: 12, exit: 1, input: 'request'),
        12,
        'exited with code 1',
      );
      await pumpGraphScreen(
        tester,
        model: ownedModel(changes: changesOf([run])),
      );
      await doubleClick(tester, 'collect');
      expect(topBar(tester), endsWith('exit 1 · 12s'));
      expect(
        textOf(tester, OutputColumn),
        'OUTPUT Output Log Run failed: exited with code 1',
      );
    });

    testWidgets('of a fork is its outcome', (tester) async {
      await pumpGraphScreen(tester);
      await doubleClick(tester, 'verdict');
      expect(
        textOf(tester, OutputColumn),
        startsWith('OUTPUT Output Log Schema JSON outcome 10 B "accepted"'),
      );
      expect(
        textOf(tester, NodeColumn),
        contains('DECIDE nodes/verdict/run.sh'),
      );
      expect(
        textOf(tester, NodeColumn),
        contains('OUTCOMES accepted → publish notify returned → fix'),
      );
    });
  });

  group('the node column', () {
    testWidgets('describes the node and tells the facts of the step', (
      tester,
    ) async {
      await pumpGraphScreen(tester);
      await doubleClick(tester, 'inspect');
      expect(
        textIn(tester, find.byKey(NodeColumn.descriptionKey)),
        'COMMAND nodes/inspect/run.sh '
        "Runs through sh -c in the graph's directory. "
        'IN #/Change { id, path } OUT #/Report { change, findings[] } '
        'THEN → verdict '
        'THIS STEP Started 14:09:20.000 Finished 14:13:22.000 took 4m 02s '
        'Exit code 0 Starts 14:09:20 interrupted — engine stopped 14:09:51',
      );
      expect(
        textIn(tester, find.byKey(NodeColumn.pathKey)),
        allOf(startsWith('…'), endsWith(p.basename(inspectStepPath))),
      );
    });

    testWidgets('of a graph in code calls a node a function, declared at a '
        'place, which does not run through sh -c', (tester) async {
      const graph = <String, Object?>{
        'start': 'collect',
        'nodes': {
          'collect': {'command': 'graph.dart:12', 'then': 'pick'},
          'pick': {'decide': 'graph.dart:20', 'then': 'collect'},
        },
      };
      final run = Journal('code-run', node: 'collect', startedAt: 0)
        ..step('collect', 0, end: 1);
      await pumpGraphScreen(
        tester,
        model: ownedModel(changes: changesOf([run], graph: graph)),
      );

      await doubleClick(tester, 'collect');
      expect(
        textIn(tester, find.byKey(NodeColumn.descriptionKey)),
        startsWith('FUNCTION graph.dart:12 IN — none OUT — none THEN → pick '),
      );
      await tap(tester, find.text('Back to canvas'));

      await doubleClick(tester, 'pick');
      expect(
        textIn(tester, find.byKey(NodeColumn.descriptionKey)),
        startsWith('DECIDE FUNCTION graph.dart:20 IN — none OUTCOMES '),
      );
    });

    testWidgets('reveals the step\'s directory in Finder, and copies its '
        'path', (tester) async {
      final ran = <List<String>>[];
      await pumpGraphScreen(
        tester,
        shell: Shell(
          run: (executable, arguments) async {
            ran.add([executable, ...arguments]);
            return ProcessResult(0, 0, '', '');
          },
        ),
      );
      await doubleClick(tester, 'inspect');

      await tap(tester, inColumn(NodeColumn, find.text('Reveal in Finder')));
      expect(ran, [
        ['/usr/bin/open', '-R', inspectStepPath],
      ]);
      expect(
        inColumn(NodeColumn, find.byTooltip(inspectStepPath)),
        findsOneWidget,
      );

      final copied = <Object?>[];
      mockClipboard(tester, copied);
      await tap(tester, inColumn(NodeColumn, find.byTooltip('Copy path')));
      expect(copied, [
        {'text': inspectStepPath},
      ]);
    });
  });

  testWidgets('stops following a step\'s log when the window shows another '
      'visit, and when it closes', (tester) async {
    final files = mockupFiles();
    await pumpGraphScreen(tester, model: mockupModel(files: files));
    // Logs shows the selected step's input: only the window follows logs.
    await tap(tester, find.byKey(StepDetailsPane.tabKey(StepTab.input)));
    await doubleClick(tester, 'inspect');
    await tap(tester, find.byKey(OutputColumn.tabKey(OutputTab.log)));
    expect(files.followed, ['k7f2-inspect-5']);

    await tap(tester, find.byKey(StepDetailsWindow.previousKey));
    expect(files.followed, ['k7f2-inspect-2']);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(files.followed, isEmpty);
  });

  testWidgets('measures the output once, not at each tick of the clock', (
    tester,
  ) async {
    final report = _Counting(mockupDocuments['report-2']);
    final files = mockupFiles()..documents['report-2'] = report;
    await pumpGraphScreen(tester, model: mockupModel(files: files));
    await doubleClick(tester, 'inspect');
    final encoded = report.encoded;

    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 1));
    }

    expect(report.encoded, encoded);
  });

  testWidgets('the data views tell Schema from JSON', (tester) async {
    await pumpGraphScreen(tester);
    await doubleClick(tester, 'inspect');
    expect(inColumn(InputColumn, find.byType(SchemaView)), findsOneWidget);
    expect(inColumn(OutputColumn, find.byType(JsonView)), findsOneWidget);
  });
}

/// A document's value that counts how many times it is encoded as JSON.
final class _Counting {
  _Counting(this.json);

  final Object? json;
  int encoded = 0;

  Object? toJson() {
    encoded++;
    return json;
  }
}
