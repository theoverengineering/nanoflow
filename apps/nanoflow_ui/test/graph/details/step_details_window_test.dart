import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart' show Text;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_ui/graph/canvas/node_tile.dart';
import 'package:nanoflow_ui/graph/details/data_view.dart';
import 'package:nanoflow_ui/graph/details/node_column.dart';
import 'package:nanoflow_ui/graph/details/output_column.dart';
import 'package:nanoflow_ui/graph/details/step_details_window.dart';
import 'package:nanoflow_ui/graph/logs/step_details_pane.dart';
import 'package:nanoflow_ui/platform/shell.dart';
import 'package:nanoflow_ui/state/graph_model.dart';
import 'package:nanoflow_ui/theme.dart';
import 'package:nanoflow_ui/widgets/icons.dart';
import 'package:nanoflow_ui/widgets/spinner.dart';
import 'package:path/path.dart' as p;

import '../canvas/support.dart';
import '../logs/support.dart';
import '../support.dart';

void main() {
  Finder window() => find.byType(StepDetailsWindow);
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

  /// A double click on the review node [id]: 1 collect, 3 discard, 4
  /// inspect, 6 publish, 7 notify, 8 fix.
  Future<void> doubleClick(WidgetTester tester, String id) async {
    await tester.tap(find.byKey(NodeTile.tileKeyOf(id)));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(find.byKey(NodeTile.tileKeyOf(id)));
    await tester.pump(const Duration(milliseconds: 500));
    await settleWindow(tester);
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pump();
    await settleWindow(tester);
  }

  /// The review session with a failed step on inspect after it.
  GraphModel failedModel() {
    final session = reviewSession()
      ..step(
        'inspect',
        700,
        end: 701,
        failed: true,
        place: 'lib/review.dart:55',
      );
    return ownedModel(
      graph: graphFileNamed('review'),
      file: reviewFile,
      changes: session.changes,
      documents: reviewDocuments,
      files: reviewFiles(),
    );
  }

  group('opens', () {
    testWidgets('from Open in Logs, on the selected step', (tester) async {
      await pumpReview(tester);
      expect(window(), findsNothing);

      await tap(tester, find.byKey(StepDetailsPane.openKey));

      expect(window(), findsOneWidget);
      expect(
        topBar(tester),
        'Back to canvas notify lib/review.dart:59 Visit 1 of 1 '
        'running · 2m 14s',
      );
    });

    testWidgets("on a double click, at the node's last step", (tester) async {
      final model = await pumpReview(tester);

      await doubleClick(tester, '4');

      expect(
        topBar(tester),
        contains('inspect lib/review.dart:55 Visit 2 of 2 finished · 4m 02s'),
      );
      expect(model.selection.stepId, 'a1b2-inspect-3');
    });

    testWidgets('on a node without steps with its name and place alone', (
      tester,
    ) async {
      final model = await pumpReview(tester);

      await doubleClick(tester, '3');

      expect(topBar(tester), 'Back to canvas discard lib/review.dart:51');
      expect(textOf(tester, OutputColumn), 'OUTPUT');
      final step = textOf(tester, NodeColumn);
      expect(step, contains('PLACE IN CODE lib/review.dart:51'));
      expect(step, isNot(contains('THIS STEP')));
      expect(model.selection.stepId, 'a1b2-notify-5');
    });

    testWidgets('on a node of Current graph with its name and place alone', (
      tester,
    ) async {
      final model = await pumpReview(tester);
      model.selection.showCurrentGraph();
      await tester.pump();

      await doubleClick(tester, '4');

      expect(topBar(tester), 'Back to canvas inspect lib/review.dart:55');
      expect(textOf(tester, NodeColumn), isNot(contains('THIS STEP')));
    });
  });

  testWidgets('fits the smallest window', (tester) async {
    // The window's least size: macos/Runner/MainFlutterWindow.swift.
    await pumpReview(tester, size: const Size(1100, 700));
    await doubleClick(tester, '4');

    expect(tester.takeException(), isNull);
    expect(tester.getRect(window()), const Rect.fromLTWH(0, 0, 1100, 700));
    expect(topBar(tester), contains('Visit 2 of 2'));
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
        await pumpReview(tester);
        await tap(tester, find.byKey(StepDetailsPane.openKey));
        expect(window(), findsOneWidget);

        await close(tester);
        await tester.pump();

        expect(window(), findsNothing);
      });
    }

    testWidgets("on a running session's newest step when the window showed "
        'its last: following goes on under the window', (tester) async {
      final more = StreamController<Change>();
      addTearDown(more.close);
      final model = await pumpReview(
        tester,
        model: ownedModel(
          graph: graphFileNamed('review'),
          file: reviewFile,
          changes: reviewSession().changes,
          more: more.stream,
          documents: reviewDocuments,
          files: reviewFiles(),
        ),
      );
      await tap(tester, find.byKey(StepDetailsPane.openKey));

      final session = reviewSession();
      final next = session.step('notify', 700, place: 'lib/review.dart:59');
      more
        ..add(StepAdded(session.steps.last))
        ..add(EventAdded(sessionId: session.id, event: session.events.last));
      await settle(tester);

      expect(
        topBar(tester),
        contains('notify lib/review.dart:59 Visit 1 of 2'),
      );
      expect(model.selection.stepId, next);
      await tap(tester, find.byKey(StepDetailsWindow.closeKey));
      expect(model.selection.stepId, next);
    });

    testWidgets('leaving the canvas and Logs on the step shown last', (
      tester,
    ) async {
      final model = await pumpReview(tester);
      await doubleClick(tester, '4');
      await tap(tester, find.byKey(StepDetailsWindow.previousKey));

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(model.selection.stepId, 'a1b2-inspect-1');
      expect(
        textIn(tester, find.byKey(StepDetailsPane.headerKey)),
        startsWith('inspect'),
      );
    });
  });

  testWidgets('the visit switcher goes through every step on the node, and '
      'selects the one shown', (tester) async {
    final model = await pumpReview(tester);
    await doubleClick(tester, '4');

    await tap(tester, find.byKey(StepDetailsWindow.previousKey));
    expect(topBar(tester), contains('Visit 1 of 2 finished · 3m 12s'));
    expect(model.selection.stepId, 'a1b2-inspect-1');
    // No visit before the first.
    await tap(tester, find.byKey(StepDetailsWindow.previousKey));
    expect(topBar(tester), contains('Visit 1 of 2'));

    await tap(tester, find.byKey(StepDetailsWindow.nextKey));
    expect(topBar(tester), contains('Visit 2 of 2'));
    expect(model.selection.stepId, 'a1b2-inspect-3');
  });

  group('the output', () {
    testWidgets('is the value the step returned, with its size, as JSON', (
      tester,
    ) async {
      await pumpReview(tester);
      await doubleClick(tester, '4');

      final output = textOf(tester, OutputColumn);
      expect(output, startsWith('OUTPUT Output Log Schema JSON returned'));
      expect(output, contains('"path": "lib/parse_config.dart"'));
      expect(inColumn(OutputColumn, find.byType(JsonView)), findsOneWidget);
    });

    testWidgets('is not there yet while the step runs', (tester) async {
      await pumpReview(tester);
      await doubleClick(tester, '7');

      expect(
        inColumn(OutputColumn, find.text('Not yet: the step is still running')),
        findsOneWidget,
      );
    });

    testWidgets('of a failed step is its error, with the stack', (
      tester,
    ) async {
      await pumpReview(tester, model: failedModel());
      await doubleClick(tester, '4');

      expect(topBar(tester), contains('Visit 3 of 3 failed · 1s'));
      expect(
        inColumn(OutputColumn, find.text('Failed: StateError: inspect failed')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(OutputColumn.stackKey),
          matching: find.text('#0 main'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('Log shows the step\'s log', (tester) async {
      await pumpReview(tester);
      await doubleClick(tester, '7');
      await tap(tester, find.byKey(OutputColumn.tabKey(OutputTab.log)));

      expect(
        inColumn(OutputColumn, find.text('2 findings, 3 subscribers')),
        findsOneWidget,
      );
    });
  });

  testWidgets('on a step that was running when the process of its session '
      'went: interrupted, nothing turning, its start interrupted, no output '
      'yet (owner spec §6)', (tester) async {
    await pumpReview(
      tester,
      model: ownedModel(
        graph: graphFileNamed('review'),
        file: reviewFile,
        changes: (reviewSession()..processGone()).changes,
        documents: reviewDocuments,
        files: reviewFiles(),
      ),
    );
    await doubleClick(tester, '7');

    // Killed in the middle of notify: when it would have ended is not
    // known.
    expect(topBar(tester), endsWith('Visit 1 of 1 interrupted'));
    expect(
      find.descendant(of: window(), matching: find.byType(Spinner)),
      findsNothing,
    );
    expect(
      find.descendant(of: window(), matching: find.byType(PauseIcon)),
      findsOneWidget,
    );
    expect(
      textIn(tester, find.byKey(NodeColumn.descriptionKey)),
      endsWith('Finished — Starts 14:13:23 interrupted — the process stopped'),
    );
    // The start says so as docs/design/step-details.html has it: amber.
    expect(
      tester
          .widget<Text>(find.text('interrupted — the process stopped'))
          .style!
          .color,
      AppColors.noteText,
    );
    expect(
      inColumn(
        OutputColumn,
        find.text('Not yet: the step was interrupted — the process stopped'),
      ),
      findsOneWidget,
    );
  });

  group('the step column', () {
    testWidgets('tells the place in the code and the facts of the step', (
      tester,
    ) async {
      await pumpReview(tester);
      await doubleClick(tester, '4');
      expect(
        textIn(tester, find.byKey(NodeColumn.descriptionKey)),
        'PLACE IN CODE lib/review.dart:55 '
        'THIS STEP Started 14:09:20.000 Finished 14:13:22.000 took 4m 02s '
        'Starts 14:09:20 interrupted — the process stopped 14:11:51',
      );
      expect(
        textIn(tester, find.byKey(NodeColumn.pathKey)),
        allOf(startsWith('…'), endsWith(p.basename(inspectStepPath))),
      );
    });

    testWidgets('copies the place, to go to it in an editor', (tester) async {
      await pumpReview(tester);
      await doubleClick(tester, '4');

      final copied = <Object?>[];
      mockClipboard(tester, copied);
      await tap(tester, find.byKey(NodeColumn.copyPlaceKey));
      expect(copied, [
        {'text': 'lib/review.dart:55'},
      ]);
    });

    testWidgets('a failed start says so', (tester) async {
      await pumpReview(tester, model: failedModel());
      await doubleClick(tester, '4');
      expect(
        textIn(tester, find.byKey(NodeColumn.descriptionKey)),
        endsWith('Starts 14:14:51 failed'),
      );
    });

    testWidgets("reveals the step's directory in Finder, and copies its "
        'path', (tester) async {
      final ran = <List<String>>[];
      await pumpReview(
        tester,
        shell: Shell(
          run: (executable, arguments) async {
            ran.add([executable, ...arguments]);
            return ProcessResult(0, 0, '', '');
          },
        ),
      );
      await doubleClick(tester, '4');

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

  testWidgets("stops following a step's log when the window shows another "
      'visit, and when it closes', (tester) async {
    final files = reviewFiles();
    await pumpReview(tester, model: reviewModel(files: files));
    // Logs shows the selected step's output: only the window follows logs.
    await tap(tester, find.byKey(StepDetailsPane.tabKey(StepTab.output)));
    await doubleClick(tester, '4');
    await tap(tester, find.byKey(OutputColumn.tabKey(OutputTab.log)));
    expect(files.followed, ['a1b2-inspect-3']);

    await tap(tester, find.byKey(StepDetailsWindow.previousKey));
    expect(files.followed, ['a1b2-inspect-1']);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(files.followed, isEmpty);
  });

  testWidgets('measures the output once, not at each tick of the clock', (
    tester,
  ) async {
    final report = _Counting(reviewDocuments['report-2']);
    final files = reviewFiles()..documents['report-2'] = report;
    await pumpReview(tester, model: reviewModel(files: files));
    await doubleClick(tester, '4');
    final encoded = report.encoded;

    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 1));
    }

    expect(report.encoded, encoded);
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
