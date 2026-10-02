import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_ui/platform/shell.dart';

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('nanoflow_shell_test'));
  tearDown(() => tmp.deleteSync(recursive: true));

  /// An executable shell script in [tmp].
  String script(String name, String body) {
    final file = File('${tmp.path}/$name')
      ..writeAsStringSync('#!/bin/sh\n$body\n');
    Process.runSync('chmod', ['+x', file.path]);
    return file.path;
  }

  /// A login shell whose profile sets PATH to [path] and runs the `-c`
  /// command, refusing any other arguments.
  String loginShell(String path, {String profile = ''}) =>
      script('login-shell', '''
[ "\$#" = 3 ] && [ "\$1" = -l ] && [ "\$2" = -c ] || exit 64
$profile
PATH='$path'
eval "\$3"''');

  group('PATH', () {
    test('comes from the login shell', () async {
      final shell = Shell(
        environment: {
          'SHELL': loginShell('/opt/homebrew/bin:/usr/bin'),
          'PATH': '/usr/bin',
        },
      );
      expect(await shell.path(), '/opt/homebrew/bin:/usr/bin');
    });

    test('skips what the profile prints before it', () async {
      final shell = Shell(
        environment: {
          'SHELL': loginShell('/login/bin', profile: 'echo Welcome; echo back'),
          'PATH': '/usr/bin',
        },
      );
      expect(await shell.path(), '/login/bin');
    });

    test('is resolved once', () async {
      final calls = File('${tmp.path}/calls');
      final shell = Shell(
        environment: {
          'SHELL': loginShell(
            '/login/bin',
            profile: 'echo call >> ${calls.path}',
          ),
          'PATH': '/usr/bin',
        },
      );
      expect(await shell.path(), '/login/bin');
      expect(await shell.path(), '/login/bin');
      expect(calls.readAsLinesSync(), ['call']);
    });

    final failing = <String, String Function()>{
      'the login shell fails': () => script('sh', 'exit 1'),
      'the login shell prints nothing': () => script('sh', 'exit 0'),
      'the login shell does not exist': () => '${tmp.path}/no-such-shell',
      'SHELL is empty': () => '',
    };
    for (final MapEntry(key: reason, value: shellPath) in failing.entries) {
      test('is the process PATH when $reason', () async {
        final shell = Shell(
          environment: {'SHELL': shellPath(), 'PATH': '/usr/bin:/bin'},
        );
        expect(await shell.path(), '/usr/bin:/bin');
      });
    }

    test('is the process PATH when SHELL is not set', () async {
      expect(
        await Shell(environment: {'PATH': '/usr/bin:/bin'}).path(),
        '/usr/bin:/bin',
      );
    });

    test('is the process PATH when the login shell hangs', () async {
      final shell = Shell(
        environment: {
          'SHELL': script('sh', 'exec sleep 5'),
          'PATH': '/usr/bin:/bin',
        },
        timeout: const Duration(milliseconds: 200),
      );
      expect(await shell.path(), '/usr/bin:/bin');
    });
  });

  test('findExecutable looks through the resolved PATH in order', () async {
    final first = Directory('${tmp.path}/first')..createSync();
    final second = Directory('${tmp.path}/second')..createSync();
    File('${first.path}/nanoflow').writeAsStringSync('not executable');
    final nanoflow = File('${second.path}/nanoflow')
      ..writeAsStringSync('#!/bin/sh\n');
    Process.runSync('chmod', ['+x', nanoflow.path]);
    Directory('${first.path}/nanoflow-yaml').createSync();
    final shell = Shell(
      environment: {
        'SHELL': loginShell('${first.path}::${second.path}'),
        'PATH': '/usr/bin',
      },
    );
    expect(await shell.findExecutable('nanoflow'), nanoflow.path);
    expect(await shell.findExecutable('nanoflow-yaml'), isNull);
  });

  group('opening a file', () {
    final runs = <List<String>>[];
    late Shell shell;

    setUp(() {
      runs.clear();
      shell = Shell(
        environment: const {},
        run: (executable, arguments) async {
          runs.add([executable, ...arguments]);
          return ProcessResult(0, 0, '', '');
        },
      );
    });

    test('revealInFinder selects it in Finder', () async {
      await shell.revealInFinder('/Users/me/review.yaml');
      expect(runs, [
        ['/usr/bin/open', '-R', '/Users/me/review.yaml'],
      ]);
    });

    test('openInEditor opens it in the default text editor', () async {
      await shell.openInEditor('/Users/me/review.yaml');
      expect(runs, [
        ['/usr/bin/open', '-t', '/Users/me/review.yaml'],
      ]);
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
    await Shell(environment: const {}).copyToClipboard('/Users/me/review.yaml');
    expect(copied, [
      {'text': '/Users/me/review.yaml'},
    ]);
  });
}
