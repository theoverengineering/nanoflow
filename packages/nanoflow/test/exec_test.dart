import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:nanoflow/nanoflow.dart';
import 'package:nanoflow/src/exec.dart' show inGroupScript;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A stand-in for the process stderr that keeps what is written to it.
final class Captured implements Stdout {
  final bytes = <int>[];
  final _added = StreamController<void>.broadcast();

  String get text => utf8.decode(bytes);

  @override
  void add(List<int> data) {
    bytes.addAll(data);
    _added.add(null);
  }

  /// Waits until [text] contains [part].
  Future<void> contains(String part) async {
    while (!text.contains(part)) {
      await _added.stream.first;
    }
  }

  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Runs [body] with the process stderr replaced by [stderr].
Future<T> withStderr<T>(Captured stderr, Future<T> Function() body) =>
    IOOverrides.runZoned(body, stderr: () => stderr);

/// Starts [executable] with [arguments] without a controlling terminal, as a
/// daemon or an app started from the Dock runs: a shell like dash then turns
/// job control off. Gives what it prints on stdout once it has exited; it is
/// killed after the test if its stdout has not ended by then.
Future<String> withoutTerminal(
  String executable,
  List<String> arguments, {
  String stdin = '',
}) async {
  final process = await Process.start(
    executable,
    arguments,
    mode: ProcessStartMode.detachedWithStdio,
  );
  // A detached process tells no exit code, and once it has exited its pid
  // may be another process's: only one whose stdout is open is killed.
  var ended = false;
  addTearDown(() {
    if (!ended) process.kill(ProcessSignal.sigkill);
  });
  process.stdin.write(stdin);
  await process.stdin.close();
  process.stderr.drain<void>().ignore();
  final out = await utf8.decodeStream(process.stdout);
  ended = true;
  return out;
}

/// Why a test that needs dash is skipped, or `null` when there is one.
final String? noDash = File('/bin/dash').existsSync() ? null : 'no /bin/dash';

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('nanoflow_exec_'));
  tearDown(() => temp.deleteSync(recursive: true));

  test('returns what the program printed on stdout', () async {
    expect(await exec('/bin/sh', ['-c', 'echo one; echo two']), 'one\ntwo\n');
  });

  test('finds the program on PATH', () async {
    expect(await exec('basename', ['/dir/file name']), 'file name\n');
  });

  test('runs the program, not a shell builtin of the same name', () async {
    // The builtin echo of /bin/sh prints `-n hi`.
    expect(await exec('echo', ['-n', 'hi']), 'hi');
  });

  test('ends a program whose reader is gone, as a shell does', () async {
    // The Dart VM ignores SIGPIPE, and a program inherits that: `yes` would
    // get a write error instead, and a writer that does not stop on one —
    // `tail -f` on macOS, a shell loop — would run on forever.
    final stderr = Captured();
    expect(
      await withStderr(
        stderr,
        () =>
            exec('/bin/bash', ['-c', r'yes | head -1; echo ${PIPESTATUS[0]}']),
      ),
      'y\n141\n',
    );
    expect(stderr.text, isEmpty);
  }, skip: File('/bin/bash').existsSync() ? null : 'no /bin/bash');

  test('exits with 127 and says why when there is no such program', () async {
    final stderr = Captured();
    await expectLater(
      withStderr(stderr, () => exec('nanoflow-no-such-program', [])),
      throwsA(isA<ExecException>().having((e) => e.exitCode, 'exitCode', 127)),
    );
    expect(stderr.text, contains('nanoflow-no-such-program'));
  });

  test('passes the arguments as they are', () async {
    expect(
      await exec('/usr/bin/printf', ['%s|', 'a b', r'$HOME', '"q"', '']),
      'a b|\$HOME|"q"||',
    );
  });

  test('writes stdin to the program and closes it', () async {
    expect(await exec('cat', [], stdin: 'données'), 'données');
  });

  test('closes stdin at once when there is none to write', () async {
    expect(await exec('cat', []), isEmpty);
  });

  test('runs the program in workingDirectory', () async {
    expect(
      await exec('pwd', [], workingDirectory: temp.path),
      '${temp.resolveSymbolicLinksSync()}\n',
    );
  });

  test('runs the program in a process group of its own', () async {
    final ours = await Process.run('ps', ['-o', 'pgid=', '-p', '$pid']);
    final out = await exec('/bin/sh', ['-c', r'echo $$ $(ps -o pgid= -p $$)']);
    final [shell, group] = out.trim().split(RegExp(r'\s+'));
    expect(group, shell);
    expect(group, isNot((ours.stdout as String).trim()));
  });

  test('passes stderr on to the process stderr as it arrives', () async {
    final stderr = Captured();
    final go = p.join(temp.path, 'go');
    // The program ends only once the test has seen its stderr.
    final out = withStderr(
      stderr,
      () => exec('/bin/sh', [
        '-c',
        r'echo "to the log" >&2; while [ ! -e "$0" ]; do sleep 0.05; done; '
            r'echo data',
        go,
      ]),
    );
    await stderr.contains('to the log\n');
    File(go).createSync();
    expect(await out, 'data\n');
    expect(stderr.text, 'to the log\n');
  });

  test('throws a FormatException when stdout is not UTF-8', () async {
    await expectLater(
      exec('/bin/sh', ['-c', r'printf "\377\376"']),
      throwsFormatException,
    );
  });

  test('throws an ExecException for a non-zero exit even when stdout is not '
      'UTF-8', () async {
    await expectLater(
      exec('/bin/sh', ['-c', r'printf "\377\376"; exit 3']),
      throwsA(isA<ExecException>().having((e) => e.exitCode, 'exitCode', 3)),
    );
  });

  test(
    'throws an ExecException when the program exits with non-zero',
    () async {
      final stderr = Captured();
      await expectLater(
        withStderr(
          stderr,
          () => exec('/bin/sh', ['-c', 'echo why >&2; exit 3']),
        ),
        throwsA(
          isA<ExecException>()
              .having((e) => e.executable, 'executable', '/bin/sh')
              .having((e) => e.exitCode, 'exitCode', 3)
              .having(
                (e) => '$e',
                'toString',
                contains('/bin/sh exited with 3'),
              ),
        ),
      );
      expect(stderr.text, 'why\n');
    },
  );

  test('runs programs through bash when there is one', () async {
    // ps prints the path of the program on macOS, only its name on Linux.
    final parent = await exec('/bin/sh', ['-c', r'ps -o comm= -p $PPID']);
    expect(p.basename(parent.trim()), 'bash');
  }, skip: File('/bin/bash').existsSync() ? null : 'no /bin/bash');

  group(
    'through a shell without job control, as dash is without a terminal',
    () {
      test('hands the program its stdin', () async {
        expect(
          await withoutTerminal('/bin/dash', [
            '-c',
            inGroupScript,
            'sh',
            'cat',
          ], stdin: 'piped'),
          'piped',
        );
      }, skip: noDash);

      test('throws instead of running a program it could not stop', () async {
        Future<String> through(String shell) => withoutTerminal(
          Platform.resolvedExecutable,
          ['run', p.join('test', 'fixtures', 'exec_through.dart'), shell],
        );
        expect(await through('/bin/bash'), 'piped\n');
        expect(
          await through('/bin/dash'),
          'exec cannot run cat in a process group of its own, so a stop '
          'of the step could not end it: /bin/dash turns job control off '
          'without a terminal; install bash\n',
        );
      }, skip: noDash);
    },
  );
}
