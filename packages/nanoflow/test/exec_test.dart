import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:nanoflow/nanoflow.dart';
import 'package:nanoflow/src/exec.dart' show execIn, inGroupScript;
import 'package:nanoflow/src/flow.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support.dart';

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
  List<String> arguments,
) async {
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
  await process.stdin.close();
  process.stderr.drain<void>().ignore();
  final out = await utf8.decodeStream(process.stdout);
  ended = true;
  return out;
}

/// Runs [program] through bash with [inGroupScript] as [exec] does, keeping
/// the pipe on the shell's stdin open until it exits; gives what it printed
/// on stdout and stderr.
Future<({String out, String err})> runInGroup(
  List<String> program, {
  Map<String, String>? environment,
}) async {
  final shell = await Process.start('/bin/bash', [
    '-c',
    inGroupScript,
    'sh',
    ...program,
  ], environment: environment);
  final out = utf8.decodeStream(shell.stdout);
  final err = utf8.decodeStream(shell.stderr);
  await shell.exitCode;
  await shell.stdin.close();
  return (out: await out, err: await err);
}

/// Whether the process [pid] runs: it is there, and not a zombie.
bool isRunning(int pid) {
  final ps = Process.runSync('ps', ['-o', 'stat=', '-p', '$pid']);
  return ps.exitCode == 0 && !(ps.stdout as String).trim().startsWith('Z');
}

/// The ids of the [count] processes that wrote them to [file], one per
/// line, once they have; each is killed after the test if it still runs.
Future<List<int>> pidsIn(String file, int count) async {
  var pids = <int>[];
  await until(() {
    if (!File(file).existsSync()) return false;
    pids = [for (final line in File(file).readAsLinesSync()) int.parse(line)];
    return pids.length == count;
  }, '$count pids in $file');
  for (final pid in pids) {
    addTearDown(() {
      if (isRunning(pid)) Process.killPid(pid, ProcessSignal.sigkill);
    });
  }
  return pids;
}

/// Arguments of [exec] for `/bin/sh` that make it append its pid to
/// [pidFile], then sleep for 100 s.
List<String> sleeper(String pidFile) => [
  '-c',
  r'echo $$ >> "$0"; exec sleep 100',
  pidFile,
];

/// Where [sleepsInEffect] and [sleepsBeside] have their program write its pid.
late String pidFile;

/// What [exec] threw in [sleepsInEffect] and [sleepsBeside], in order.
final execErrors = <Object>[];

/// Opened to let [sleepsBeside] past its effect `wait`.
late Completer<void> gate;

/// An effect that runs a program that sleeps for 100 s, then another program.
Future<String> sleepsInEffect(Flow f, String x) => f.effect('sleep', () async {
  for (final arguments in [sleeper(pidFile), <String>[]]) {
    try {
      await exec('/bin/sh', arguments);
    } on Exception catch (e) {
      execErrors.add(e);
    }
  }
  return 'woke';
});

/// An effect that runs a program that sleeps for 100 s, and beside it an effect
/// that waits for [gate].
Future<void> sleepsBeside(Flow f, String x) async {
  await Future.wait([
    f.effect('sleep', () async {
      try {
        return await exec('/bin/sh', sleeper(pidFile));
      } on Exception catch (e) {
        execErrors.add(e);
        rethrow;
      }
    }),
    f.effect('wait', () => gate.future),
  ]);
}

/// An effect that runs a program that writes to stderr.
Future<String> complainsInEffect(Flow f, String x) => f.effect(
  'complain',
  () => exec('/bin/sh', ['-c', 'echo to the log >&2; echo out']),
);

/// Runs a program that writes to stderr, outside the effects.
Future<String> complainsOutside(Flow f, String x) =>
    exec('/bin/sh', ['-c', 'echo to stderr >&2; echo out']);

/// An effect that runs a program that writes 3 MB to stderr.
Future<String> floodsLog(Flow f, String x) => f.effect(
  'flood',
  () => exec('/bin/sh', [
    '-c',
    r"head -c 3000000 /dev/zero | tr '\0' x >&2; echo done",
  ]),
);

/// The shell [execsThenEffects] runs its program through.
late String shellPath;

/// Runs a program through [shellPath] in the workflow, then an effect.
Future<String> execsThenEffects(Flow f, String x) async {
  await execIn(shellPath, 'true', []);
  return f.effect('after', () => 'x');
}

/// The keys of the effects of the session [sessionId] in [dir].
Future<List<String>> keysOf(String dir, String sessionId) async => [
  for (final effect in await (await openSession(dir, sessionId)).effects())
    effect.key,
];

/// Why a test that needs bash is skipped, or `null` when there is one.
final String? noBash = File('/bin/bash').existsSync() ? null : 'no /bin/bash';

/// Why a test that needs dash is skipped, or `null` when there is one.
final String? noDash = File('/bin/dash').existsSync() ? null : 'no /bin/dash';

/// Why a test that needs perl is skipped, or `null` when there is one. Without
/// it [exec] runs programs with SIGPIPE ignored.
final String? noPerl = File('/usr/bin/perl').existsSync()
    ? null
    : 'no /usr/bin/perl';

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
  }, skip: noBash ?? noPerl);

  test('keeps perl out of the effect log and out of the program\'s '
      'environment under a locale that is not installed', () async {
    // perl warns on stderr about it, unless told not to with PERL_BADLANG,
    // which then must not reach the program.
    final run = await runInGroup(
      ['/bin/sh', '-c', r'echo "${PERL_BADLANG-unset}"'],
      environment: {'LANG': 'xx_XX.UTF-8', 'LC_ALL': 'xx_XX.UTF-8'},
    );
    expect(run.out, 'unset\n');
    expect(run.err, matches(RegExp(r'^nanoflow-exec-group \d+\n$')));
  }, skip: noBash ?? noPerl);

  test('takes an executable that starts with - for a program, not a switch '
      'of perl', () async {
    // `-v` as a switch makes perl print its version and exit with 0.
    final stderr = Captured();
    await expectLater(
      withStderr(stderr, () => exec('-v', [])),
      throwsA(isA<ExecException>()),
    );
    expect(stderr.text, contains('-v'));
  });

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
      await exec('/usr/bin/printf', [
        '%s|',
        'a b',
        r'$HOME',
        '"q"',
        '',
        '-n',
        '--',
      ]),
      'a b|\$HOME|"q"||-n|--|',
    );
  });

  test('gives the program an empty stdin', () async {
    expect(await exec('cat', []), isEmpty);
  });

  test('adds environment to the environment of the process', () async {
    expect(
      await exec(
        '/bin/sh',
        ['-c', r'echo "$NANOFLOW_GREETING $HOME"'],
        environment: {'NANOFLOW_GREETING': 'hello'},
      ),
      'hello ${Platform.environment['HOME']}\n',
    );
  });

  group('with color', () {
    const variables = r'echo "$FORCE_COLOR $CLICOLOR_FORCE"';

    test('asks the program to color what it prints, though it prints to no '
        'terminal', () async {
      expect(await exec('/bin/sh', ['-c', variables], color: true), '1 1\n');
    });

    test('environment goes over what it asks', () async {
      expect(
        await exec(
          '/bin/sh',
          ['-c', variables],
          color: true,
          environment: {'FORCE_COLOR': '3'},
        ),
        '3 1\n',
      );
    });

    test('returns stdout without its escape sequences', () async {
      const colored =
          r'\033[1;31mred\033[0m '
          r'\033]8;;https://x.dev\033\\link\033]8;;\033\\ '
          r'\033[Kdone\n';
      expect(
        await exec('/usr/bin/printf', [colored], color: true),
        'red link done\n',
      );
      expect(
        await exec('/usr/bin/printf', [r'\033[31mred\033[0m']),
        '\x1b[31mred\x1b[0m',
      );
    });

    test('leaves the colors of stderr as they are', () async {
      final stderr = Captured();
      await withStderr(
        stderr,
        () => exec('/bin/sh', [
          '-c',
          r'printf "\033[31mred\033[0m\n" >&2',
        ], color: true),
      );
      expect(stderr.text, '\x1b[31mred\x1b[0m\n');
    });
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
  }, skip: noBash);

  test('through a shell without job control, as dash is without a '
      'terminal, throws instead of running a program it could not '
      'stop', () async {
    Future<String> through(String shell) => withoutTerminal(
      Platform.resolvedExecutable,
      ['run', p.join('test', 'fixtures', 'exec_through.dart'), shell],
    );
    expect(await through('/bin/bash'), 'ran\n');
    expect(
      await through('/bin/dash'),
      'exec cannot run echo in a process group of its own, so it could not '
      'be stopped with what it starts: /bin/dash turns job control off '
      'without a terminal; install bash\n',
    );
  }, skip: noDash);

  group('the program dies with the process that ran it', () {
    test('as the shell that runs it ends its group, with what it started, '
        'when the pipe on its stdin closes', () async {
      final pids = p.join(temp.path, 'pids');
      final shell = await Process.start('/bin/bash', [
        '-c',
        inGroupScript,
        'sh',
        '/bin/sh',
        '-c',
        r'sleep 100 & echo $! >> "$0"; wait',
        pids,
      ]);
      shell.stdout.drain<void>().ignore();
      shell.stderr.drain<void>().ignore();
      final [sleep] = await pidsIn(pids, 1);
      // The watcher leaves the program alone while the pipe is open.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(isRunning(sleep), isTrue);

      await shell.stdin.close();

      expect(await shell.exitCode.timeout(const Duration(seconds: 5)), 143);
      expect(isRunning(sleep), isFalse);
    }, skip: noBash);

    test('even when that process is killed with SIGKILL', () async {
      final pids = p.join(temp.path, 'pids');
      final process = await Process.start(Platform.resolvedExecutable, [
        p.join('test', 'fixtures', 'exec_dies_with.dart'),
        pids,
      ]);
      addTearDown(() => process.kill(ProcessSignal.sigkill));
      process.stdout.drain<void>().ignore();
      process.stderr.drain<void>().ignore();
      final sleeps = await pidsIn(pids, 2);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(sleeps.every(isRunning), isTrue);

      process.kill(ProcessSignal.sigkill);
      await process.exitCode;

      await until(
        () => !sleeps.any(isRunning),
        'the end of the programs',
        within: const Duration(seconds: 5),
      );
    });
  });

  group('in a session', () {
    late String dir;

    setUp(() async {
      dir = await tempDir();
      pidFile = p.join(temp.path, 'pids');
      execErrors.clear();
    });

    test('writes the stderr of a program run in an effect to the effect\'s '
        'log', () async {
      final stderr = Captured();

      expect(
        await withStderr(
          stderr,
          () => Flow(directory: dir).runWorkflow(complainsInEffect, 'x'),
        ),
        'out\n',
      );

      expect(stderr.text, isEmpty);
      expect(
        await logOfEffect(await onlySession(dir), 'complain'),
        'to the log\n',
      );
    });

    test('writes all of a flood of stderr to the effect\'s log', () async {
      expect(await Flow(directory: dir).runWorkflow(floodsLog, 'x'), 'done\n');

      expect(await logOfEffect(await onlySession(dir), 'flood'), 'x' * 3000000);
    });

    test('passes the stderr of a program run outside the effects on to the '
        'process stderr', () async {
      final stderr = Captured();

      expect(
        await withStderr(
          stderr,
          () => Flow(directory: dir).runWorkflow(complainsOutside, 'x'),
        ),
        'out\n',
      );

      expect(stderr.text, 'to stderr\n');
      expect(await (await onlySession(dir)).effects(), isEmpty);
    });

    test('flow.stop() ends the group of a program that runs, and exec throws '
        'a FlowStoppedException then, and at once after', () async {
      final flow = Flow(directory: dir);
      final session = await flow.startWorkflow(sleepsInEffect, 'x');
      final [sleep] = await pidsIn(pidFile, 1);

      flow.stop();

      await expectLater(session.result, throwsA(isA<FlowStoppedException>()));
      expect(execErrors, [
        isA<FlowStoppedException>(),
        isA<FlowStoppedException>(),
      ]);
      expect(isRunning(sleep), isFalse);
    });

    test('moves no effect key: the first program through a shell, which '
        'probes the shell, and a later one give the same keys', () async {
      // A path to bash that no test has run a program through before.
      shellPath = '/bin/./bash';
      final flow = Flow(directory: dir);

      final first = await flow.startWorkflow(execsThenEffects, 'x');
      await first.result;
      final second = await flow.startWorkflow(execsThenEffects, 'x');
      await second.result;

      final keys = await keysOf(dir, first.id);
      expect(keys, hasLength(1));
      expect(await keysOf(dir, second.id), keys);
    }, skip: noBash);

    test('a failure of the store ends the group of a program that runs, and '
        'exec throws the StorageException', () async {
      gate = Completer();
      final session = await Flow(directory: dir)
          .startWorkflow(sleepsBeside, 'x');
      final [sleep] = await pidsIn(pidFile, 1);

      Directory(sessionDirOf(dir, session.id)).deleteSync(recursive: true);
      gate.complete();

      await expectLater(session.result, throwsA(isA<StorageException>()));
      expect(execErrors, [isA<StorageException>()]);
      expect(isRunning(sleep), isFalse);
    });
  });
}
