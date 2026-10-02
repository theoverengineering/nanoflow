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

  /// A login shell like zsh: `-l -c` reads the profile, which sets PATH to
  /// [path]; `-i -l -c` also reads the rc file, which adds [rc] in front.
  /// [interactive] false refuses `-i`. Any other arguments are refused too.
  String loginShell(
    String path, {
    String profile = '',
    String rc = '',
    bool interactive = true,
  }) => script('login-shell', '''
if [ "\$1" = -i ]; then
  ${interactive ? 'interactive=yes' : 'exit 64'}
  shift
fi
[ "\$#" = 3 ] && [ "\$1" = -l ] && [ "\$2" = -c ] || exit 64
$profile
PATH='$path'
if [ "\$interactive" = yes ] && [ -n '$rc' ]; then PATH='$rc':"\$PATH"; fi
eval "\$3"''');

  group('PATH', () {
    test('comes from the interactive login shell, which reads the rc file '
        'too', () async {
      final shell = Shell(
        environment: {
          'SHELL': loginShell(
            '/opt/homebrew/bin:/usr/bin',
            rc: '/Users/me/.pub-cache/bin',
          ),
          'PATH': '/usr/bin',
        },
      );
      expect(
        await shell.path(),
        '/Users/me/.pub-cache/bin:/opt/homebrew/bin:/usr/bin',
      );
    });

    test(
      'comes from a login shell that is not interactive when -i fails',
      () async {
        final shell = Shell(
          environment: {
            'SHELL': loginShell(
              '/opt/homebrew/bin:/usr/bin',
              interactive: false,
            ),
            'PATH': '/usr/bin',
          },
        );
        expect(await shell.path(), '/opt/homebrew/bin:/usr/bin');
      },
    );

    test('skips what the profile prints before and after it', () async {
      final shell = Shell(
        environment: {
          'SHELL': loginShell(
            '/login/bin',
            profile: "echo Welcome; printf 'no newline'; trap 'echo bye' EXIT",
          ),
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
      'the login shell prints an empty PATH': () => loginShell(''),
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
          'SHELL': script('sh', 'exec sleep 2'),
          'PATH': '/usr/bin:/bin',
        },
        timeout: const Duration(milliseconds: 200),
      );
      expect(await shell.path(), '/usr/bin:/bin');
    });

    test(
      'does not wait for a program the profile leaves holding the output',
      () async {
        final shell = Shell(
          environment: {
            'SHELL': loginShell('/login/bin', profile: 'sleep 3 &'),
            'PATH': '/usr/bin',
          },
        );
        final watch = Stopwatch()..start();
        expect(await shell.path(), '/login/bin');
        expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
      },
    );

    test('gives up on the output after the timeout when a program the '
        'profile leaves holds it', () async {
      final shell = Shell(
        environment: {
          'SHELL': script('sh', 'sleep 3 & exit 0'),
          'PATH': '/usr/bin:/bin',
        },
        timeout: const Duration(milliseconds: 200),
      );
      final watch = Stopwatch()..start();
      expect(await shell.path(), '/usr/bin:/bin');
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
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
    late int exitCode;
    late Shell shell;

    setUp(() {
      runs.clear();
      exitCode = 0;
      shell = Shell(
        environment: const {},
        run: (executable, arguments) async {
          runs.add([executable, ...arguments]);
          return ProcessResult(0, exitCode, '', '');
        },
      );
    });

    test('revealInFinder selects it in Finder', () async {
      expect(await shell.revealInFinder('/Users/me/review.yaml'), isTrue);
      expect(runs, [
        ['/usr/bin/open', '-R', '/Users/me/review.yaml'],
      ]);
    });

    test('openInEditor opens it in the default text editor', () async {
      expect(await shell.openInEditor('/Users/me/review.yaml'), isTrue);
      expect(runs, [
        ['/usr/bin/open', '-t', '/Users/me/review.yaml'],
      ]);
    });

    test('reports that open failed', () async {
      exitCode = 1;
      expect(await shell.revealInFinder('/Users/me/gone.yaml'), isFalse);
      expect(await shell.openInEditor('/Users/me/gone.yaml'), isFalse);
    });

    test('reports that open could not start', () async {
      final shell = Shell(
        environment: const {},
        run: (executable, arguments) async =>
            throw ProcessException(executable, arguments, 'not found', 2),
      );
      expect(await shell.revealInFinder('/Users/me/review.yaml'), isFalse);
      expect(await shell.openInEditor('/Users/me/review.yaml'), isFalse);
    });
  });

  group('start', () {
    test('starts a program with the resolved PATH', () async {
      final started = <Object?>[];
      final shell = Shell(
        environment: {'PATH': '/login/bin'},
        start: (executable, arguments, {workingDirectory, environment}) {
          started.addAll([
            executable,
            arguments.skip(2).toList(),
            workingDirectory,
            environment,
          ]);
          return Process.start('/bin/echo', const []);
        },
      );
      final process = await shell.start('/opt/bin/nanoflow-yaml', [
        'review.yaml',
        '--graph',
        '--watch',
      ], workingDirectory: '/Users/me/review');
      await process.exitCode;
      expect(started, [
        '/bin/sh',
        ['sh', '/opt/bin/nanoflow-yaml', 'review.yaml', '--graph', '--watch'],
        '/Users/me/review',
        {'PATH': '/login/bin'},
      ]);
    });

    test('gives the program its stdin, its output and its exit code', () async {
      final shell = Shell(environment: {'PATH': '/usr/bin:/bin'});
      final process = await shell.start('/bin/sh', [
        '-c',
        r'read line; printf "%s|%s" "$line" "$PATH"; echo oops >&2; exit 3',
      ]);
      process.stdin.writeln('hello');
      await process.stdin.close();
      expect(
        await process.stdout.transform(const SystemEncoding().decoder).join(),
        'hello|/usr/bin:/bin',
      );
      expect(
        await process.stderr.transform(const SystemEncoding().decoder).join(),
        'oops\n',
      );
      expect(await process.exitCode, 3);
    });

    test('kill stops the program with every process it started', () async {
      final pids = File('${tmp.path}/pids');
      final shell = Shell(environment: {'PATH': '/usr/bin:/bin'});
      final process = await shell.start(
        script('watcher', 'sleep 3 & echo \$! > ${pids.path}; wait'),
        const [],
      );
      while (!pids.existsSync() || pids.readAsStringSync().isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      final child = pids.readAsStringSync().trim();
      process.kill();
      expect(await process.exitCode, isNot(0));
      final deadline = DateTime.now().add(const Duration(seconds: 2));
      while (Process.runSync('kill', ['-0', child]).exitCode == 0) {
        if (DateTime.now().isAfter(deadline)) fail('$child still runs');
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
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
