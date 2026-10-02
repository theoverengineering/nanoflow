import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_ui/graph/logs/file_footer.dart';
import 'package:nanoflow_ui/graph/logs/step_details_pane.dart';
import 'package:nanoflow_ui/platform/shell.dart';

import '../../state/support.dart';
import '../support.dart';
import 'support.dart';

void main() {
  /// A shell whose `open` exits with [exitCode]; what it was asked to run
  /// goes to [ran].
  Shell shellOpening(List<List<String>> ran, {int exitCode = 0}) => Shell(
    environment: const {},
    run: (executable, arguments) async {
      ran.add([executable, ...arguments]);
      return ProcessResult(0, exitCode, '', '');
    },
  );

  Finder footer() => find.byType(FileFooter);
  Finder inFooter(Finder finder) =>
      find.descendant(of: footer(), matching: finder);

  Future<void> open(WidgetTester tester, StepTab tab) async {
    await tester.tap(find.byKey(StepDetailsPane.tabKey(tab)));
    await tester.pump();
  }

  testWidgets('shows the file of the open tab, cut from the left when too '
      'long, in full in a tooltip', (tester) async {
    await pumpGraphScreen(tester);

    final shown = textIn(tester, inFooter(find.byKey(FileFooter.pathKey)));
    expect(shown, startsWith('…'));
    expect(shown, endsWith('-notify-e5f6-notify-0/command.log'));
    expect(notifyLogPath, endsWith(shown.substring(1)));
    expect(inFooter(find.byTooltip(notifyLogPath)), findsOneWidget);

    await open(tester, StepTab.input);
    expect(
      textIn(tester, inFooter(find.byKey(FileFooter.pathKey))),
      endsWith('-a1b2-session/documents/report-2.json'),
    );
  });

  testWidgets('a short path is shown whole, from the graph\'s directory', (
    tester,
  ) async {
    final files = mockupFiles()
      ..logPaths['e5f6-notify-0'] =
          '${File(reviewFile).parent.path}/'
          'runs/notify.log';
    await pumpGraphScreen(tester, model: mockupModel(files: files));

    expect(
      textIn(tester, inFooter(find.byKey(FileFooter.pathKey))),
      'runs/notify.log',
    );
  });

  testWidgets('without a file, or a document, there is no footer', (
    tester,
  ) async {
    await pumpGraphScreen(tester, model: mockupModel(files: FakeFiles()));
    expect(footer(), findsNothing);

    await pumpGraphScreen(tester);
    await open(tester, StepTab.output);
    expect(footer(), findsNothing);
  });

  testWidgets('Finder reveals the file, Editor opens it', (tester) async {
    final ran = <List<String>>[];
    await pumpGraphScreen(tester, shell: shellOpening(ran));

    await tester.tap(inFooter(find.text('Finder')));
    await tester.pump();
    await tester.tap(inFooter(find.text('Editor')));
    await tester.pump();
    expect(ran, [
      ['/usr/bin/open', '-R', notifyLogPath],
      ['/usr/bin/open', '-t', notifyLogPath],
    ]);
  });

  for (final (button, note) in [
    ('Finder', 'Could not reveal command.log in Finder'),
    ('Editor', 'Could not open command.log in an editor'),
  ]) {
    testWidgets('says when $button fails', (tester) async {
      await pumpGraphScreen(tester, shell: shellOpening([], exitCode: 1));

      await tester.tap(inFooter(find.text(button)));
      await tester.pump();
      await tester.pump();
      expect(find.text(note), findsOneWidget);
    });
  }

  testWidgets('copies the path', (tester) async {
    final copied = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') copied.add(call.arguments);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await pumpGraphScreen(tester);

    await tester.tap(inFooter(find.byTooltip('Copy path')));
    await tester.pump();
    expect(copied, [
      {'text': notifyLogPath},
    ]);
  });
}
