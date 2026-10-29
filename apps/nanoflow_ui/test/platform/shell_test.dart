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
        await shell.revealInFinder('/Users/me/review/lib/review.graph.json'),
        isTrue,
      );
      expect(runs, [
        ['/usr/bin/open', '-R', '/Users/me/review/lib/review.graph.json'],
      ]);
    });

    test('openInEditor opens it in the default text editor', () async {
      expect(
        await shell.openInEditor('/Users/me/review/lib/review.graph.json'),
        isTrue,
      );
      expect(runs, [
        ['/usr/bin/open', '-t', '/Users/me/review/lib/review.graph.json'],
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

  group('opening a place in the code', () {
    final runs = <List<String>>[];
    late String app;
    late int exitCode;
    late Shell shell;
    late String file;

    setUp(() {
      runs.clear();
      app = 'com.todesktop.230313mzl4w4u92\n';
      exitCode = 0;
      shell = Shell(
        run: (executable, arguments) async {
          runs.add([executable, ...arguments]);
          return executable == '/usr/bin/osascript'
              ? ProcessResult(0, 0, app, '')
              : ProcessResult(0, exitCode, '', '');
        },
      );
      final root = Directory.systemTemp.createTempSync('nanoflow_shell');
      addTearDown(() => root.deleteSync(recursive: true));
      file = '${root.path}/review.dart';
      File(file).writeAsStringSync('// review\n');
    });

    /// What the shell ran to open the file, after asking for its app.
    List<List<String>> opened() {
      expect(runs.first.take(4), [
        '/usr/bin/osascript',
        '-l',
        'JavaScript',
        '-e',
      ]);
      expect(runs.first.last, file);
      return runs.skip(1).toList();
    }

    String link(String scheme) =>
        Uri(scheme: scheme, host: 'file', path: '$file:49').toString();

    test('opens it at its line in the editor that opens the file', () async {
      expect(await shell.openAtLine(file, 49), isTrue);
      expect(opened(), [
        ['/usr/bin/open', link('cursor')],
      ]);
      expect(link('cursor'), endsWith('/review.dart:49'));
      expect(link('cursor'), startsWith('cursor://file/'));
    });

    test('tells each editor it knows the line by its link', () async {
      for (final MapEntry(key: bundle, value: scheme)
          in Shell.lineSchemes.entries) {
        runs.clear();
        app = bundle;
        expect(await shell.openAtLine(file, 49), isTrue);
        expect(opened(), [
          ['/usr/bin/open', link(scheme)],
        ], reason: bundle);
      }
      expect(Shell.lineSchemes.values, containsAll(['vscode', 'zed']));
    });

    test('encodes a path with spaces in the link', () async {
      final spaced = '${File(file).parent.path}/my review.dart';
      File(spaced).writeAsStringSync('');
      expect(await shell.openAtLine(spaced, 3), isTrue);
      expect(runs.last.last, contains('my%20review.dart:3'));
    });

    test('opens it at its top in another app', () async {
      app = 'com.apple.dt.Xcode';
      expect(await shell.openAtLine(file, 49), isTrue);
      expect(opened(), [
        ['/usr/bin/open', file],
      ]);
    });

    test('opens it in the default text editor without an app', () async {
      app = '\n';
      expect(await shell.openAtLine(file, 49), isTrue);
      expect(opened(), [
        ['/usr/bin/open', '-t', file],
      ]);
    });

    test(
      'opens it in the default text editor when the app is not told',
      () async {
        final shell = Shell(
          run: (executable, arguments) async {
            runs.add([executable, ...arguments]);
            if (executable == '/usr/bin/osascript') {
              throw ProcessException(executable, arguments, 'not found', 2);
            }
            return ProcessResult(0, 0, '', '');
          },
        );
        expect(await shell.openAtLine(file, 49), isTrue);
        expect(runs.last, ['/usr/bin/open', '-t', file]);
      },
    );

    test('reports a file that is not there, opening nothing', () async {
      expect(await shell.openAtLine('$file.gone', 49), isFalse);
      expect(runs, isEmpty);
    });

    test('reports that open failed', () async {
      exitCode = 1;
      expect(await shell.openAtLine(file, 49), isFalse);
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
    await Shell().copyToClipboard('/Users/me/review/lib/review.graph.json');
    expect(copied, [
      {'text': '/Users/me/review/lib/review.graph.json'},
    ]);
  });
}
