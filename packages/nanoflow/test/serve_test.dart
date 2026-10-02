@Timeout(Duration(minutes: 2))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:nanoflow/src/build.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'fixtures/program.dart' as program;

String fixture(String name) => p.absolute('test', 'fixtures', name);

final String programFile = fixture('program.dart');

/// Text a process writes to one of its streams, collected as it arrives.
final class Output {
  Output(Stream<List<int>> stream) {
    _reading = stream.transform(utf8.decoder).listen((text) {
      _text.write(text);
      _changes.add(null);
    }, onDone: _end);
  }

  late final StreamSubscription<String> _reading;
  final _text = StringBuffer();
  final _changes = StreamController<void>.broadcast();
  var _ended = false;

  String get text => '$_text';

  /// Stops reading the stream, as a reader that is gone: what the process
  /// writes to it after that fails.
  Future<void> close() async {
    await _reading.cancel();
    _end();
  }

  void _end() {
    _ended = true;
    _changes.add(null);
  }

  /// Waits until the text written so far passes [test]; throws if the
  /// stream ends first.
  Future<void> until(bool Function(String text) test) async {
    while (!test(text)) {
      if (_ended) throw StateError('the stream ended with: $text');
      await _changes.stream.first;
    }
  }

  /// All the text, once the stream has ended or was closed.
  Future<String> get whole async {
    while (!_ended) {
      await _changes.stream.first;
    }
    return text;
  }
}

/// Every graph program [start] started, to kill once the tests are over:
/// a test that fails or times out must not leave one running.
final _started = <Process>[];

/// Starts the graph program [file] with `dart run` and [args].
Future<Process> start(String file, List<String> args) async {
  final process = await Process.start(Platform.resolvedExecutable, [
    'run',
    file,
    ...args,
  ]);
  _started.add(process);
  process.stdin.done.ignore();
  return process;
}

/// Kills every graph program [start] started that still runs.
void killStarted() {
  for (final process in _started) {
    process.kill(ProcessSignal.sigkill);
  }
}

/// How a run of a graph program ended.
typedef Ended = ({int exitCode, String stdout, String stderr});

/// Runs the graph program [file] with [args], writing [stdin].
///
/// With [close], stdin is closed after [stdin]; otherwise it stays open until
/// the program exits, as the engine leaves the stdin of `--call` open.
Future<Ended> run(
  String file,
  List<String> args, {
  String stdin = '',
  bool close = true,
}) async {
  final process = await start(file, args);
  final stdout = utf8.decodeStream(process.stdout);
  final stderr = utf8.decodeStream(process.stderr);
  process.stdin.write(stdin);
  if (close) process.stdin.close().ignore();
  final exitCode = await process.exitCode;
  if (!close) process.stdin.close().ignore();
  return (exitCode: exitCode, stdout: await stdout, stderr: await stderr);
}

/// Runs `--call [node]` of the program [file] — the program fixture unless
/// given — with the input [line].
Future<Ended> call(String node, String line, [String? file]) =>
    run(file ?? programFile, ['--call', node], stdin: '$line\n', close: false);

/// Calls the nodes of the program whose data classes declare toJson
/// abstract one after another, each with what the one before printed.
Future<List<Ended>> callAbstractToJson() async {
  final file = fixture('program_with_abstract_to_json.dart');
  final judged = await call('judge', '3', file);
  final summarized = await call('summarize', judged.stdout.trim(), file);
  final shouted = await call('shout', summarized.stdout.trim(), file);
  return [judged, summarized, shouted];
}

/// How `--call` of a node that waits on its command ended after a stop, the
/// pids its command told, and how long it took to exit after the stop.
typedef Stopped = ({
  int exitCode,
  String stdout,
  List<int> pids,
  Duration exitedIn,
});

/// A `--call` running as the engine runs it, and what it writes.
typedef Calling = ({Process process, Output stdout, Output stderr});

/// Runs `--call [node]`, waits until the node's command tells the pids of
/// the processes it started — a line `pids <pid>…` on stderr — then calls
/// [stop]. Throws if `--call` has not exited 30 s after.
Future<Stopped> stopMidStep(
  String node,
  FutureOr<void> Function(Calling call) stop,
) async {
  final process = await start(programFile, ['--call', node]);
  final call = (
    process: process,
    stdout: Output(process.stdout),
    stderr: Output(process.stderr),
  );
  process.stdin.writeln();
  final told = RegExp(r'^pids (\d+(?: \d+)*)$', multiLine: true);
  await call.stderr.until(told.hasMatch);
  final match = told.firstMatch(call.stderr.text)!;
  final watch = Stopwatch()..start();
  await stop(call);
  final exitCode = await process.exitCode.timeout(
    const Duration(seconds: 30),
    onTimeout: () => throw TimeoutException('--call $node has not exited'),
  );
  process.stdin.close().ignore();
  return (
    exitCode: exitCode,
    stdout: await call.stdout.whole,
    pids: [for (final pid in match[1]!.split(' ')) int.parse(pid)],
    exitedIn: watch.elapsed,
  );
}

/// Ends the stdin of [call], which stops the step.
void closeStdin(Calling call) => call.process.stdin.close().ignore();

/// How `--call` of a node that ends while a `sleep` it started with `exec`
/// runs ended, and the pid of that `sleep`.
typedef EndedWithSleep = ({Ended ended, int sleep});

/// Runs `--call [node]` with a fresh file for the pid of the node's `sleep`
/// as its input. The `sleep` is killed after the tests, if it still runs.
Future<EndedWithSleep> endsWhileExecRuns(String node) async {
  final dir = Directory.systemTemp.createTempSync('nanoflow_sleep_');
  final pidFile = p.join(dir.path, 'sleep.pid');
  final ended = await call(node, jsonEncode(pidFile));
  final sleep = int.parse(File(pidFile).readAsStringSync().trim());
  addTearDown(() {
    if (isRunning(sleep)) Process.killPid(sleep, ProcessSignal.sigkill);
    dir.deleteSync(recursive: true);
  });
  return (ended: ended, sleep: sleep);
}

/// Whether process [pid] is still running: it exists and is not a zombie.
bool isRunning(int pid) {
  final ps = Process.runSync('ps', ['-o', 'stat=', '-p', '$pid']);
  return ps.exitCode == 0 && !(ps.stdout as String).trim().startsWith('Z');
}

/// A pub package `graph_package` in a fresh directory, which depends on
/// nanoflow and holds [files] — their contents by path — with its
/// dependencies got. Gives the package's directory, deleted after the test.
Future<String> graphPackage(Map<String, String> files) async {
  final package = Directory.systemTemp
      .createTempSync('nanoflow_package_')
      .resolveSymbolicLinksSync();
  addTearDown(() => Directory(package).deleteSync(recursive: true));
  File(p.join(package, 'pubspec.yaml')).writeAsStringSync(
    'name: graph_package\n'
    'environment:\n'
    '  sdk: ^3.13.0\n'
    'dependencies:\n'
    '  nanoflow:\n'
    '    path: ${jsonEncode(p.absolute('.'))}\n',
  );
  for (final MapEntry(key: path, value: contents) in files.entries) {
    File(p.join(package, path))
      ..createSync(recursive: true)
      ..writeAsStringSync(contents);
  }
  final got = await Process.run(Platform.resolvedExecutable, [
    'pub',
    'get',
    '--offline',
  ], workingDirectory: package);
  expect(got.exitCode, 0, reason: '${got.stdout}${got.stderr}');
  return package;
}

/// Starts `dart run :graph --graph --watch` in [package], killed after the
/// test: the program `bin/graph.dart` as a package executable, which runs
/// a snapshot pub builds under `.dart_tool`. Gives its stdout and the lines
/// printed there so far.
Future<({Output stdout, List<String> Function() lines})> watchPackage(
  String package,
) async {
  final process = await Process.start(Platform.resolvedExecutable, [
    'run',
    ':graph',
    '--graph',
    '--watch',
  ], workingDirectory: package);
  addTearDown(process.kill);
  final stdout = Output(process.stdout);
  Output(process.stderr);
  return (
    stdout: stdout,
    lines: () => const LineSplitter().convert(stdout.text),
  );
}

/// The names of the nodes in [description], a line `--graph` printed.
List<String> nodesOf(String description) {
  final json = jsonDecode(description) as Map<String, Object?>;
  final graph = json['graph']! as Map<String, Object?>;
  return [...(graph['nodes']! as Map<String, Object?>).keys];
}

void main() {
  tearDownAll(killStarted);

  group('serve', () {
    // Every program run here is independent, so all of them start at once.
    late Future<Ended> graph,
        noStart,
        usage,
        input,
        badInput,
        noInputFunction,
        nothingToInput,
        worker,
        ifFork,
        switchFork,
        withoutOut,
        throwing,
        unknownNode,
        badLine;
    late Future<List<Ended>> abstractToJson;
    late Future<Stopped> closedStdin,
        terminated,
        interrupted,
        ignoresTerm,
        engineGone,
        leftClosedStdin,
        leftTerminated;
    late Future<EndedWithSleep> timedOut, returned, uncaught;

    setUpAll(() {
      graph = run(programFile, ['--graph']);
      noStart = run(fixture('program_without_start.dart'), ['--graph']);
      usage = run(programFile, []);
      input = run(programFile, [
        '--input',
      ], stdin: '{ "branch": "main", "extra": true }');
      badInput = run(programFile, ['--input'], stdin: '{"branch": 1}');
      noInputFunction = run(fixture('program_without_input.dart'), [
        '--input',
      ], stdin: '"text"');
      nothingToInput = run(fixture('program_taking_nothing.dart'), [
        '--input',
      ], close: false);
      worker = call('collect', '{"branch":"main"}');
      ifFork = call('isEmpty', '{"id":"1","path":""}');
      switchFork = call(
        'verdict',
        '{"change":{"id":"1","path":"a"},"findings":["typo"]}',
      );
      withoutOut = call(
        'notify',
        '{"change":{"id":"7","path":"a"},"findings":[]}',
      );
      throwing = call(
        'fix',
        '{"change":{"id":"1","path":"a.dart"},"findings":["typo"]}',
      );
      unknownNode = call('nope', '');
      badLine = call('collect', '{"branch":3}');
      abstractToJson = callAbstractToJson();
      closedStdin = stopMidStep('hang', closeStdin);
      terminated = stopMidStep(
        'hang',
        (c) => c.process.kill(ProcessSignal.sigterm),
      );
      interrupted = stopMidStep(
        'hang',
        (c) => c.process.kill(ProcessSignal.sigint),
      );
      ignoresTerm = stopMidStep('hangHard', closeStdin);
      engineGone = stopMidStep('logsWhenStopped', (c) async {
        // The engine dies: nothing reads what the call writes any more, and
        // the OS closes its stdin.
        await c.stdout.close();
        await c.stderr.close();
        closeStdin(c);
      });
      leftClosedStdin = stopMidStep('leavesChild', closeStdin);
      leftTerminated = stopMidStep(
        'leavesChild',
        (c) => c.process.kill(ProcessSignal.sigterm),
      );
      timedOut = endsWhileExecRuns('timesOut');
      returned = endsWhileExecRuns('returnsEarly');
      uncaught = endsWhileExecRuns('failsUncaught');
    });

    group('--graph', () {
      test('prints the description as one line of JSON', () async {
        final expected = jsonEncode(
          describe(buildGraph(program.graph), programFile),
        );
        expect(await graph, (exitCode: 0, stdout: '$expected\n', stderr: ''));
      });

      test('prints build errors one per line and exits with 1', () async {
        expect(await noStart, (
          exitCode: 1,
          stdout: '',
          stderr:
              'graph has no Graph.start\n'
              'length: next is declared twice\n',
        ));
      });
    });

    test('prints usage for unknown arguments and exits with 2', () async {
      final ended = await usage;
      expect(ended.exitCode, 2);
      expect(ended.stdout, isEmpty);
      expect(ended.stderr, startsWith('usage: program.dart --graph'));
    });

    group('--input', () {
      test('prints what the input function returned, as JSON', () async {
        expect(await input, (
          exitCode: 0,
          stdout: '{"branch":"main"}\n',
          stderr: '',
        ));
      });

      test('exits with 1 when the input function throws', () async {
        final ended = await badInput;
        expect(ended.exitCode, 1);
        expect(ended.stdout, isEmpty);
        expect(ended.stderr, contains("'int' is not a subtype of type"));
      });

      test('exits with 1 when a start node takes input but serve has no '
          'input function', () async {
        final ended = await noInputFunction;
        expect(ended.exitCode, 1);
        expect(ended.stdout, isEmpty);
        expect(ended.stderr, contains('no input function'));
      });

      test('prints null without reading stdin when no start node takes '
          'input', () async {
        expect(await nothingToInput, (
          exitCode: 0,
          stdout: 'null\n',
          stderr: '',
        ));
      });
    });

    group('--call', () {
      test('a worker prints its result as JSON', () async {
        expect(await worker, (
          exitCode: 0,
          stdout: '{"id":"1","path":"lib/main.dart"}\n',
          stderr: '',
        ));
      });

      test('an if prints its outcome as a JSON bool', () async {
        expect(await ifFork, (exitCode: 0, stdout: 'true\n', stderr: ''));
      });

      test('a switch prints its outcome key, an enum by name', () async {
        expect(await switchFork, (
          exitCode: 0,
          stdout: '"returned"\n',
          stderr: '',
        ));
      });

      test('a worker without out prints nothing; its print goes to '
          'stderr', () async {
        expect(await withoutOut, (
          exitCode: 0,
          stdout: '',
          stderr: 'notified about change 7\n',
        ));
      });

      test('an exception exits with 1, its message and stack trace on '
          'stderr', () async {
        final ended = await throwing;
        expect(ended.exitCode, 1);
        expect(ended.stdout, isEmpty);
        expect(ended.stderr, startsWith('Bad state: cannot fix a.dart\n'));
        expect(ended.stderr, contains('program.dart'));
      });

      test('an unknown node exits with 1', () async {
        expect(await unknownNode, (
          exitCode: 1,
          stdout: '',
          stderr: 'unknown node "nope"\n',
        ));
      });

      test('an input that does not fit the node exits with 1', () async {
        final ended = await badLine;
        expect(ended.exitCode, 1);
        expect(ended.stdout, isEmpty);
        expect(ended.stderr, startsWith('invalid input: Request.fromJson'));
      });

      test('data classes whose toJson is abstract, a sealed base and a '
          'freezed 3 model, go from step to step as JSON', () async {
        expect(await abstractToJson, [
          (exitCode: 0, stdout: '{"kind":"passed","count":3}\n', stderr: ''),
          (exitCode: 0, stdout: '{"text":"3 passed"}\n', stderr: ''),
          (exitCode: 0, stdout: '"3 PASSED"\n', stderr: ''),
        ]);
      });

      group('stops the command with its process group', () {
        void expectStopped(Stopped stopped, int exitCode) {
          addTearDown(() {
            for (final pid in stopped.pids.where(isRunning)) {
              Process.killPid(pid, ProcessSignal.sigkill);
            }
          });
          expect(stopped.exitCode, exitCode);
          expect(stopped.stdout, isEmpty);
          for (final pid in stopped.pids) {
            expect(isRunning(pid), isFalse, reason: 'process $pid');
          }
        }

        test('when stdin ends, exiting with 1', () async {
          expectStopped(await closedStdin, 1);
        });

        test('on SIGTERM, exiting with 143', () async {
          expectStopped(await terminated, 143);
        });

        test('on SIGINT, exiting with 130', () async {
          expectStopped(await interrupted, 130);
        });

        test('with SIGKILL 5 s after a SIGTERM it ignores', () async {
          final stopped = await ignoresTerm;
          expectStopped(stopped, 1);
          expect(stopped.exitedIn, greaterThan(const Duration(seconds: 5)));
        });

        test('when the engine is gone, though the command writes to the log '
            'as it stops and nothing reads the log: exits all the same, with '
            '1', () async {
          final stopped = await engineGone;
          expectStopped(stopped, 1);
          expect(stopped.exitedIn, lessThan(const Duration(seconds: 10)));
        });

        group('also once the program has exited, leaving a process in its '
            'group that holds its stdout', () {
          test('when stdin ends, exiting with 1', () async {
            expectStopped(await leftClosedStdin, 1);
          });

          test('on SIGTERM, exiting with 143', () async {
            expectStopped(await leftTerminated, 143);
          });
        });
      });

      group('stops what exec still runs once the step has ended', () {
        test('by an exception: exits with 1', () async {
          final (:ended, :sleep) = await timedOut;
          expect(ended.exitCode, 1);
          expect(ended.stdout, isEmpty);
          expect(ended.stderr, startsWith('TimeoutException'));
          expect(isRunning(sleep), isFalse);
        });

        test('by returning: exits with 0', () async {
          final (:ended, :sleep) = await returned;
          expect(ended, (exitCode: 0, stdout: '', stderr: ''));
          expect(isRunning(sleep), isFalse);
        });

        test('by an error nobody awaits, a failure like an exception: exits '
            'with 1', () async {
          final (:ended, :sleep) = await uncaught;
          expect(ended.exitCode, 1);
          expect(ended.stdout, isEmpty);
          expect(ended.stderr, startsWith('Bad state: nobody awaits this\n'));
          expect(isRunning(sleep), isFalse);
        });
      });
    });
  });

  test('--graph --watch prints the description again when the graph changes, '
      'and nothing while the program does not compile', () async {
    final original = File(fixture('program_without_input.dart'))
        .readAsStringSync();
    String edited(Map<String, String> changes) {
      var source = original;
      for (final MapEntry(key: from, value: to) in changes.entries) {
        expect(source, contains(from));
        source = source.replaceFirst(from, to);
      }
      return source;
    }

    final directory = Directory.systemTemp.createTempSync('nanoflow_watch_');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File(p.join(directory.path, 'graph.dart'))
      ..writeAsStringSync(original);

    final process = await Process.start(Platform.resolvedExecutable, [
      'run',
      // The copy is outside the workspace: it needs the workspace packages.
      '--packages=${Isolate.packageConfigSync!.toFilePath()}',
      file.path,
      '--graph',
      '--watch',
    ]);
    addTearDown(process.kill);
    final stdout = Output(process.stdout);
    final stderr = Output(process.stderr);
    List<String> lines() => const LineSplitter().convert(stdout.text);

    await stdout.until((text) => text.endsWith('\n'));
    final first = lines().single;
    expect(nodesOf(first), ['length']);
    expect((jsonDecode(first) as Map<String, Object?>)['file'], file.path);

    // Does not compile: the compiler's errors on stderr, nothing on stdout.
    file.writeAsStringSync('$original\nfinal broken = ;\n');
    await stderr.until((text) => text.contains('Error'));

    // Compiles again, with the same graph: nothing on stdout. Every node
    // stays on its line, since the description holds the lines.
    file.writeAsStringSync(
      edited({
        "import 'package:nanoflow/nanoflow.dart';":
            "import 'dart:io'; import 'package:nanoflow/nanoflow.dart';",
        'void main(List<String> args) => serve(args, graph);':
            "void main(List<String> args) { stderr.writeln('same graph'); "
            'serve(args, graph); }',
      }),
    );
    await stderr.until((text) => text.contains('same graph'));

    // A new node, whose initializer prints before serve runs, so that the
    // program prints a line before the description: only the description
    // is the next line.
    file.writeAsStringSync(
      '${edited({'Graph.start(length)': 'Graph.start(length).next(half)'})}\n'
      'final half = () {\n'
      "  print('stray');\n"
      '  return node((int n) async => n ~/ 2);\n'
      '}();\n',
    );
    await stdout.until((text) => lines().length >= 2);
    expect(lines(), hasLength(2));
    expect(lines().first, first);
    expect(nodesOf(lines().last), ['length', 'half']);
    await stderr.until((text) => text.contains('stray\n'));
  }, timeout: const Timeout(Duration(minutes: 1)));

  test('run as a package executable, describes the source in bin as its '
      'file, places commands next to it and watches it', () async {
    final original = File(fixture('program_without_input.dart'))
        .readAsStringSync();
    final package = await graphPackage({'bin/graph.dart': original});
    final source = File(p.join(package, 'bin', 'graph.dart'));
    final (:stdout, :lines) = await watchPackage(package);

    await stdout.until((text) => text.endsWith('\n'));
    final first = jsonDecode(lines().single) as Map<String, Object?>;
    expect(first['file'], source.path);
    final graph = first['graph']! as Map<String, Object?>;
    final nodes = graph['nodes']! as Map<String, Object?>;
    final line = original
        .split('\n')
        .indexWhere((l) => l.startsWith('final length ='));
    expect(nodes['length'], containsPair('command', 'graph.dart:${line + 1}'));

    source.writeAsStringSync(
      '${original.replaceFirst('Graph.start(length)', 'Graph.start(length).next(half)')}\n'
      'final half = node((int n) async => n ~/ 2);\n',
    );
    await stdout.until((text) => lines().length >= 2);
    expect(nodesOf(lines().last), ['length', 'half']);
  }, timeout: const Timeout(Duration(minutes: 1)));

  test('run as a package executable, watches the whole package: a graph in '
      'lib behind main in bin', () async {
    const main = 'void main(List<String> args) => serve(args, graph);\n';
    final original = File(fixture('program_without_input.dart'))
        .readAsStringSync();
    expect(original, contains(main));
    final package = await graphPackage({
      'lib/graph.dart': original.replaceFirst(main, ''),
      'bin/graph.dart':
          "import 'package:graph_package/graph.dart';\n"
          "import 'package:nanoflow/nanoflow.dart';\n"
          '\n'
          '$main',
    });
    final library = File(p.join(package, 'lib', 'graph.dart'));
    final (:stdout, :lines) = await watchPackage(package);

    await stdout.until((text) => text.endsWith('\n'));
    expect(nodesOf(lines().single), ['length']);

    library.writeAsStringSync(
      '${library.readAsStringSync().replaceFirst('Graph.start(length)', 'Graph.start(length).next(half)')}\n'
      'final half = node((int n) async => n ~/ 2);\n',
    );
    await stdout.until((text) => lines().length >= 2);
    expect(nodesOf(lines().last), ['length', 'half']);
  }, timeout: const Timeout(Duration(minutes: 1)));
}
