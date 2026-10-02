import 'dart:convert';
import 'dart:io';

import 'package:nanoflow_cli/nanoflow_cli.dart';
import 'package:nanoflow_cli/src/engine/engine.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_store/nanoflow_store.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/fake_program.dart';
import '../support/helpers.dart';
import '../support/sessions.dart';

/// The `nanoflow` executable, compiled once for this file: a signal must
/// reach the engine itself, not a `dart` wrapper script.
late final String nanoflowExe;

/// `nanoflow` running as a process of its own; what it prints is collected.
/// It is killed when the test ends, if it still runs.
final class EngineProcess {
  EngineProcess._(this.process, this.pid)
    : out = process.stdout.transform(utf8.decoder).join(),
      err = process.stderr.transform(utf8.decoder).join() {
    var exited = false;
    process.exitCode.then((_) => exited = true).ignore();
    // A shell that started the engine in a group waits for it: once the
    // shell has exited, the engine's pid may belong to another process.
    addTearDown(() {
      if (!exited) Process.killPid(pid, ProcessSignal.sigkill);
    });
  }

  /// Starts `nanoflow` with [args].
  static Future<EngineProcess> start(List<String> args) async {
    final process = await Process.start(nanoflowExe, args);
    return EngineProcess._(process, process.pid);
  }

  /// Starts `nanoflow` with [args] in a process group of its own, as a shell
  /// with job control starts a command: its calls are in the group too. A
  /// signal to the group reaches them all at once, as a terminal's Ctrl+C
  /// does.
  ///
  /// [process] is that shell, which exits with the engine's code (`128 + N`
  /// as well when a signal `N` killed the engine).
  static Future<EngineProcess> startInGroup(List<String> args) async {
    final dir = Directory.systemTemp.createTempSync('nanoflow_group_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final pidFile = File(p.join(dir.path, 'engine.pid'));
    final shell = await Process.start(
      '/bin/sh',
      [
        '-c',
        r'set -m; "$0" "$@" & echo $! > "$PID_FILE.tmp"; '
            r'mv "$PID_FILE.tmp" "$PID_FILE"; wait $!',
        nanoflowExe,
        ...args,
      ],
      environment: {'PID_FILE': pidFile.path},
    );
    await waitFor(pidFile.existsSync);
    return EngineProcess._(shell, int.parse(pidFile.readAsStringSync()));
  }

  /// The process: the engine, or the shell that started it in a group.
  final Process process;

  /// The engine's pid; in a group of its own, also the group's id.
  final int pid;

  /// All it prints on stdout and stderr, once it has exited.
  final Future<String> out;
  final Future<String> err;

  /// Sends [signal] to the engine and gives the code it exits with.
  Future<int> stop(ProcessSignal signal) => _exit(pid, signal);

  /// Sends [signal] to the engine's process group, started by
  /// [startInGroup], and gives the code it exits with.
  Future<int> stopGroup(ProcessSignal signal) => _exit(-pid, signal);

  Future<int> _exit(int target, ProcessSignal signal) async {
    Process.killPid(target, signal);
    return process.exitCode.timeout(const Duration(seconds: 15));
  }
}

/// A graph of two steps: `a`, then `b`.
const twoSteps = {
  'start': 'a',
  'nodes': {
    'a': {'command': 'a', 'then': 'b'},
    'b': {'command': 'b'},
  },
};

/// A node script that writes `attempt` to its log and, the first time,
/// writes its pid to `a.pid` and runs until it is stopped; the next time it
/// exits with 0.
const stopsOnce = '''
echo attempt >&2
[ -e again ] && exit 0
touch again
echo \$\$ > a.pid.tmp && mv a.pid.tmp a.pid
while :; do sleep 0.05; done''';

/// The pid a node script of [fake] wrote to `<name>.pid`, once it has. The
/// process is killed when the test ends, if it still runs.
Future<int> pidOf(FakeProgram fake, String name) async {
  final file = File(p.join(fake.dir, '$name.pid'));
  await waitFor(file.existsSync);
  final pid = int.parse(file.readAsStringSync().trim());
  addTearDown(() => Process.killPid(pid, ProcessSignal.sigkill));
  return pid;
}

/// Whether the process [pid] runs.
bool isAlive(int pid) => Process.runSync('kill', ['-0', '$pid']).exitCode == 0;

void main() {
  setUpAll(() async {
    final dir = Directory.systemTemp.createTempSync('nanoflow_exe_');
    addTearDown(() => dir.deleteSync(recursive: true));
    nanoflowExe = p.join(dir.path, 'nanoflow');
    // Far longer than a compile takes, and far shorter than the 12 minutes
    // the test package gives a setUpAll.
    final compiled = await Process.run(Platform.resolvedExecutable, [
      'compile',
      'exe',
      'bin/nanoflow.dart',
      '-o',
      nanoflowExe,
    ]).timeout(const Duration(minutes: 3));
    if (compiled.exitCode != 0) {
      throw StateError('cannot compile nanoflow: ${compiled.stderr}');
    }
  });

  test('SIGINT: exit 130, the step stops without step-finished, and '
      '--resume runs the same step again', () async {
    final fake = FakeProgram(twoSteps, nodes: {'a': stopsOnce, 'b': 'true'});
    final engine = await EngineProcess.start(['run', '--', fake.path]);
    final command = await pidOf(fake, 'a');
    expect(await engine.stop(ProcessSignal.sigint), 130);
    expect(isAlive(command), isFalse);
    final id = (await engine.out).trim();
    final session = (await FsStore(fake.runsDir).openSession(id))!;
    final run = await onlyRun(session);
    expect(await journal(session, run.id), ['run-started a', 'step-started a']);
    final started = (await session.events(run.id)).last as StepStarted;

    final resumed = await nanoflow(['run', '--resume', id, '--', fake.path]);
    expect(resumed.code, 0, reason: resumed.err);
    expect(resumed.out, '$id\n');
    expect(await journal(session, run.id), [
      'run-started a',
      'step-started a',
      'step-started a',
      'step-finished 0',
      'step-started b',
      'step-finished 0',
      'run-finished',
    ]);
    final steps = await stepsOf(session, run.id);
    expect(steps.first.step.id, started.stepId);
    expect(logOf(session, steps.first.step), 'attempt\nattempt\n');
  });

  test('Ctrl+C, which signals the whole process group: exit 130, the step '
      'stops without step-finished, and --resume runs it again', () async {
    final fake = FakeProgram(twoSteps, nodes: {'a': stopsOnce, 'b': 'true'});
    final engine = await EngineProcess.startInGroup(['run', '--', fake.path]);
    final command = await pidOf(fake, 'a');
    expect(await engine.stopGroup(ProcessSignal.sigint), 130);
    final id = (await engine.out).trim();
    final session = (await FsStore(fake.runsDir).openSession(id))!;
    final run = await onlyRun(session);
    expect(await journal(session, run.id), ['run-started a', 'step-started a']);
    // The call died of the signal, so its command, a process of the engine's
    // no longer, is gone a moment later.
    await waitFor(() => !isAlive(command));

    final resumed = await nanoflow(['run', '--resume', id, '--', fake.path]);
    expect(resumed.code, 0, reason: resumed.err);
    expect(await journal(session, run.id), [
      'run-started a',
      'step-started a',
      'step-started a',
      'step-finished 0',
      'step-started b',
      'step-finished 0',
      'run-finished',
    ]);
  });

  test('SIGTERM: exit 143, the step stops without step-finished', () async {
    final fake = FakeProgram(twoSteps, nodes: {'a': stopsOnce, 'b': 'true'});
    final engine = await EngineProcess.start(['run', '--', fake.path]);
    final command = await pidOf(fake, 'a');
    expect(await engine.stop(ProcessSignal.sigterm), 143);
    expect(isAlive(command), isFalse);
    final id = (await engine.out).trim();
    final session = (await FsStore(fake.runsDir).openSession(id))!;
    expect(await journal(session, (await onlyRun(session)).id), [
      'run-started a',
      'step-started a',
    ]);
  });

  test('SIGINT while --resume drives the session: exit 130', () async {
    final fake = FakeProgram(twoSteps, nodes: {'a': stopsOnce, 'b': 'true'});
    final session = await FsStore(fake.runsDir).createSession(
      graphName: 'graph',
      graph: twoSteps,
      startNodes: [(node: 'a', takesInput: false)],
    );
    // The engine in its own process must get the session's lock.
    await session.release();
    final id = session.session.id;
    final engine = await EngineProcess.start([
      'run',
      '--resume',
      id,
      '--',
      fake.path,
    ]);
    final command = await pidOf(fake, 'a');
    expect(await engine.stop(ProcessSignal.sigint), 130);
    expect(await engine.out, '$id\n');
    expect(isAlive(command), isFalse);
    expect(await journal(session, (await onlyRun(session)).id), [
      'run-started a',
      'step-started a',
    ]);
  });

  test('SIGKILL of the engine: the command stops within seconds', () async {
    final fake = FakeProgram(twoSteps, nodes: {'a': stopsOnce, 'b': 'true'});
    final engine = await EngineProcess.start(['run', '--', fake.path]);
    final command = await pidOf(fake, 'a');
    await engine.stop(ProcessSignal.sigkill);
    await waitFor(() => !isAlive(command));
  });

  group('a call that ends the way SIGINT or SIGTERM ends one', () {
    const oneStep = {
      'start': 'a',
      'nodes': {
        'a': {'command': 'a'},
      },
    };

    test('just before the engine stops: nothing is written', () async {
      // The signal reaches the call first, which ends with 130 when it stops
      // on SIGINT, or dies of SIGTERM.
      for (final ending in ['exit 130', r'kill -TERM $PPID']) {
        final fake = FakeProgram(
          oneStep,
          nodes: {'a': 'touch ending\n$ending'},
        );
        final session = await FsStore(fake.runsDir).createSession(
          graphName: 'graph',
          graph: oneStep,
          startNodes: [(node: 'a', takesInput: false)],
        );
        final progress = IOSink(Capture());
        addTearDown(progress.close);
        final engine = Engine(
          store: session,
          graph: Graph.fromJson(oneStep),
          program: GraphProgram([fake.path]),
          progress: progress,
        );
        final driving = engine.drive();
        await waitFor(File(p.join(fake.dir, 'ending')).existsSync);
        // The engine's own signal comes a moment later.
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await engine.stop();
        await driving;
        expect(await journal(session, (await onlyRun(session)).id), [
          'run-started a',
          'step-started a',
        ], reason: ending);
      }
    });

    test('while the engine goes on: the step failed', () async {
      final (:code, err: _, :session) = await runGraph(
        oneStep,
        nodes: {'a': 'exit 130'},
      );
      expect(code, 1);
      expect(await journal(session, (await onlyRun(session)).id), [
        'run-started a',
        'step-started a',
        'step-finished 130',
        'run-failed exited with code 130',
      ]);
    });
  });

  group('Engine.stop', () {
    /// An engine for a new session of [graph], whose steps run through
    /// [fake], and that waits [stopTimeout] for its calls to stop.
    Future<({Engine engine, SessionHandle session})> engineOf(
      FakeProgram fake,
      Map<String, Object?> graph, {
      Duration stopTimeout = const Duration(seconds: 10),
    }) async {
      final session = await FsStore(fake.runsDir).createSession(
        graphName: 'graph',
        graph: graph,
        startNodes: [(node: 'a', takesInput: false)],
      );
      final progress = IOSink(Capture());
      addTearDown(progress.close);
      return (
        engine: Engine(
          store: session,
          graph: Graph.fromJson(graph),
          program: GraphProgram([fake.path]),
          progress: progress,
          stopTimeout: stopTimeout,
        ),
        session: session,
      );
    }

    const oneStep = {
      'start': 'a',
      'nodes': {
        'a': {'command': 'a'},
      },
    };

    test('gives a call time to stop on its own', () async {
      final fake = FakeProgram(
        oneStep,
        nodes: {
          'a': '''
trap 'sleep 0.3; echo "cleaned up" >&2; exit 0' TERM
echo \$\$ > a.pid.tmp && mv a.pid.tmp a.pid
while :; do sleep 0.05; done''',
        },
      );
      final (:engine, :session) = await engineOf(fake, oneStep);
      final driving = engine.drive();
      await pidOf(fake, 'a');
      await engine.stop();
      await driving.timeout(const Duration(seconds: 5));
      final run = await onlyRun(session);
      expect(await journal(session, run.id), [
        'run-started a',
        'step-started a',
      ]);
      // The shell may note the `sleep` it lost to the signal first.
      expect(
        logOf(session, (await session.steps(run.id)).single),
        endsWith('cleaned up\n'),
      );
    });

    test('kills a call that has not stopped in time, even when the command '
        'it started keeps its output open', () async {
      final fake = FakeProgram(
        oneStep,
        nodes: {
          // Ignores the end of the call's stdin, and outlives the call.
          'a': '''
trap '' TERM
echo \$PPID > call.pid.tmp && mv call.pid.tmp call.pid
echo \$\$ > a.pid.tmp && mv a.pid.tmp a.pid
i=0
while [ ! -e release ] && [ \$i -lt 200 ]; do
  i=\$((i + 1))
  sleep 0.05
done''',
        },
      );
      final (:engine, :session) = await engineOf(
        fake,
        oneStep,
        stopTimeout: const Duration(milliseconds: 300),
      );
      final driving = engine.drive();
      final call = await pidOf(fake, 'call');
      final command = await pidOf(fake, 'a');
      addTearDown(() async {
        File(p.join(fake.dir, 'release')).createSync();
        await waitFor(() => !isAlive(command));
      });
      await engine.stop().timeout(const Duration(seconds: 5));
      await driving.timeout(const Duration(seconds: 5));
      expect(isAlive(call), isFalse);
      expect(await journal(session, (await onlyRun(session)).id), [
        'run-started a',
        'step-started a',
      ]);
    });
  });
}
