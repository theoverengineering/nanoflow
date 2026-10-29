import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_ui/graph/logs/effect_details_pane.dart';
import 'package:nanoflow_ui/graph/logs/effect_list.dart';
import 'package:nanoflow_ui/graph/logs/file_footer.dart';
import 'package:nanoflow_ui/platform/shell.dart';
import 'package:nanoflow_ui/state/project_dir.dart';

import '../../state/support.dart';
import '../support.dart';
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

  Finder footer() => find.byType(FileFooter);
  Finder inFooter(Finder finder) =>
      find.descendant(of: footer(), matching: finder);

  Future<void> open(WidgetTester tester, EffectTab tab) async {
    await tester.tap(find.byKey(EffectDetailsPane.tabKey(tab)));
    await tester.pump();
  }

  testWidgets('shows the file of the open tab, cut from the left when too '
      'long, in full in a tooltip', (tester) async {
    await pumpReview(tester);

    final shown = textIn(tester, inFooter(find.byKey(FileFooter.pathKey)));
    expect(shown, startsWith('…'));
    expect(shown, endsWith('-notify-a1b2-notify-5/effect.log'));
    expect(notifyLogPath, endsWith(shown.substring(1)));
    expect(inFooter(find.byTooltip(notifyLogPath)), findsOneWidget);

    await tester.tap(find.byKey(EffectList.rowKey('a1b2-inspect-3')));
    await tester.pump();
    await open(tester, EffectTab.output);
    expect(
      textIn(tester, inFooter(find.byKey(FileFooter.pathKey))),
      endsWith('-a1b2-session/documents/report-2.json'),
    );
  });

  testWidgets("a short path is shown whole, from the graph's project", (
    tester,
  ) async {
    final files = reviewFiles()
      ..logPaths['a1b2-notify-5'] =
          '${projectDirOf(reviewFile)}/'
          'runs/notify.log';
    await pumpReview(tester, model: reviewModel(files: files));

    expect(
      textIn(tester, inFooter(find.byKey(FileFooter.pathKey))),
      'runs/notify.log',
    );
  });

  testWidgets('without a file, or a document, there is no footer', (
    tester,
  ) async {
    await pumpReview(tester, model: reviewModel(files: FakeFiles()));
    expect(footer(), findsNothing);

    await pumpReview(tester);
    await open(tester, EffectTab.output);
    expect(footer(), findsNothing);
  });

  testWidgets('Finder reveals the file, Editor opens it', (tester) async {
    final ran = <List<String>>[];
    await pumpReview(tester, shell: shellOpening(ran));

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
    ('Finder', 'Could not reveal effect.log in Finder'),
    ('Editor', 'Could not open effect.log in an editor'),
  ]) {
    testWidgets('says when $button fails', (tester) async {
      await pumpReview(tester, shell: shellOpening([], exitCode: 1));

      await tester.tap(inFooter(find.text(button)));
      await tester.pump();
      await tester.pump();
      expect(find.text(note), findsOneWidget);
    });
  }

  testWidgets('copies the path, and says so for a moment', (tester) async {
    final copied = <Object?>[];
    mockClipboard(tester, copied);
    await pumpReview(tester);

    await tester.tap(inFooter(find.byTooltip('Copy path')));
    await tester.pump();
    expect(copied, [
      {'text': notifyLogPath},
    ]);
    expect(inFooter(find.text('Copied')), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    expect(inFooter(find.text('Copied')), findsNothing);
    expect(inFooter(find.byTooltip('Copy path')), findsOneWidget);
  });

  testWidgets('says when copying fails', (tester) async {
    mockClipboard(tester, [], error: PlatformException(code: 'busy'));
    await pumpReview(tester);

    await tester.tap(inFooter(find.byTooltip('Copy path')));
    await tester.pump();
    await tester.pump();
    expect(find.text('Could not copy the path of effect.log'), findsOneWidget);
    expect(inFooter(find.text('Copied')), findsNothing);
  });
}
