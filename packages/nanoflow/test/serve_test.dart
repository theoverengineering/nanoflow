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
    stream
        .transform(utf8.decoder)
        .listen(
          (text) {
            _text.write(text);
            _changes.add(null);
          },
          onDone: () {
            _ended = true;
            _changes.add(null);
          },
        );
  }

  final _text = StringBuffer();
  final _changes = StreamController<void>.broadcast();
  var _ended = false;

  String get text => '$_text';

  /// Waits until the text written so far passes [test]; throws if the
  /// stream ends first.
  Future<void> until(bool Function(String text) test) async {
    while (!test(text)) {
      if (_ended) throw StateError('the stream ended with: $text');
      await _changes.stream.first;
    }
  }
}

/// Starts the graph program [file] with `dart run` and [args].
Future<Process> start(String file, List<String> args) async {
  final process = await Process.start(Platform.resolvedExecutable, [
    'run',
    file,
    ...args,
  ]);
  process.stdin.done.ignore();
  return process;
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

/// Runs `--call [node]` of the program fixture with the input [line].
Future<Ended> call(String node, String line) =>
    run(programFile, ['--call', node], stdin: '$line\n', close: false);

/// How `--call` of a node that waits on its command ended after a stop, and
/// how long it took to exit after the stop.
typedef Stopped = ({
  int exitCode,
  String stdout,
  List<int> pids,
  Duration exitedIn,
});

/// Runs `--call [node]`, waits until the node's command tells the pids of its
/// shell and of the `sleep` the shell started, then calls [stop].
Future<Stopped> stopMidStep(String node, void Function(Process) stop) async {
  final process = await start(programFile, ['--call', node]);
  final stdout = utf8.decodeStream(process.stdout);
  final stderr = Output(process.stderr);
  process.stdin.writeln();
  final told = RegExp(r'^pids (\d+) (\d+)$', multiLine: true);
  await stderr.until(told.hasMatch);
  final match = told.firstMatch(stderr.text)!;
  final watch = Stopwatch()..start();
  stop(process);
  final exitCode = await process.exitCode;
  process.stdin.close().ignore();
  return (
    exitCode: exitCode,
    stdout: await stdout,
    pids: [int.parse(match[1]!), int.parse(match[2]!)],
    exitedIn: watch.elapsed,
  );
}

/// Whether process [pid] is still running: it exists and is not a zombie.
bool isRunning(int pid) {
  final ps = Process.runSync('ps', ['-o', 'stat=', '-p', '$pid']);
  return ps.exitCode == 0 && !(ps.stdout as String).trim().startsWith('Z');
}

/// The names of the nodes in [description], a line `--graph` printed.
List<String> nodesOf(String description) {
  final json = jsonDecode(description) as Map<String, Object?>;
  final graph = json['graph']! as Map<String, Object?>;
  return [...(graph['nodes']! as Map<String, Object?>).keys];
}

void main() {
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
    late Future<Stopped> closedStdin, terminated, interrupted, ignoresTerm;

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
      closedStdin = stopMidStep('hang', (p) => p.stdin.close().ignore());
      terminated = stopMidStep('hang', (p) => p.kill(ProcessSignal.sigterm));
      interrupted = stopMidStep('hang', (p) => p.kill(ProcessSignal.sigint));
      ignoresTerm = stopMidStep('hangHard', (p) => p.stdin.close().ignore());
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

      group('stops the command with its process group', () {
        void expectStopped(Stopped stopped, int exitCode) {
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

    // A new node: the next line is the new description.
    file.writeAsStringSync(
      '${edited({'Graph.start(length)': 'Graph.start(length).next(half)'})}\n'
      'final half = node((int n) async => n ~/ 2);\n',
    );
    await stdout.until((text) => lines().length == 2);
    expect(lines().first, first);
    expect(nodesOf(lines().last), ['length', 'half']);
  }, timeout: const Timeout(Duration(minutes: 1)));
}
