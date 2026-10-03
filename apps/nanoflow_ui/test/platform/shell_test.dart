import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_ui/platform/shell.dart';

void main() {
  group('opening a file', () {
    final runs = <List<String>>[];
    late int exitCode;
    late Shell shell;

    setUp(() {
      runs.clear();
      exitCode = 0;
      shell = Shell(
        run: (executable, arguments) async {
          runs.add([executable, ...arguments]);
          return ProcessResult(0, exitCode, '', '');
        },
      );
    });

    test('revealInFinder selects it in Finder', () async {
      expect(
        await shell.revealInFinder('/Users/me/review/nanoflow.graph.json'),
        isTrue,
      );
      expect(runs, [
        ['/usr/bin/open', '-R', '/Users/me/review/nanoflow.graph.json'],
      ]);
    });

    test('openInEditor opens it in the default text editor', () async {
      expect(
        await shell.openInEditor('/Users/me/review/nanoflow.graph.json'),
        isTrue,
      );
      expect(runs, [
        ['/usr/bin/open', '-t', '/Users/me/review/nanoflow.graph.json'],
      ]);
    });

    test('reports that open failed', () async {
      exitCode = 1;
      expect(await shell.revealInFinder('/Users/me/gone.json'), isFalse);
      expect(await shell.openInEditor('/Users/me/gone.json'), isFalse);
    });

    test('reports that open could not start', () async {
      final shell = Shell(
        run: (executable, arguments) async =>
            throw ProcessException(executable, arguments, 'not found', 2),
      );
      expect(await shell.revealInFinder('/Users/me/review.json'), isFalse);
      expect(await shell.openInEditor('/Users/me/review.json'), isFalse);
    });
  });

  testWidgets('copyToClipboard puts the text on the clipboard', (tester) async {
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
    await Shell().copyToClipboard('/Users/me/review/nanoflow.graph.json');
    expect(copied, [
      {'text': '/Users/me/review/nanoflow.graph.json'},
    ]);
  });
}
